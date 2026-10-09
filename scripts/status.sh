#!/usr/bin/env bash
set -euo pipefail

resource_group="${RESOURCE_GROUP:-rg-litellm-gateway-demo-eus2}"
cluster_name="${AKS_NAME:-litellm-demo-aks}"

echo "Azure resources"
az resource list \
  --resource-group "$resource_group" \
  --query "[].{name:name,type:type,location:location}" \
  --output table

if az aks show --resource-group "$resource_group" --name "$cluster_name" >/dev/null 2>&1; then
  echo
  echo "AKS cluster"
  az aks show \
    --resource-group "$resource_group" \
    --name "$cluster_name" \
    --query "{name:name,state:provisioningState,power:powerState.code,version:kubernetesVersion,oidc:oidcIssuerProfile.enabled,workloadIdentity:securityProfile.workloadIdentity.enabled}" \
    --output table
fi

if kubectl auth can-i get pods --namespace litellm >/dev/null 2>&1; then
  echo
  echo "LiteLLM namespace"
  kubectl get pods,services --namespace litellm
fi
