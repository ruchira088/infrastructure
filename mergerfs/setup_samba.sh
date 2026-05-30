#!/usr/bin/env bash
#
# Fix ownership of the mergerfs pool and export it as an authenticated
# Samba share named [storage].
set -euo pipefail

POOL=/mnt/storage
SHARE=storage
OWNER=ruchira
GROUP=ruchira

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then red "Run with sudo/root."; exit 1; fi
mountpoint -q "$POOL" || { red "ERROR: $POOL is not mounted."; exit 1; }
id "$OWNER" >/dev/null 2>&1 || { red "ERROR: user $OWNER does not exist."; exit 1; }

# ---------------------------- Ownership fix -------------------------------
bold "Setting ownership of $POOL to $OWNER:$GROUP (passes through to disks)..."
chown -R "$OWNER:$GROUP" "$POOL"
chmod -R u=rwX,g=rwX,o=rX "$POOL"   # 775 dirs / 664 files

# ------------------------------ Install Samba -----------------------------
if ! command -v smbd >/dev/null; then
  bold "Installing Samba..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update && apt-get install -y samba
fi

# ------------------------- Share config (idempotent) ----------------------
cp -a /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%s)"
# Strip any prior managed block so re-runs don't duplicate it.
sed -i '/# >>> storage share >>>/,/# <<< storage share <<</d' /etc/samba/smb.conf

cat >> /etc/samba/smb.conf <<EOF
# >>> storage share >>>
[$SHARE]
   path = $POOL
   browseable = yes
   read only = no
   valid users = $OWNER
   force user = $OWNER
   force group = $GROUP
   create mask = 0664
   directory mask = 0775
# <<< storage share <<<
EOF

# Validate the config before touching the running service.
testparm -s >/dev/null

# ------------------------- Samba user + password --------------------------
# The unix user already exists; create/refresh its Samba (SMB) credential.
# This PROMPTS for the share password interactively.
bold "Set the Samba password for '$OWNER' (used by clients to connect):"
smbpasswd -a "$OWNER"
smbpasswd -e "$OWNER" >/dev/null

# ------------------------------- Restart ----------------------------------
systemctl enable --now smbd >/dev/null 2>&1 || true
systemctl restart smbd
# nmbd (NetBIOS name resolution) is optional but helps Windows browse.
systemctl restart nmbd 2>/dev/null || true

# ------------------------------- Report -----------------------------------
echo
green "DONE."
echo "Share:        //$(hostname -I | awk '{print $1}')/$SHARE"
echo "Auth user:    $OWNER"
ls -ld "$POOL"
echo
green "Share definition:"
sed -n '/# >>> storage share >>>/,/# <<< storage share <<</p' /etc/samba/smb.conf
echo
green "Service status:"
systemctl --no-pager --lines=0 status smbd | head -3
