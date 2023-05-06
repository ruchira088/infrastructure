```
sudo apt install cifs-utils -y
```

/home/ruchira/.samba_credentials
```
username=ruchira088@live.com
password=<Populate password>
```

/etc/fstab
```
//desktop.internal.ruchij.com/Data /media/data cifs credentials=/home/ruchira/.samba_credentials,dir_mode=0777,file_mode=0777
//desktop.internal.ruchij.com/Media /media/plex cifs credentials=/home/ruchira/.samba_credentials,dir_mode=0777,file_mode=0777
```