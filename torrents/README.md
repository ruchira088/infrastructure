# torrents

qBittorrent on the `home` k3s cluster, with all torrent traffic going through ExpressVPN. The web UI is at **https://torrents.home.ruchij.com**, protected by qBittorrent's own login.

## How it works

```
                 ┌──────────────────────── pod: qbittorrent-deployment ─────────────────────────┐
browser ─► Traefik ─► qbittorrent-service:8080 ─► eth0 ─┐                                        │
                                                         │  shared network namespace             │
                                                         ▼                                        │
                 │   qbittorrent-container ──(all egress)──► gluetun-container ──► tun0 ──► ExpressVPN ─► peers
                 │     /config    ← /home/ruchira/Data/qbittorrent                                │
                 │     /downloads ← /mnt/storage/torrents (mergerfs pool)                         │
                 └────────────────────────────────────────────────────────────────────────────────┘
```

- **gluetun** (`qmcgaw/gluetun`) runs as a *native sidecar*, an init container with `restartPolicy: Always`. Kubernetes only starts qBittorrent after gluetun's startup probe passes, which means the VPN is connected.
- The two containers share the pod's network namespace. Gluetun sets up `tun0` and an iptables **kill switch**, and these apply to qBittorrent too. If the VPN drops, qBittorrent's internet traffic is **blocked**. It is never sent through your home IP.
- Two exceptions are allowed through the firewall:
  - `FIREWALL_INPUT_PORTS=8080` lets Traefik and the kubelet reach the web UI.
  - `FIREWALL_OUTBOUND_SUBNETS` covers the k3s pod and service CIDRs (`10.42.0.0/16`, `10.43.0.0/16`), so in-cluster traffic keeps working.
- The VPN credentials and the `.ovpn` config file are the ones `video-downloader-back-end/forward-proxy` uses. They're stored in AWS Secrets Manager as `ExpressVPN/credentials` and `ExpressVPN/vpn-config/<country>`.
- Gluetun runs as a **`custom` provider** with that `.ovpn` file, not with its built-in `expressvpn` provider. The built-in ExpressVPN server list is stale: it points at old servers signed by an old CA, and the TLS handshake fails (`TLS key negotiation failed to occur within 60 seconds`).
- Gluetun requires an IP in the `.ovpn` `remote` line, but ExpressVPN rotates server IPs. So the gluetun container's command resolves the hostname through CoreDNS (`10.43.0.10`) on every start, writes `/gluetun/custom.conf`, and then execs gluetun.

## Files

| File | Resource |
|---|---|
| `Namespace.yaml` | `torrents` namespace |
| `Deployment.yaml` | gluetun sidecar + qBittorrent |
| `Service.yaml` | `qbittorrent-service` (port `webui-port` 8080) |
| `Certificate.yaml` | Let's Encrypt cert for `torrents.home.ruchij.com` → `torrents-tls-secret` |
| `Ingress.yaml` | Routes `torrents.home.ruchij.com` to the service (Traefik, TLS from `torrents-tls-secret`) |

The `expressvpn-credentials` Secret is **not** in git. You create it by hand in step 3.

## Prerequisites

- `kubectl` with the `home` context
- `aws` CLI with access to Secrets Manager in `ap-southeast-2`, plus `jq`
- `ssh home` access with sudo
- The cluster is already bootstrapped: cert-manager + `lets-encrypt` ClusterIssuer (`k8s/setup-k8s.yaml`)
- `torrents.home.ruchij.com` resolves to the home server. The `*.home.ruchij.com` records used by the other apps cover this.
- The mergerfs pool is mounted at `/mnt/storage` (see `mergerfs/`)

## Install

Run everything from the repository root.

### 1. Create the host directories

Both volumes are `hostPath` with `type: Directory`, so the pod won't start until they exist. They must be owned by UID/GID 1000 (`ruchira`), because qBittorrent runs as that user (`PUID`/`PGID`). Kubernetes creates missing directories as root, which is why you create them yourself.

```bash
ssh home 'mkdir -p ~/Data/qbittorrent && sudo install -d -o 1000 -g 1000 -m 775 /mnt/storage/torrents'
ssh home 'ls -ld ~/Data/qbittorrent /mnt/storage/torrents'   # both should be owned by ruchira
```

### 2. Create the namespace

```bash
kubectl --context home apply -f torrents/Namespace.yaml
```

### 3. Create the VPN credentials Secret

