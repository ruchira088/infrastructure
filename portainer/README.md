Start-up command for Portainer

```
docker run -d \
    -p 9000:9000 \
    --name portainer \
    --restart=unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /home/ruchira/Data/portainer:/data \
    portainer/portainer-ce:lts --trusted-origins=portainer.home.ruchij.com
```