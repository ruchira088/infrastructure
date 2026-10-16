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
# k3s starts the kubelet with --config-dir pointing here; files sort after
# k3s's own 00-k3s-defaults.conf and override it. The --shutdown-grace-period
# kubelet flags were removed in Kubernetes 1.35, so this must be config, not
# kubelet-arg in /etc/rancher/k3s/config.yaml (that crash-loops k3s).
DROPIN_DIR=/var/lib/rancher/k3s/agent/etc/kubelet.conf.d
DROPIN=$DROPIN_DIR/99-graceful-shutdown.conf
K3S_CONFIG=/etc/rancher/k3s/config.yaml

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

# Remove the kubelet-arg block an earlier version of this script appended.
if [[ -f $K3S_CONFIG ]] && grep -q 'shutdown-grace-period' "$K3S_CONFIG"; then
  sed -i '/^kubelet-arg:$/d; /shutdown-grace-period/d' "$K3S_CONFIG"
  if ! grep -q '[^[:space:]]' "$K3S_CONFIG"; then
    rm "$K3S_CONFIG"
  fi
  echo "Removed legacy shutdown-grace-period kubelet-arg from $K3S_CONFIG"
fi

mkdir -p "$DROPIN_DIR"
cat >"$DROPIN" <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
shutdownGracePeriod: $GRACE
shutdownGracePeriodCriticalPods: $CRITICAL_GRACE
EOF

# logind caps inhibitor delays at InhibitDelayMaxSec (default 5s), which would
# cut the grace period short. Drop-ins from /etc and /usr/lib are merged and
# applied in filename order, so the name must sort after Ubuntu's
# unattended-upgrades-logind-maxdelay.conf (30s); "99-" sorts before it.
mkdir -p /etc/systemd/logind.conf.d
rm -f /etc/systemd/logind.conf.d/99-k3s-graceful-shutdown.conf
cat >/etc/systemd/logind.conf.d/zz-k3s-graceful-shutdown.conf <<EOF
[Login]
InhibitDelayMaxSec=$GRACE
EOF
# Apply the new value before k3s restarts: the kubelet checks it only once at
# startup and gives up on the shutdown manager if it is still too low.
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
echo "kubelet shutdown inhibitor not found; check: journalctl -u k3s | grep -iE 'shutdown|error'" >&2
exit 1