This reads three things from AWS Secrets Manager into one Secret: the ExpressVPN OpenVPN username, the password, and the `.ovpn` config for the server location. The credentials are the *manual configuration* ones from https://www.expressvpn.com/setup#manual, not your account login. Change `au` to `nz` to use New Zealand instead.

```bash
CREDS=$(aws secretsmanager get-secret-value --region ap-southeast-2 \
  --secret-id ExpressVPN/credentials --query SecretString --output text)

kubectl --context home -n torrents create secret generic expressvpn-credentials \
  --from-literal=OPENVPN_USER="$(jq -r .OPENVPN_USER <<<"$CREDS")" \
  --from-literal=OPENVPN_PASSWORD="$(jq -r .OPENVPN_PASS <<<"$CREDS")" \
  --from-literal=expressvpn.ovpn="$(aws secretsmanager get-secret-value --region ap-southeast-2 \
    --secret-id ExpressVPN/vpn-config/au --query SecretString --output text)"

unset CREDS
```

### 4. Validate, then deploy

```bash
kubectl --context home apply --dry-run=server -f torrents
kubectl --context home apply -f torrents
```

`kubectl apply -f torrents` only picks up `*.yaml`/`*.json` files, so this README is ignored.

### 5. Wait for it to come up

```bash
kubectl --context home -n torrents get pods -w
```

The pod shows `Init:0/1` while gluetun connects, which usually takes 10–30s. After that it shows `2/2 Running`. The certificate can take a minute or two because of the DNS-01 challenge:

```bash
kubectl --context home -n torrents get certificate   # READY should be True
```

### 6. First login

1. Open https://torrents.home.ruchij.com. qBittorrent's login page appears.
2. The username is `admin`. The linuxserver image prints a **temporary password** in the logs on first start:
   ```bash
   kubectl --context home -n torrents logs deploy/qbittorrent-deployment -c qbittorrent-container | grep -i password
   ```
3. Go to **Tools → Options → WebUI**, set a **strong** permanent password, and save. The temporary password changes on every restart until you do this. This login is the only thing protecting the UI, so don't reuse a weak password.

### 7. Recommended qBittorrent settings

Under **Tools → Options**:

- **Downloads → Default Save Path:** `/downloads` (the default in this image). Files end up in `/mnt/storage/torrents` on the host.
- **Advanced → Disk IO type (libtorrent):** **POSIX-compliant**, then restart the pod. This is **required**. `/downloads` is on the mergerfs pool, which is mounted with `cache.files=off`, so FUSE can't memory-map files. With the default (mmap) setting, every torrent goes straight to *Errored* with `file_mmap ... error: No such device`.
- **Advanced → Network interface:** `tun0`. The gluetun firewall already enforces the VPN. Binding to `tun0` adds a second layer, because qBittorrent then refuses to use any other interface.
- **Connection → Listening port:** turn off *Use UPnP / NAT-PMP*. It does nothing through the VPN.
- **WebUI → Enable reverse proxy support:** turn it on and set *Trusted proxies* to `10.42.0.0/16`. Every request reaches qBittorrent from the Traefik pod, so without this setting qBittorrent sees one IP for everyone. Its brute-force protection (a ban after repeated failed logins) would then lock **everyone** out, not just the attacker. With the setting on, qBittorrent reads the real client IP from Traefik's `X-Forwarded-For` header.
- **WebUI:** leave *Bypass authentication for clients in whitelisted IP subnets* **off**. Whitelisting `10.42.0.0/16` would let every request through Traefik skip the login.

## Verify the VPN

These checks are worth running after every install or upgrade.

```bash
POD=deploy/qbittorrent-deployment

# 1. Public IP seen by qBittorrent. It must be an ExpressVPN IP, NOT your home IP.
kubectl --context home -n torrents exec $POD -c qbittorrent-container -- curl -s https://ifconfig.me; echo
curl -s https://ifconfig.me; echo    # your home IP, for comparison

# 2. Gluetun's own view (public IP, country, VPN status)
kubectl --context home -n torrents logs $POD -c gluetun-container | grep -Ei 'public ip|healthy|vpn'

# 3. Kill switch: stop OpenVPN, then check that qBittorrent CANNOT reach the internet
kubectl --context home -n torrents exec $POD -c gluetun-container -- pkill openvpn
kubectl --context home -n torrents exec $POD -c qbittorrent-container -- curl -s --max-time 10 https://ifconfig.me \
  || echo "blocked, kill switch works"
# Gluetun restarts the tunnel by itself. Re-run check 1 after about 30s.
```

