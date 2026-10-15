#!/usr/bin/env bash

# Creates the hosted agent's Foundry project connection without placing the
# LiteLLM virtual key in source, chat, or the user's shell history.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly AGENT_PROJECT="${REPO_ROOT}/litellm-deepwiki-agent"
readonly CONNECTION_NAME="litellm-deepwiki-hosted-agent"
readonly LITELLM_MCP_URL="https://litellm-agent365-mcp-d18f2ff3.eastus2.cloudapp.azure.com/mcp"

if ! command -v azd >/dev/null 2>&1; then
    printf 'Error: azd is required but was not found on PATH.\n' >&2
    exit 1
fi

printf 'Enter the replacement DeepWiki-restricted LiteLLM virtual key: ' >&2
IFS= read -r -s LITELLM_KEY
printf '\n' >&2

if [[ -z "${LITELLM_KEY}" ]]; then
    printf 'Error: the virtual key cannot be empty.\n' >&2
    exit 1
fi

trap 'unset LITELLM_KEY' EXIT HUP INT TERM

cd "${AGENT_PROJECT}"

AZURE_DEV_USER_AGENT=microsoft_foundry_skill \
    azd ai connection create "${CONNECTION_NAME}" \
    --kind remote-tool \
    --target "${LITELLM_MCP_URL}" \
    --auth-type custom-keys \
    --custom-key "x-litellm-api-key=${LITELLM_KEY}"

# Default connection output excludes credentials. This confirms creation
# without asking azd to return or print the protected key.
AZURE_DEV_USER_AGENT=microsoft_foundry_skill \
    azd ai connection show "${CONNECTION_NAME}"
