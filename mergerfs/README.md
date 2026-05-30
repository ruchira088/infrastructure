# mergerfs storage pool (`home`)

Pools all the spinning HDDs on the `home` server into a single mount at
**`/mnt/storage`** using [mergerfs](https://github.com/trapexit/mergerfs).

## Design

- Each disk has its **own independent ext4 filesystem**, mounted at `/mnt/disk1`…`/mnt/diskN`.
- mergerfs unions those mounts (`/mnt/disk*`) into one pool at `/mnt/storage`.
- **No redundancy.** Files are written whole onto individual disks, so if one
  disk dies you lose **only that disk's files** — the rest of the pool keeps
  working. (This is why mergerfs is used instead of LVM/RAID-0, where a single
  disk failure takes down the entire volume.)

This is deliberately *not* striped and *not* parity-protected. If you later want
the ability to rebuild a failed disk, add [SnapRAID](https://www.snapraid.it/)
on top (dedicate one or more disks to parity) — mergerfs + SnapRAID compose well.

## Current disks

| Mount        | Label   | Size  | Model                    |
|--------------|---------|-------|--------------------------|
| `/mnt/disk1` | `disk1` | 8 TB  | WDC WD80EFBX-68AZZN0     |
| `/mnt/disk2` | `disk2` | 8 TB  | ST8000DM004-2U9188       |
| `/mnt/disk3` | `disk3` | 8 TB  | ST8000DM004-2U9188       |
| `/mnt/disk4` | `disk4` | 3 TB  | WDC WD30EZRZ-22Z5HB0     |
| `/mnt/disk5` | `disk5` | 8 TB  | ST8000DM004-2U9188       |
| `/mnt/disk6` | `disk6` | 8 TB  | ST8000DM004-2U9188       |
| `/mnt/disk7` | `disk7` | 8 TB  | ST8000DM004-2U9188       |
| `/mnt/disk8` | `disk8` | 3 TB  | WDC WD30EZRZ-22Z5HB0     |
| `/mnt/disk9` | `disk9` | 3 TB  | WDC WD30EZRZ-22Z5HB0     |

> The `disk1..9` numbering follows the `sda..sdi` order at setup time. Disks are
> mounted by **ext4 label** (not `/dev/sdX`, which can change across reboots).
> The OS NVMe drive (`nvme0n1`) is **not** part of the pool.

## mergerfs options (in `/etc/fstab`)

```
/mnt/disk*  /mnt/storage  fuse.mergerfs  cache.files=off,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=mergerfs,allow_other,use_ino  0  0
```

| Option                  | Why                                                           |
|-------------------------|---------------------------------------------------------------|
| `category.create=mfs`   | New files go to the disk with **most free space** (balances). |
| `moveonenospc=true`     | If a disk fills mid-write, move the file to another disk.      |
| `minfreespace=20G`      | Don't pick a disk for new files once it drops below 20 GB.     |
| `allow_other`           | Non-root users / containers can access the pool.               |
| `use_ino`               | Consistent inode numbers across the pool.                      |
| `cache.files=off`       | Safe default; raise to `partial`/`full` for read-heavy loads.  |

## Initial setup

The whole pool is built by `setup_mergerfs.sh` (**destructive — wipes every
listed disk**). It safety-checks that no target is the NVMe OS disk or currently
mounted, then makes you type `WIPE` to confirm.

```bash
# copy the script over, then run it interactively (needs sudo password + WIPE confirm)
scp setup_mergerfs.sh home:/tmp/
ssh -t home 'sudo bash /tmp/setup_mergerfs.sh'
```

The script: wipes each disk → one GPT partition → ext4 (labeled `diskN`) →
installs mergerfs → writes a managed block to `/etc/fstab` (backs up the old
one) → mounts everything. Re-running it is idempotent for the fstab block, but
it **re-wipes the disks**, so only re-run on a fresh setup.

## Operations

### Check pool health / usage

```bash
df -h /mnt/storage          # total pooled space
df -h /mnt/disk*            # per-disk usage
mergerfs --version
```

### Add a new disk to the pool

1. Identify the new device (e.g. `/dev/sdj`): `lsblk`
2. Partition + format + label with the next number:
   ```bash
   sudo wipefs -a /dev/sdj
   sudo sgdisk --zap-all /dev/sdj
   sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:disk10 /dev/sdj
   sudo partprobe /dev/sdj
   sudo mkfs.ext4 -F -m 0 -L disk10 /dev/sdj1
   sudo mkdir -p /mnt/disk10
   ```
3. Add to `/etc/fstab` (inside the managed block):
   ```
   LABEL=disk10  /mnt/disk10  ext4  defaults,noatime,nofail  0  2
   ```
4. Mount it: `sudo mount /mnt/disk10`

The `/mnt/disk*` glob means mergerfs picks up the new branch automatically once
it's mounted (a remount of the pool — `sudo mount -o remount /mnt/storage` — or
reboot ensures it's registered).

### Replace / remove a failed disk

Because there's no redundancy, **the data on a failed disk is gone.** To swap in
a replacement:

1. Unmount and comment out the dead disk's fstab line, or pull it physically.
2. The pool keeps serving every other disk's files immediately (`nofail` ensures
   boot isn't blocked by the missing disk).
3. Provision the replacement using the **Add a new disk** steps above, reusing
   the same `diskN` label so the layout stays tidy.

### What survives a disk failure

Run this any time to see which files live on which disk (so you know what you'd
lose if a specific disk died):

```bash
ls -l /mnt/disk3        # files physically on disk3
```

Files are stored whole per-disk, so per-disk listing is an accurate inventory.

## File sharing (Samba)

The pool is exported over SMB/CIFS as an **authenticated, read-write** share
named `[storage]`, suitable for both file-server use and as a media library that
Jellyfin/Plex (running locally on `home`) read directly from `/mnt/storage`.

Built by `setup_samba.sh`, which:

1. `chown -R ruchira:ruchira /mnt/storage` + `775` dirs / `664` files
   (ownership passes through mergerfs to the real files on each disk).
2. Installs Samba and writes a managed `[storage]` block to
   `/etc/samba/smb.conf` (backing up the old config first).
3. Prompts to set the **Samba password** for `ruchira` (separate from the Linux
   login password — it's the credential clients use), then enables the account.
4. Validates with `testparm` and restarts `smbd`/`nmbd`.

```bash
scp setup_samba.sh home:/tmp/
ssh -t home 'sudo bash /tmp/setup_samba.sh'   # needs sudo password + sets SMB password
```

### Share definition (`/etc/samba/smb.conf`)

```ini
[storage]
   path = /mnt/storage
   browseable = yes
   read only = no
   valid users = ruchira
   force user = ruchira
   force group = ruchira
   create mask = 0664
   directory mask = 0775
```

`force user`/`force group = ruchira` keeps every file written via SMB
consistently owned, regardless of which client wrote it.

### Connecting

| Client  | Address |
|---------|---------|
| macOS   | Finder → ⌘K → `smb://home.ruchij.com/storage` (log in as `ruchira`) |
| Windows | `\\home.ruchij.com\storage` |
| Linux   | `sudo mount -t cifs //home.ruchij.com/storage /mnt/x -o username=ruchira` |

### Operations

```bash
# Reset / change the SMB password for ruchira
sudo smbpasswd ruchira

# Add another SMB user (the Linux user must already exist)
sudo smbpasswd -a someuser    # then add them to `valid users` in smb.conf

# Validate config after editing smb.conf
testparm -s

# Restart after config changes
sudo systemctl restart smbd nmbd

# Who's currently connected
sudo smbstatus
```

## Notes

- `nofail` on every branch means a missing/dead disk won't hang boot.
- Don't write directly to `/mnt/diskN` while also using the pool unless you know
  why — write through `/mnt/storage` so mergerfs applies the create policy.
- Source scripts of record live in this repo: `setup_mergerfs.sh` (pool) and
  `setup_samba.sh` (ownership + SMB share).
