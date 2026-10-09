#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resource_group="${RESOURCE_GROUP:-rg-litellm-gateway-demo-eus2}"
cluster_name="${AKS_NAME:-litellm-demo-aks}"
namespace="litellm"
release_name="litellm"
chart_version="1.90.2"

if [[ "${APPROVE_KUBERNETES_CHANGES:-}" != "yes" ]]; then
  cat >&2 <<EOF
This script mutates the target AKS cluster by creating the LiteLLM namespace,
configuration, master-key Secret, service account, and Helm release.
Set APPROVE_KUBERNETES_CHANGES=yes only after explicit approval.
EOF
  exit 1
fi

az aks get-credentials \
  --resource-group "$resource_group" \
  --name "$cluster_name" \
  --overwrite-existing

kubectl apply -f "$repo_root/kubernetes/namespace.yaml"

kubectl create configmap litellm-config \
  --namespace "$namespace" \
  --from-file=config.yaml="$repo_root/litellm/config.yaml" \
  --dry-run=client \
  --output yaml | kubectl apply -f -

if ! kubectl get secret litellm-master-key --namespace "$namespace" >/dev/null 2>&1; then
  master_key="sk-$(openssl rand -hex 24)"
  kubectl create secret generic litellm-master-key \
    --namespace "$namespace" \
    --from-literal=master-key="$master_key"
  unset master_key
fi

workload_client_id="$(az identity show \
  --resource-group "$resource_group" \
  --name litellm-demo-workload-id \
  --query clientId \
  --output tsv)"

helm upgrade --install "$release_name" \
  oci://ghcr.io/berriai/litellm-helm \
  --version "$chart_version" \
  --namespace "$namespace" \
  --values "$repo_root/kubernetes/values.yaml" \
  --set-string "serviceAccount.annotations.azure\\.workload\\.identity/client-id=$workload_client_id" \
  --wait \
  --timeout 10m
