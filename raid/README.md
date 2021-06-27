## RAID-5 Setup Guide

#### Creating the RAID-5 Array

(1) Identify the disks for the RAID array
```
$ lsblk

NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
loop0    7:0    0  55.4M  1 loop /snap/core18/2066
loop1    7:1    0  99.4M  1 loop /snap/core/11187
sda      8:0    0     4G  0 disk 
sdb      8:16   0     4G  0 disk 
sdc      8:32   0    40G  0 disk 
├─sdc1   8:33   0   512M  0 part /boot/efi
├─sdc2   8:34   0     1K  0 part 
└─sdc5   8:37   0  39.5G  0 part /
sdd      8:48   0     4G  0 disk 
sr0     11:0    1  1024M  0 rom  
```
In the above case, the disks are `sda`, `sdb` & `sdd`

(2) Create the RAID-5 array using `mdadm`
```
$ sudo mdadm \
    --create --verbose \
    /dev/md0 \
    --level=5 --raid-devices=3 \
    /dev/sda /dev/sdb /dev/sdd

mdadm: layout defaults to left-symmetric
mdadm: layout defaults to left-symmetric
mdadm: chunk size defaults to 512K
mdadm: size set to 4189184K
mdadm: Fail create md0 when using /sys/module/md_mod/parameters/new_array
mdadm: Defaulting to version 1.2 metadata
mdadm: array /dev/md0 started.    
```

(3) Monitor the progress of the RAID array creation
```
$ cat /proc/mdstat

Personalities : [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid1] [raid10] 
md0 : active raid5 sdd[3] sdb[1] sda[0]
      8378368 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [UU_]
      [=======>.............]  recovery = 36.2% (1519256/4189184) finish=0.2min speed=217037K/sec

$ cat /proc/mdstat

Personalities : [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid1] [raid10] 
md0 : active raid5 sdd[3] sdb[1] sda[0]
      8378368 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [UU_]
      [========>............]  recovery = 42.9% (1800832/4189184) finish=0.1min speed=200092K/sec
```

(4) Create and mount the file system

```
$ sudo mkfs.ext4 -F /dev/md0
$ sudo mkdir -p /mnt/md0
$ sudo mount /dev/md0 /mnt/md0
```

(5) Verify the array has finished assembling

```
$ cat /proc/mdstat 

Personalities : [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid1] [raid10] 
md0 : active raid5 sdd[3] sdb[1] sda[0]
      8378368 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/3] [UUU]
      
unused devices: <none>
```

(6) Post creation steps

```
$ sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf

ARRAY /dev/md0 metadata=1.2 name=ubuntu:0 UUID=3365bd05:bb0ff5f8:beb433be:0c25ab59

$ sudo update-initramfs -u

update-initramfs: Generating /boot/initrd.img-5.8.0-59-generic

$ echo '/dev/md0 /mnt/md0 ext4 defaults,nofail,discard 0 0' | sudo tee -a /etc/fstab

/dev/md0 /mnt/md0 ext4 defaults,nofail,discard 0 0
```

#### Rebuilding the RAID-5 Array

The following instructions outline how to rebuild the RAID-5 array when a disk has been replaced.

(1) Unmount the RAID-5 array
```
$ sudo umount /dev/md0

umount: /dev/md0: not mounted.
```

(2) Stop the array
```
$ sudo mdadm --stop /dev/md0

mdadm: stopped /dev/md0
```

(3) Assemble for array
```
$ sudo mdadm --assemble --force -v /dev/md0

mdadm: No super block found on /dev/loop0 (Expected magic a92b4efc, got 401f129b)
mdadm: no RAID superblock on /dev/loop0
mdadm: /dev/sdb is identified as a member of /dev/md0, slot 1.
mdadm: /dev/sda is identified as a member of /dev/md0, slot 0.
mdadm: added /dev/sdb to /dev/md0 as 1
mdadm: no uptodate device for slot 2 of /dev/md0
mdadm: added /dev/sda to /dev/md0 as 0
mdadm: /dev/md0 has been started with 2 drives (out of 3).
```

(4) Examine the details of the RAID array

