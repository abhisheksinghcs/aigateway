#!/usr/bin/env bash
set -euo pipefail

namespace="${MIDDLEWARE_NAMESPACE:-litellm}"
secret_name="${MIDDLEWARE_SECRET_NAME:-litellm-foundry-middleware-secret}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required." >&2
  exit 1
fi

if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
  echo "Kubernetes namespace '$namespace' does not exist." >&2
  exit 1
fi

read -r -s -p "Middleware OBO client secret: " client_secret
printf '\n'
trap 'unset client_secret' EXIT

if [[ -z "$client_secret" ]]; then
  echo "The middleware client secret cannot be empty." >&2
  exit 1
fi

printf '%s' "$client_secret" |
  kubectl create secret generic "$secret_name" \
    --namespace "$namespace" \
    --from-file=MIDDLEWARE_CLIENT_SECRET=/dev/stdin \
    --dry-run=client \
    --output yaml |
  kubectl apply --filename -

unset client_secret
trap - EXIT

echo "Configured Kubernetes Secret '$namespace/$secret_name'."
