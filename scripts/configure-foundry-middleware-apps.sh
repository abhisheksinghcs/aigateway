#!/usr/bin/env bash
set -euo pipefail
set +x

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
middleware_name="${MIDDLEWARE_APP_NAME:-litellm-foundry-middleware-api}"
cli_name="${CLI_APP_NAME:-litellm-foundry-cli-client}"
gateway_app_id="${GATEWAY_APP_ID:-18f77e7f-8bf9-4f43-b014-e2168b6c5574}"
output_file="${APP_REGISTRATION_OUTPUT_FILE:-$repo_root/.azure/foundry-middleware-apps.env}"
scope_value="access_as_user"

if [[ "${APPROVE_ENTRA_CHANGES:-}" != "yes" ]]; then
  cat >&2 <<EOF
This script creates or updates two single-tenant Microsoft Entra applications
and their service principals:
  - $middleware_name
  - $cli_name

It does not create client secrets or grant Azure RBAC roles.
Set APPROVE_ENTRA_CHANGES=yes only after explicit approval.
EOF
  exit 1
fi

for command in az python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

tenant_id="$(az account show --query tenantId --output tsv)"
if [[ -z "$tenant_id" ]]; then
  echo "No active Azure tenant was found. Run az login first." >&2
  exit 1
fi

gateway_scope_id="$(az ad app show \
  --id "$gateway_app_id" \
  --query "api.oauth2PermissionScopes[?value=='$scope_value' && isEnabled].id | [0]" \
  --output tsv)"

if [[ -z "$gateway_scope_id" ]]; then
  echo "Gateway application $gateway_app_id does not expose the enabled $scope_value scope." >&2
  exit 1
fi

find_app() {
  local display_name="$1"
  local apps
  apps="$(az ad app list --filter "displayName eq '$display_name'" --output json)"
  python3 -c '
import json
import sys

apps = json.load(sys.stdin)
if len(apps) > 1:
    raise SystemExit("More than one application has the requested display name.")
if apps:
    print(apps[0]["appId"])
' <<<"$apps"
}

ensure_app() {
  local display_name="$1"
  local app_id
  app_id="$(find_app "$display_name")"
  if [[ -z "$app_id" ]]; then
    app_id="$(az ad app create \
      --display-name "$display_name" \
      --sign-in-audience AzureADMyOrg \
      --query appId \
      --output tsv)"
  fi
  printf '%s' "$app_id"
}

ensure_service_principal() {
  local app_id="$1"
  if ! az ad sp show --id "$app_id" >/dev/null 2>&1; then
    az ad sp create --id "$app_id" >/dev/null
  fi
}

has_delegated_permission() {
  local app_id="$1"
  local resource_app_id="$2"
  local permission_id="$3"
  az ad app show --id "$app_id" --query requiredResourceAccess --output json |
    python3 -c '
import json
import sys

resource_app_id, permission_id = sys.argv[1:3]
permissions = json.load(sys.stdin) or []
found = any(
    item.get("resourceAppId") == resource_app_id
    and any(
        access.get("id") == permission_id and access.get("type") == "Scope"
        for access in item.get("resourceAccess", [])
    )
    for item in permissions
)
raise SystemExit(0 if found else 1)
' "$resource_app_id" "$permission_id"
}

ensure_delegated_permission() {
  local app_id="$1"
  local resource_app_id="$2"
  local permission_id="$3"
  if ! has_delegated_permission "$app_id" "$resource_app_id" "$permission_id"; then
    az ad app permission add \
      --id "$app_id" \
      --api "$resource_app_id" \
      --api-permissions "$permission_id=Scope" \
      >/dev/null
  fi
}

middleware_app_id="$(ensure_app "$middleware_name")"
cli_app_id="$(ensure_app "$cli_name")"
ensure_service_principal "$middleware_app_id"
ensure_service_principal "$cli_app_id"

middleware_object_id="$(az ad app show --id "$middleware_app_id" --query id --output tsv)"
middleware_scope_id="$(az ad app show \
  --id "$middleware_app_id" \
  --query "api.oauth2PermissionScopes[?value=='$scope_value'].id | [0]" \
  --output tsv)"
if [[ -z "$middleware_scope_id" ]]; then
  middleware_scope_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
fi

middleware_payload="$(
  az ad app show --id "$middleware_app_id" --query api --output json |
    python3 -c '
import json
import sys

app_id, cli_app_id, scope_id, scope_value = sys.argv[1:5]
api = json.load(sys.stdin) or {}
scopes = [
    scope
    for scope in api.get("oauth2PermissionScopes", [])
    if scope.get("value") != scope_value
]
scopes.append(
    {
        "adminConsentDescription": "Allow the client to access the Foundry middleware as the signed-in user.",
        "adminConsentDisplayName": "Access the Foundry middleware as a user",
        "id": scope_id,
        "isEnabled": True,
        "type": "User",
        "userConsentDescription": "Allow this application to access the Foundry middleware on your behalf.",
        "userConsentDisplayName": "Access the Foundry middleware as you",
        "value": scope_value,
    }
)
preauthorized = [
    item
    for item in api.get("preAuthorizedApplications", [])
    if item.get("appId") != cli_app_id
]
preauthorized.append({"appId": cli_app_id, "delegatedPermissionIds": [scope_id]})
api["oauth2PermissionScopes"] = scopes
api["preAuthorizedApplications"] = preauthorized
api["requestedAccessTokenVersion"] = 2
print(json.dumps({"identifierUris": [f"api://{app_id}"], "api": api}))
' "$middleware_app_id" "$cli_app_id" "$middleware_scope_id" "$scope_value"
)"

az rest \
  --method PATCH \
  --url "https://graph.microsoft.com/v1.0/applications/$middleware_object_id" \
  --headers Content-Type=application/json \
  --body "$middleware_payload" \
  >/dev/null

cli_object_id="$(az ad app show --id "$cli_app_id" --query id --output tsv)"
cli_payload='{"isFallbackPublicClient":true,"publicClient":{"redirectUris":["http://localhost"]}}'
az rest \
  --method PATCH \
  --url "https://graph.microsoft.com/v1.0/applications/$cli_object_id" \
  --headers Content-Type=application/json \
  --body "$cli_payload" \
  >/dev/null

ensure_delegated_permission "$middleware_app_id" "$gateway_app_id" "$gateway_scope_id"
ensure_delegated_permission "$cli_app_id" "$middleware_app_id" "$middleware_scope_id"

mkdir -p "$(dirname "$output_file")"
umask 077
cat >"$output_file" <<EOF
TENANT_ID=$tenant_id
GATEWAY_APP_ID=$gateway_app_id
GATEWAY_SCOPE=api://$gateway_app_id/$scope_value
MIDDLEWARE_APP_ID=$middleware_app_id
MIDDLEWARE_SCOPE=api://$middleware_app_id/$scope_value
CLI_APP_ID=$cli_app_id
EOF

cat <<EOF
Microsoft Entra applications are configured.

Middleware API:
  Display name: $middleware_name
  Application ID: $middleware_app_id
  Scope: api://$middleware_app_id/$scope_value

CLI client:
  Display name: $cli_name
  Application ID: $cli_app_id
  Redirect URI: http://localhost

Non-secret identifiers were written to:
  $output_file

No client secret was created. Grant tenant-wide admin consent separately only
if the customer requires pre-consent for all users.
EOF
