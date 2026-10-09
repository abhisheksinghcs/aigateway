#!/usr/bin/env bash
set -euo pipefail

namespace="${LITELLM_NAMESPACE:-litellm}"
service="${LITELLM_SERVICE:-litellm}"
local_port="${LITELLM_LOCAL_PORT:-4000}"

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "Set LITELLM_MASTER_KEY without placing it in shell history or source control." >&2
  exit 1
fi

kubectl port-forward \
  --namespace "$namespace" \
  "service/$service" \
  "$local_port:4000" >/tmp/litellm-port-forward.log 2>&1 &
port_forward_pid=$!
trap 'kill "$port_forward_pid" 2>/dev/null || true' EXIT

for _ in {1..20}; do
  if curl --silent --fail "http://127.0.0.1:$local_port/health/readiness" >/dev/null; then
    break
  fi
  sleep 1
done

curl --fail-with-body --silent --show-error \
  "http://127.0.0.1:$local_port/v1/chat/completions" \
  --header "Authorization: Bearer $LITELLM_MASTER_KEY" \
  --header "Content-Type: application/json" \
  --data '{
    "model": "customer-chat",
    "messages": [
      {
        "role": "user",
        "content": "Reply with exactly: LiteLLM gateway path verified."
      }
    ],
    "max_completion_tokens": 500,
    "reasoning_effort": "low"
  }'

echo
