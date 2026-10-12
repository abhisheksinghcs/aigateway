#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resource_group="${RESOURCE_GROUP:-rg-litellm-gateway-demo-eus2}"
cluster_name="${AKS_NAME:-litellm-demo-aks}"
aks_subnet_nsg="${AKS_SUBNET_NSG:-litellm-demo-vnet-snet-aks-nsg-eastus2}"
namespace="litellm"

if [[ "${APPROVE_KUBERNETES_CHANGES:-}" != "yes" ]]; then
  cat >&2 <<EOF
This script installs or updates ingress-nginx and cert-manager, applies the
Let's Encrypt ClusterIssuer, and exposes only LiteLLM's /mcp route publicly.
Set APPROVE_KUBERNETES_CHANGES=yes only after explicit approval.
EOF
  exit 1
fi

az aks get-credentials \
  --resource-group "$resource_group" \
  --name "$cluster_name" \
  --overwrite-existing

if ! az network nsg rule show \
  --resource-group "$resource_group" \
  --nsg-name "$aks_subnet_nsg" \
  --name AllowPublicIngressHttpHttps \
  --output none; then
  cat >&2 <<EOF
The AKS subnet NSG does not contain AllowPublicIngressHttpHttps.
Deploy infra/main.bicep before deploying the public ingress.
EOF
  exit 1
fi

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update ingress-nginx jetstack

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.15.1 \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.metrics.enabled=true \
  --set controller.service.externalTrafficPolicy=Cluster \
  --set-string 'controller.service.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path=/healthz' \
  --wait \
  --timeout 10m

helm upgrade --install cert-manager jetstack/cert-manager \
  --version v1.21.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait \
  --timeout 10m

kubectl apply \
  -f "$repo_root/kubernetes/cluster-issuer.yaml" \
  -f "$repo_root/kubernetes/public-ingress.yaml"

kubectl wait \
  --for=condition=Ready \
  certificate/litellm-public-tls \
  --namespace "$namespace" \
  --timeout 10m

hostname="$(kubectl get ingress litellm-public \
  --namespace "$namespace" \
  --output jsonpath='{.spec.rules[0].host}')"

printf 'LiteLLM MCP ingress is ready: https://%s/mcp\n' "$hostname"
