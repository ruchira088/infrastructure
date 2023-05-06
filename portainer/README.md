Start-up command for Portainer

```
docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    -p 9000:9000 \
    --name portainer \
    --restart=unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /home/ruchira/Data/portainer:/data \
    portainer/portainer-ce:latest
```