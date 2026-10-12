#!/usr/bin/env bash
set -euo pipefail
set +x

resource_group="${RESOURCE_GROUP:-rg-litellm-gateway-demo-eus2}"
cluster_name="${AKS_NAME:-litellm-demo-aks}"
namespace="${LITELLM_NAMESPACE:-litellm}"
tenant_id="${AGENT365_TENANT_ID:-}"
client_id="${AGENT365_CLIENT_ID:-}"

if [[ "${APPROVE_KUBERNETES_CHANGES:-}" != "yes" ]]; then
  cat >&2 <<EOF
This script creates or updates the Kubernetes Secret litellm-agent365.
Set APPROVE_KUBERNETES_CHANGES=yes only after explicit approval.
EOF
  exit 1
fi

if [[ -z "$tenant_id" || -z "$client_id" ]]; then
  cat >&2 <<EOF
Set AGENT365_TENANT_ID and AGENT365_CLIENT_ID before running this script.
Do not set AGENT365_CLIENT_SECRET in the environment; the script prompts for it.
EOF
  exit 1
fi

guid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
if [[ ! "$tenant_id" =~ $guid_pattern || ! "$client_id" =~ $guid_pattern ]]; then
  echo "AGENT365_TENANT_ID and AGENT365_CLIENT_ID must be GUIDs." >&2
  exit 1
fi

az aks get-credentials \
  --resource-group "$resource_group" \
  --name "$cluster_name" \
  --overwrite-existing

read -r -s -p "Rotated Agent 365 client secret: " client_secret
printf '\n'
trap 'unset client_secret' EXIT

if [[ -z "$client_secret" ]]; then
  echo "The client secret cannot be empty." >&2
  exit 1
fi

printf '%s\n' \
  "AGENT365_TENANT_ID=$tenant_id" \
  "AGENT365_CLIENT_ID=$client_id" \
  "AGENT365_CLIENT_SECRET=$client_secret" |
  kubectl create secret generic litellm-agent365 \
    --namespace "$namespace" \
    --from-env-file=/dev/stdin \
    --dry-run=client \
    --output yaml |
  kubectl apply -f -

unset client_secret
trap - EXIT

echo "Kubernetes Secret $namespace/litellm-agent365 is configured."
