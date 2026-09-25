# infrastructure

Configuration for my home lab and the AWS resources behind it: Kubernetes manifests for the k3s cluster on the `home` server, Terraform for AWS, Docker Compose stacks, and setup scripts and runbooks for the server's storage.

Everything is applied by hand. There's no CI.

## Layout

```
k8s/
├── apps/                  # Workloads on the home k3s cluster (one directory per app)
├── k8s-resource-files/    # Cluster add-ons: Let's Encrypt ClusterIssuer, Headlamp
├── setup-k8s.yaml         # Ansible playbook that bootstraps cert-manager + add-ons
├── route-53-credentials/  # Terraform: IAM user for cert-manager DNS-01 challenges
└── k3s/                   # Terraform: k3s on EC2 (single node, or 3-node HA behind an NLB)
monitoring/                # kube-prometheus-stack (Prometheus + Grafana) via Helm
elk-logs/                  # Elasticsearch / Logstash / Kibana stack for application logs
portainer/                 # Docker Compose stacks deployed through Portainer
mergerfs/                  # Disk pool + Samba share on the home server
torrents/                  # qBittorrent on k3s, routed through ExpressVPN (gluetun sidecar)
github/terraform/          # AWS IAM role that GitHub Actions assumes via OIDC
raid/, samba/              # Runbooks: mdadm RAID-5 and CIFS client mounts
```

## Services

Hosted on the `home` k3s cluster behind Traefik. TLS certificates come from Let's Encrypt via cert-manager.

| Service | URL | Source |
|---|---|---|
| Plex | https://plex.home.ruchij.com | `k8s/apps/plex` |
| Jellyfin | https://jellyfin.home.ruchij.com | `k8s/apps/jellyfin` |
| Kafka (Redpanda Console) | https://kafka.home.ruchij.com | `k8s/apps/kafka` |
| tinyauth (SSO) | https://auth.home.ruchij.com | `k8s/apps/auth` |
| Nginx Proxy Manager | https://admin.nginx.home.ruchij.com | `k8s/apps/nginx-proxy-manager` |
| Headlamp (cluster UI) | https://headlamp.home.ruchij.com | `k8s/k8s-resource-files/headlamp` |
| Grafana | https://grafana.home.ruchij.com | `monitoring/` |
| qBittorrent (via ExpressVPN) | https://torrents.home.ruchij.com | `torrents/` |

Nginx Proxy Manager also routes `portainer.home.ruchij.com` and `logs.home.ruchij.com` (Kibana) to services that run outside the cluster.

## Prerequisites

- `kubectl` with a `home` context for the k3s cluster
- `helm`, `ansible` (with the `amazon.aws` collection for SSM lookups), `terraform`
- AWS credentials for account resources in `ap-southeast-2`. Terraform state lives in the `terraform.ruchij.com` S3 bucket.
- Docker with Compose v2 for the ELK stack

## Usage

### Cluster bootstrap (one-time)

```bash
# Create the cert-manager IAM user and store its keys in SSM
terraform -chdir=k8s/route-53-credentials init
terraform -chdir=k8s/route-53-credentials apply

# Install cert-manager, the lets-encrypt ClusterIssuer, and Headlamp (prints the Headlamp admin token)
cd k8s && ansible-playbook setup-k8s.yaml
```

### Deploy or update an app

```bash
kubectl --context home apply --dry-run=server -f k8s/apps/<app>   # check first
kubectl --context home apply -f k8s/apps/<app>
```

Each app directory has its own Namespace, Deployment/StatefulSet, Service, Ingress and Certificate. To put a UI behind tinyauth login, add a Traefik `forwardAuth` Middleware in the app's namespace (see `k8s/apps/kafka/Console-Middleware.yaml`).

### Monitoring

```bash
./monitoring/install.sh   # KUBE_CONTEXT=home by default
```

The first run creates the `grafana-admin` secret and prints the password.

### ELK logs

```bash
cd elk-logs
cp .env.example .env   # fill in passwords and Kibana encryption keys
docker compose up -d
```

Logstash accepts newline-delimited JSON on TCP 5001 and UDP 5002. Logs are kept for 30 days. See [`elk-logs/README.md`](elk-logs/README.md).

### Storage (home server)

The HDDs are pooled with mergerfs at `/mnt/storage` and shared over SMB as `\\home.ruchij.com\storage`. **`setup_mergerfs.sh` wipes the disks**, so run it only on a fresh setup. See [`mergerfs/README.md`](mergerfs/README.md).

### AWS

```bash
terraform -chdir=<dir> init
terraform -chdir=<dir> plan
```

| Directory | Purpose |
|---|---|
| `k8s/k3s/single` | Single k3s node on EC2, with `dev.ruchij.com` and `*.dev.ruchij.com` DNS |
| `k8s/k3s/cluster` | 3-node HA k3s across AZs behind a Network Load Balancer |
| `k8s/route-53-credentials` | IAM user + SSM parameters for cert-manager |
| `github/terraform` | GitHub Actions OIDC provider and IAM role |

## Secrets

Nothing sensitive is committed. `.env`, `kubeconfig`, rendered manifests in `output/`, and Terraform working files are gitignored. Cluster secrets are either pulled from AWS SSM at apply time or generated on first install.
