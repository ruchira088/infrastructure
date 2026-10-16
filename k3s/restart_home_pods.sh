#!/usr/bin/env bash
# Delete every running pod in the home cluster one at a time, waiting for the
# namespace to become Ready again before moving on. Recreated pods start with
# 0 restarts. Completed (Job) pods are skipped.
#
# Runs from your machine against kube context `home` (not on the server).
# Usage: k3s/restart_home_pods.sh [namespace ...]   (default: all namespaces)
set -euo pipefail

CTX="home"
TIMEOUT="300s"
k() { kubectl --context "$CTX" "$@"; }

if [[ $# -gt 0 ]]; then
  pods=$(for ns in "$@"; do
    k get pods -n "$ns" --field-selector=status.phase=Running \
      -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'
  done)
else
  pods=$(k get pods -A --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')
fi

total=$(grep -c . <<<"$pods" || true)
i=0
while read -r ns pod; do
  [[ -z "$pod" ]] && continue
  i=$((i + 1))
  echo "[$i/$total] $ns/$pod"
  k delete pod -n "$ns" "$pod" --wait=true
  sleep 3  # give the controller time to create the replacement
  if ! k wait pod --all -n "$ns" --for=condition=Ready \
      --field-selector=status.phase!=Succeeded --timeout="$TIMEOUT"; then
    echo "!! $ns did not become Ready within $TIMEOUT, stopping." >&2
    exit 1
  fi
done <<<"$pods"

echo "Done."
k get pods -A
