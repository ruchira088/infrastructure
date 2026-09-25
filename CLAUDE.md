# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal home-lab and AWS infrastructure: plain Kubernetes manifests, Terraform, Docker Compose stacks, and host setup scripts/runbooks. There is no build, lint, or test tooling and no CI. Changes are applied by hand against live systems, so validate with dry runs (see below) rather than applying.

## Targets and how each directory is applied

| Directory | Target | Apply with |
|---|---|---|
| `k8s/apps/<app>/` | k3s cluster on the `home` server (kube context `home`) | `kubectl --context home apply -f k8s/apps/<app>` |
| `k8s/setup-k8s.yaml` + `k8s/k8s-resource-files/` | Cluster bootstrap: cert-manager, `lets-encrypt` ClusterIssuer, Headlamp | `ansible-playbook k8s/setup-k8s.yaml` (run from `k8s/`, uses `~/.kube/config`) |
| `torrents/` | qBittorrent + gluetun ExpressVPN sidecar on the k3s cluster; follows the `k8s/apps/` conventions. Needs host dirs and the `expressvpn-credentials` Secret first (see `torrents/README.md`) | `kubectl --context home apply -f torrents` |
| `monitoring/` | kube-prometheus-stack Helm release | `monitoring/install.sh` (`KUBE_CONTEXT` defaults to `home`) |
| `elk-logs/` | Docker Compose ELK stack (see `elk-logs/README.md`) | `docker compose up -d` with a `.env` copied from `.env.example` |
| `portainer/*/docker-compose.yml` | Stacks deployed through Portainer on a Docker host | Portainer UI |
| `mergerfs/` | Disk pool + Samba share on the `home` server | `scp` the script, then `ssh -t home 'sudo bash /tmp/<script>.sh'`. **`setup_mergerfs.sh` wipes disks.** |
| `k8s/k3s/{single,cluster}`, `k8s/route-53-credentials`, `github/terraform` | AWS (`ap-southeast-2`) | `terraform init && terraform plan` inside the directory |
| `raid/`, `samba/` | Runbooks only (Markdown) | — |

Validation commands to use instead of applying:

```bash
kubectl --context home apply --dry-run=server -f k8s/apps/<app>
terraform -chdir=<dir> validate   # or plan
docker compose -f elk-logs/docker-compose.yml config
```

## Kubernetes conventions (`k8s/apps/`)

- **One directory per app, one resource per file**, named after the kind (`Namespace.yaml`, `Deployment.yaml`, `Service.yaml`, `Ingress.yaml`, `Certificate.yaml`). Multi-component apps prefix with the component (`kafka/Console-Deployment.yaml`, `kafka/SchemaRegistry-Service.yaml`). Each app gets its own namespace.
- **Ingress is k3s's bundled Traefik**, so Ingresses omit `ingressClassName`. Traefik-specific features use `traefik.io/v1alpha1` CRDs, e.g. `Middleware`.
- **TLS**: public hostnames are `<app>.home.ruchij.com`. Apps under `k8s/apps/` declare an explicit cert-manager `Certificate` (issuer `ClusterIssuer/lets-encrypt`, secret `<app>-tls-secret`) that the Ingress's `tls.secretName` references. `monitoring/ingress.yaml` uses the `cert-manager.io/cluster-issuer` annotation instead. The issuer does a DNS-01 challenge against Route 53.
- **Auth**: tinyauth (`k8s/apps/auth`) is the shared SSO gateway. Put a UI behind it by adding a `forwardAuth` Middleware pointing at `http://tinyauth.auth.svc.cluster.local:3000/api/auth/traefik` in the app's namespace (copy `kafka/Console-Middleware.yaml`) and referencing it from the Ingress.
- **Storage is single-node `hostPath`** on the `home` server: app state lives under `/home/ruchira/Data/<app>`, and media under `/media/...` (the mergerfs pool, `/mnt/storage`). Prometheus uses the k3s `local-path` StorageClass.
- Images are pinned to explicit versions. Version bumps are their own commits.

## Secrets flow

Secrets are never committed. `.env`, `kubeconfig`, `output/`, and `.terraform*` are gitignored.
- cert-manager's Route 53 IAM credentials are created by `k8s/route-53-credentials` (Terraform) and stored in SSM (`/k8s/cert-manager/*`). `setup-k8s.yaml` looks them up with `aws_ssm`, renders the Jinja-templated `k8s-resource-files/cluster-issuer/*.yaml` into `output/`, and applies from there. Keep the `{{ ... }}` placeholders in those source files.
- The Grafana admin secret is generated once by `monitoring/install.sh` if it's missing.
- For the ELK stack, `elasticsearch-init` (`elk-logs/elasticsearch/init.sh`) re-creates users, roles, the ILM policy, and the index template from `.env` on every run. Passwords changed in the Kibana UI get reset.

## Terraform

- All roots use the S3 backend `terraform.ruchij.com` (region `ap-southeast-2`) with a distinct state key per root. A new root needs a new key.
- `k8s/k3s/modules/k3s-server` is the shared EC2 module. It assumes pre-existing AWS resources: VPC, `public-sg` security group, subnets tagged `Type=public`, and key pair `My MacBook Pro`.
- `github/terraform` defines the GitHub Actions OIDC role (AdministratorAccess), which is scoped by the `token.actions.githubusercontent.com:sub` `StringLike` patterns. Edit that list carefully.