```
$ sudo mdadm -D /dev/md0

/dev/md0:
           Version : 1.2
     Creation Time : Sat Jun 26 23:13:59 2021
        Raid Level : raid5
        Array Size : 8378368 (7.99 GiB 8.58 GB)
     Used Dev Size : 4189184 (4.00 GiB 4.29 GB)
      Raid Devices : 3
     Total Devices : 2
       Persistence : Superblock is persistent

       Update Time : Sat Jun 26 23:29:05 2021
             State : clean, degraded 
    Active Devices : 2
   Working Devices : 2
    Failed Devices : 0
     Spare Devices : 0

            Layout : left-symmetric
        Chunk Size : 512K

Consistency Policy : resync

              Name : ubuntu:0  (local to host ubuntu)
              UUID : 3365bd05:bb0ff5f8:beb433be:0c25ab59
            Events : 18

    Number   Major   Minor   RaidDevice State
       0       8        0        0      active sync   /dev/sda
       1       8       16        1      active sync   /dev/sdb
       -       0        0        2      removed
```

(5) Mount the RAID array

```
$ sudo mount /dev/md0 /mnt/md0
```

(6) Verify the data

```
$ ls /mnt/md0/
 
 file_example_MP4_1920_18MG.mp4   lost+found               'Sample Video File For Testing.mp4'
 greeting.txt                     metaxas-keller-Bell.mp4
 lion-sample.mp4                  sample_3840x2160.mp4
```

(7) Identify the drive to be added to the array
```
$ lsblk

NAME   MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
loop0    7:0    0  10.5M  1 loop  /snap/kubectl/1976
loop1    7:1    0  99.4M  1 loop  /snap/core/11187
sda      8:0    0     4G  0 disk  
└─md0    9:0    0     8G  0 raid5 
sdb      8:16   0     4G  0 disk  
└─md0    9:0    0     8G  0 raid5 
sdc      8:32   0     4G  0 disk  
sdd      8:48   0    40G  0 disk  
├─sdd1   8:49   0   512M  0 part  /boot/efi
├─sdd2   8:50   0     1K  0 part  
└─sdd5   8:53   0  39.5G  0 part  /
sr0     11:0    1  1024M  0 rom
```

In the above scenario, `sdc` needs to be added to the RAID array.

(8) Add the new drive to the RAID array

```
$ sudo mdadm --add /dev/md0 /dev/sdc

mdadm: added /dev/sdc
```

(9) Monitor the progress of the rebuild process

```
$ cat /proc/mdstat 

Personalities : [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid1] [raid10] 
md0 : active raid5 sda[4] sdb[1] sdc[3]
      8378368 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [_UU]
      [==========>..........]  recovery = 54.3% (2278812/4189184) finish=0.1min speed=207164K/sec
      
unused devices: <none>

$ cat /proc/mdstat 

Personalities : [raid6] [raid5] [raid4] [linear] [multipath] [raid0] [raid1] [raid10] 
md0 : active raid5 sda[4] sdb[1] sdc[3]
      8378368 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [_UU]
      [===============>.....]  recovery = 76.4% (3203840/4189184) finish=0.0min speed=213589K/sec
      
unused devices: <none>
```

(10) Once the rebuild process is completed, the array state should be `clean`

```
$ sudo mdadm -D /dev/md0
/dev/md0:
           Version : 1.2
     Creation Time : Sat Jun 26 23:13:59 2021
        Raid Level : raid5
        Array Size : 8378368 (7.99 GiB 8.58 GB)
     Used Dev Size : 4189184 (4.00 GiB 4.29 GB)
      Raid Devices : 3
     Total Devices : 3
       Persistence : Superblock is persistent

       Update Time : Sun Jun 27 00:00:46 2021
             State : clean 
    Active Devices : 3
   Working Devices : 3
    Failed Devices : 0
     Spare Devices : 0

            Layout : left-symmetric
        Chunk Size : 512K

Consistency Policy : resync

              Name : ubuntu:0  (local to host ubuntu)
              UUID : 3365bd05:bb0ff5f8:beb433be:0c25ab59
            Events : 66

    Number   Major   Minor   RaidDevice State
       4       8        0        0      active sync   /dev/sda
       1       8       16        1      active sync   /dev/sdb
       3       8       32        2      active sync   /dev/sdc
```