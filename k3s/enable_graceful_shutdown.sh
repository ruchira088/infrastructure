#!/usr/bin/env bash
# Enable kubelet graceful node shutdown on the home k3s server.
#
# Without it, a reboot hard-kills containers (exit 255 / Unknown) and the
# kubelet restarts them in place, bumping every pod's restart count. With it,
# the kubelet holds a systemd shutdown inhibitor, sends pods SIGTERM, and
# controllers replace them with fresh pods after boot.
#
# Run on the server: scp this file, then `ssh -t home 'sudo bash /tmp/enable_graceful_shutdown.sh'`
set -euo pipefail

GRACE=60s
CRITICAL_GRACE=10s
CONFIG=/etc/rancher/k3s/config.yaml

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

if [[ -f $CONFIG ]] && grep -q 'kubelet-arg' "$CONFIG"; then
  echo "$CONFIG already has kubelet-arg; merge these by hand:" >&2
  echo "  - shutdown-grace-period=$GRACE" >&2
  echo "  - shutdown-grace-period-critical-pods=$CRITICAL_GRACE" >&2
  exit 1
fi

cat >>"$CONFIG" <<EOF
kubelet-arg:
  - "shutdown-grace-period=$GRACE"
  - "shutdown-grace-period-critical-pods=$CRITICAL_GRACE"
EOF
chmod 600 "$CONFIG"

# logind caps inhibitor delays at InhibitDelayMaxSec (default 5s), which would
# cut the grace period short.
mkdir -p /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/99-k3s-graceful-shutdown.conf <<EOF
[Login]
InhibitDelayMaxSec=$GRACE
EOF
# Reload logind config without restarting it (a restart can end desktop sessions).
systemctl kill -s HUP systemd-logind

# Restarting k3s doesn't stop running containers; the containerd shims survive.
systemctl restart k3s

for _ in $(seq 1 30); do
  if systemd-inhibit --list --no-pager | grep -q kubelet; then
    systemd-inhibit --list --no-pager | grep kubelet
    echo "Graceful shutdown enabled."
    exit 0
  fi
  sleep 2
done
echo "kubelet shutdown inhibitor not found; check: journalctl -u k3s | grep -i shutdown" >&2
exit 1
