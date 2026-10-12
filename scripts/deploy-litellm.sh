#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resource_group="${RESOURCE_GROUP:-rg-litellm-gateway-demo-eus2}"
cluster_name="${AKS_NAME:-litellm-demo-aks}"
namespace="litellm"
release_name="litellm"
chart_version="1.105.0"

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

if ! kubectl get secret litellm-agent365 --namespace "$namespace" >/dev/null 2>&1; then
  cat >&2 <<EOF
The Kubernetes Secret litellm-agent365 does not exist.
Run scripts/configure-agent365-secret.sh before deploying this configuration.
EOF
  exit 1
fi

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

if kubectl get secret litellm-dbcredentials --namespace "$namespace" >/dev/null 2>&1; then
  postgres_password="$(kubectl get secret litellm-dbcredentials \
    --namespace "$namespace" \
    --output jsonpath='{.data.postgres-password}' | base64 --decode)"
  database_password="$(kubectl get secret litellm-dbcredentials \
    --namespace "$namespace" \
    --output jsonpath='{.data.password}' | base64 --decode)"
else
  postgres_password="$(openssl rand -hex 24)"
  database_password="$(openssl rand -hex 24)"
fi

helm upgrade --install "$release_name" \
  oci://ghcr.io/berriai/litellm-helm \
  --version "$chart_version" \
  --namespace "$namespace" \
  --values "$repo_root/kubernetes/values.yaml" \
  --set-string "serviceAccount.annotations.azure\\.workload\\.identity/client-id=$workload_client_id" \
  --set-string "postgresql.auth.postgres-password=$postgres_password" \
  --set-string "postgresql.auth.password=$database_password" \
  --wait \
  --timeout 10m

unset postgres_password database_password
