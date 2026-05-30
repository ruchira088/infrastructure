#!/usr/bin/env bash
#
# Pool all spinning HDDs into a single mergerfs mount (/mnt/storage).
# Each disk gets its own ext4 filesystem => losing one disk loses ONLY that
# disk's data; the rest of the pool keeps working. No redundancy.
#
# DESTRUCTIVE: wipes every disk listed in DISKS.
set -euo pipefail

# --- The spinning disks to pool. The OS NVMe drive is intentionally absent. ---
DISKS=(sda sdb sdc sdd sde sdf sdg sdh sdi)

POOL=/mnt/storage
MOPTS="cache.files=off,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=mergerfs,allow_other,use_ino"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then red "Run with sudo/root."; exit 1; fi

# --------------------------- Safety checks --------------------------------
bold "Disks targeted for WIPE:"
for d in "${DISKS[@]}"; do
  dev="/dev/$d"
  [[ -b "$dev" ]]            || { red "ERROR: $dev is not a block device"; exit 1; }
  [[ "$d" == nvme* ]]        && { red "ERROR: refusing to touch NVMe $dev"; exit 1; }
  # Refuse if the disk or any of its partitions is currently mounted.
  if lsblk -nro MOUNTPOINT "$dev" | grep -q .; then
    red "ERROR: $dev (or a partition) is mounted. Aborting."; lsblk "$dev"; exit 1
  fi
  size=$(lsblk -ndo SIZE "$dev")
  model=$(lsblk -ndo MODEL "$dev")
  printf '  %-10s %-8s %s\n' "$dev" "$size" "$model"
done
echo
bold "Current signatures on these disks (what will be destroyed):"
for d in "${DISKS[@]}"; do blkid "/dev/$d"* 2>/dev/null || true; done
echo
red "This ERASES all of the above. Type EXACTLY 'WIPE' to continue:"
read -r confirm
[[ "$confirm" == "WIPE" ]] || { echo "Aborted."; exit 1; }

# ------------------------ Wipe / partition / format -----------------------
i=1
for d in "${DISKS[@]}"; do
  dev="/dev/$d"
  bold "=== [$dev] -> disk$i ==="
  wipefs -a "$dev"
  sgdisk --zap-all "$dev"
  sgdisk -n 1:0:0 -t 1:8300 -c 1:"disk$i" "$dev"
  partprobe "$dev"; udevadm settle; sleep 1
  part="${dev}1"
  [[ -b "$part" ]] || { red "ERROR: expected partition $part not found"; exit 1; }
  # -m 0 => no reserved blocks (data disk, reclaim the usual 5%)
  mkfs.ext4 -F -m 0 -L "disk$i" "$part"
  mkdir -p "/mnt/disk$i"
  i=$((i+1))
done
N=$((i-1))

# ------------------------------ Install mergerfs --------------------------
if ! command -v mergerfs >/dev/null; then
  bold "Installing mergerfs..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update && apt-get install -y mergerfs
fi
mergerfs --version || true

# ------------------------------ /etc/fstab --------------------------------
cp -a /etc/fstab "/etc/fstab.bak.$(date +%s)"
# Remove any prior entries we manage (idempotent re-runs)
sed -i '/# >>> mergerfs pool >>>/,/# <<< mergerfs pool <<</d' /etc/fstab

{
  echo "# >>> mergerfs pool >>>"
  for n in $(seq 1 "$N"); do
    echo "LABEL=disk$n  /mnt/disk$n  ext4  defaults,noatime,nofail  0  2"
  done
  echo "/mnt/disk*  $POOL  fuse.mergerfs  $MOPTS  0  0"
  echo "# <<< mergerfs pool <<<"
} >> /etc/fstab

# ------------------------------- Mount ------------------------------------
mkdir -p "$POOL"
systemctl daemon-reload || true
for n in $(seq 1 "$N"); do mount "/mnt/disk$n"; done
mount "$POOL"

# ------------------------------- Report -----------------------------------
echo
green "DONE. Pool layout:"
df -h "$POOL" /mnt/disk* | sed 's/^/  /'
echo
green "Per-disk usage:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "${DISKS[@]/#//dev/}"
