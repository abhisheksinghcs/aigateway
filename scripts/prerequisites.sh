#!/usr/bin/env bash
set -euo pipefail

required_commands=(az kubectl helm git openssl)

for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

subscription_id="$(az account show --query id --output tsv)"
tenant_id="$(az account show --query tenantId --output tsv)"

if [[ "$subscription_id" != "d18f2ff3-4ef1-4102-8c8f-3a344037aeed" ]]; then
  echo "Active subscription is not MultiCloudTeam. No context was changed." >&2
  exit 1
fi

if [[ "$tenant_id" != "e0ca6a1b-554d-4f12-87c9-92ec42abb750" ]]; then
  echo "Active tenant is not the confirmed tenant. No context was changed." >&2
  exit 1
fi

echo "Azure context is the confirmed MultiCloudTeam subscription."
az bicep version
kubectl version --client
helm version --short

signed_in_user="$(az account show --query user.name --output tsv)"
roles="$(az role assignment list \
  --assignee "$signed_in_user" \
  --include-groups \
  --include-inherited \
  --all \
  --query "[].roleDefinitionName" \
  --output tsv)"

if ! grep -Eq '^(Owner|Contributor)$' <<<"$roles"; then
  echo "Missing Contributor or Owner in the target subscription/resource scope." >&2
  exit 1
fi

if ! grep -Eq '^(Owner|Role Based Access Control Administrator|User Access Administrator)$' <<<"$roles"; then
  echo "Missing authority to create the required Azure role assignments." >&2
  exit 1
fi

echo "Prerequisite checks passed."