For an end-to-end test, add a legal torrent (e.g. an Ubuntu ISO) and check that it downloads into `/mnt/storage/torrents`. You can also add a tracker-based IP-check torrent (e.g. from ipleak.net) and confirm that only the VPN IP shows up.

## Operations

### Change the VPN location

The location comes from the `.ovpn` file in the Secret. Secrets Manager has `ExpressVPN/vpn-config/au` and `ExpressVPN/vpn-config/nz`. For any other location, download its `.ovpn` from https://www.expressvpn.com/setup#manual and store it as a new `ExpressVPN/vpn-config/<country>` secret. Then recreate the Secret (delete it and re-run step 3 with the new `--secret-id`) and restart:

```bash
kubectl --context home -n torrents rollout restart deploy/qbittorrent-deployment
```

### Rotate the VPN credentials

```bash
kubectl --context home -n torrents delete secret expressvpn-credentials
# re-run step 3, then restart so gluetun picks up the new values:
kubectl --context home -n torrents rollout restart deploy/qbittorrent-deployment
```

### Upgrade images

Both images are pinned. Bump the tag in `Deployment.yaml`, re-apply, and run the VPN checks again. Per the repo convention, each version bump is its own commit.

- gluetun: https://github.com/qdm12/gluetun/releases
- qBittorrent: https://github.com/linuxserver/docker-qbittorrent/releases

The Deployment uses `strategy: Recreate`, so the old pod stops before the new one starts. That prevents two qBittorrents from writing to the same `/config`, and also means a few seconds of downtime.

### Logs

```bash
kubectl --context home -n torrents logs deploy/qbittorrent-deployment -c gluetun-container -f
kubectl --context home -n torrents logs deploy/qbittorrent-deployment -c qbittorrent-container -f
```

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Pod stuck in `ContainerCreating`, event says `hostPath type check failed` | A host directory is missing. Re-run step 1. |
| Pod stuck in `Init:0/1` / gluetun `CrashLoopBackOff` | Read the gluetun logs. `AUTH_FAILED` means the credentials are wrong: check the Secret and the Secrets Manager values. `TLS key negotiation failed` means the server or CA in the `.ovpn` is out of date: download a fresh `.ovpn` from ExpressVPN. `Could not resolve` means CoreDNS isn't reachable at `10.43.0.10`. `TUN device not found` means `/dev/net/tun` is missing on the host (`ssh home ls -l /dev/net/tun`). |
| `CreateContainerConfigError` | The `expressvpn-credentials` Secret is missing or has the wrong key names. It needs `OPENVPN_USER`, `OPENVPN_PASSWORD` and `expressvpn.ovpn`. |
| qBittorrent never becomes Ready, or the web UI returns 502/504 | Gluetun's firewall is dropping inbound traffic to 8080. Check that `FIREWALL_INPUT_PORTS=8080` is set and that the port matches `WEBUI_PORT`. |
| qBittorrent says "Unauthorized" / blank page through the ingress | Host header / CSRF protection. Under **Options → WebUI**, add `torrents.home.ruchij.com` to *Server domains*, or disable *Host header validation*. |
| Torrent goes straight to *Errored*; log shows `file_mmap ... error: No such device` | Disk IO type is still mmap, which mergerfs doesn't support. Set **Advanced → Disk IO type** to *POSIX-compliant*, restart the pod, then *Force recheck* the torrent. |
| Downloads fail with "Permission denied" | `/mnt/storage/torrents` isn't owned by UID 1000: `ssh home sudo chown -R 1000:1000 /mnt/storage/torrents` |
| Certificate not Ready | `kubectl --context home -n torrents describe certificate torrents-certificate`, then check the cert-manager logs (Route 53 DNS-01). |

## Limitations

- **No incoming peer connections.** ExpressVPN doesn't support port forwarding. Downloading works normally, but you can only connect to peers that accept incoming connections, and seeding ratios will be lower.
- **Single node only.** State lives in `hostPath` directories on the `home` server, like the other apps in this repo.

## Uninstall

```bash
kubectl --context home delete namespace torrents   # removes everything, including the Secret
# downloaded data and config remain on the host:
#   /mnt/storage/torrents, /home/ruchira/Data/qbittorrent
```
