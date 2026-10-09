#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deployment_name="${DEPLOYMENT_NAME:-litellm-gateway-demo}"
location="${AZURE_LOCATION:-eastus2}"
principal_id="$(az ad signed-in-user show --query id --output tsv)"

"$repo_root/scripts/prerequisites.sh"

cat <<EOF
This command creates or updates the dedicated AI Gateway resource group, VNet,
Log Analytics workspace, workload identity, AKS cluster, federation, and Azure
RBAC assignments declared in infra/main.bicep:

az deployment sub create --name "$deployment_name" --location "$location" \
  --template-file "$repo_root/infra/main.bicep" \
  --parameters "$repo_root/infra/parameters/demo.bicepparam" \
  --parameters aksAdminPrincipalId="$principal_id"

Run the subscription deployment only after reviewing a successful validation and
what-if result and receiving explicit approval in the active session.
EOF

if [[ "${APPROVE_AZURE_CHANGES:-}" != "yes" ]]; then
  echo "Set APPROVE_AZURE_CHANGES=yes only after explicit approval." >&2
  exit 1
fi

az deployment sub create \
  --name "$deployment_name" \
  --location "$location" \
  --template-file "$repo_root/infra/main.bicep" \
  --parameters "$repo_root/infra/parameters/demo.bicepparam" \
  --parameters aksAdminPrincipalId="$principal_id"
