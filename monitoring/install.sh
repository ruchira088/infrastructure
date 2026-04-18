#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

KUBE_CONTEXT="${KUBE_CONTEXT:-home}"
NAMESPACE="monitoring"
RELEASE="kube-prometheus-stack"

kubectl --context "$KUBE_CONTEXT" apply -f namespace.yaml

if ! kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get secret grafana-admin >/dev/null 2>&1; then
  echo "Creating grafana-admin secret (one-time)..."
  PASSWORD="$(openssl rand -base64 24)"
  kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$PASSWORD"
  echo
  echo "Grafana admin password: $PASSWORD"
  echo "(retrieve later: kubectl --context $KUBE_CONTEXT -n $NAMESPACE get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
  echo
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community

helm --kube-context "$KUBE_CONTEXT" upgrade --install "$RELEASE" \
  prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --values values.yaml \
  --timeout 10m \
  --wait

kubectl --context "$KUBE_CONTEXT" apply -n "$NAMESPACE" -f certificate.yaml
kubectl --context "$KUBE_CONTEXT" apply -n "$NAMESPACE" -f ingress.yaml

echo
echo "Done. Grafana: https://grafana.home.ruchij.com"
