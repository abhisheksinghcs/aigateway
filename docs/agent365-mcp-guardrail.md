# Microsoft Agent 365 MCP Guardrail Guide

Last verified: 2026-10-12

This guide records the proposed Microsoft Agent 365 guardrail design for the
LiteLLM gateway. It distinguishes the LiteLLM quick start from the additional
work required to connect a Copilot Studio agent.

No Agent 365 guardrail configuration is currently deployed. LiteLLM `1.105.0`
was selected as the pinned upgrade because its released source contains the
documented `agent_365` implementation. The guardrail configuration and
credentials remain a separate rollout after the base gateway upgrade is
validated.

The base upgrade completed on 2026-10-12 as Helm revision 6. Runtime
verification confirmed LiteLLM `1.105.0`, `Agent365Guardrail`, and the
`pre_mcp_call` hook. Database migrations, admin authentication, and
`customer-chat` inference passed. Helm revision 5 remains the superseded
`1.90.2` rollback point.

## What the Guardrail Protects

The guardrail evaluates MCP tool calls before LiteLLM invokes the upstream MCP
server. It does not evaluate chat-completion requests.

For the MVP:

- LiteLLM MCP server ID: `deepwiki`
- Upstream MCP server: `https://mcp.deepwiki.com/mcp`
- Guardrail mode: `pre_mcp_call`
- Default behavior: enabled for MCP calls
- Unreachable behavior: fail closed by default

The existing `customer-chat` entry is unrelated to the MCP guardrail. It is a
logical LiteLLM model alias, not an application or a separately deployed
service. It exists in the LiteLLM ConfigMap running on AKS and routes
OpenAI-compatible chat requests to the existing Azure `o4-mini` deployment.

## Components and Identities

| Item | Purpose |
|------|---------|
| Copilot Studio agent or test client | Initiates an MCP tool call |
| Delegated Entra user token | Identifies the signed-in user to LiteLLM and Agent 365 |
| LiteLLM virtual key | Controls access to the `deepwiki` MCP server |
| LiteLLM gateway app registration | Performs the On-Behalf-Of token exchange |
| LiteLLM | Enforces MCP permissions and calls the Agent 365 evaluation API |
| Microsoft Agent 365 / Defender | Returns an allow or block decision |
| DeepWiki | Runs the tool only after an allow decision |

The gateway application's client secret identifies LiteLLM during the OBO
exchange. It is not the user token and is not the LiteLLM virtual key.

## End-to-End Request Flow

```mermaid
sequenceDiagram
    participant User
    participant Client as Copilot Studio or test client
    participant LiteLLM
    participant Entra as Microsoft Entra ID
    participant A365 as Microsoft Agent 365 / Defender
    participant DeepWiki

    User->>Client: Sign in and request an action
    Client->>Entra: Request delegated token for gateway API
    Entra-->>Client: User token with access_as_user
    Client->>LiteLLM: MCP call with user bearer token and LiteLLM credential
    LiteLLM->>LiteLLM: Check MCP server/tool permission
    LiteLLM->>Entra: OBO exchange using gateway app credentials
    Entra-->>LiteLLM: Delegated Agent 365 token
    LiteLLM->>A365: Evaluate pending tool call
    A365-->>LiteLLM: Allow or block plus correlation ID
    alt Allowed
        LiteLLM->>DeepWiki: Invoke tool
        DeepWiki-->>LiteLLM: Tool result
        LiteLLM-->>Client: Tool result
    else Blocked or not evaluated
        LiteLLM-->>Client: Refusal; DeepWiki is not called
    end
```

With the proposed DeepWiki configuration, the user's Entra bearer token is
consumed by LiteLLM for the guardrail OBO flow. It is not forwarded to
DeepWiki.

## Where the Bearer Token Comes From

The caller is responsible for obtaining the delegated user token:

- In the LiteLLM quick start, Azure CLI obtains the token for the signed-in
  test user.
- In an application, its OAuth/MSAL authentication layer obtains and refreshes
  the token.
- In Copilot Studio, an OAuth 2.0 MCP connection signs in the user and obtains
  an access token on the user's behalf.

The token must be issued for:

```text
api://<gateway-client-id>
```

Its `scp` claim must include:

```text
access_as_user
```

The Copilot agent does not invent or self-sign this token. The Copilot Studio
connection and Microsoft Entra ID produce it after the user authenticates.

## Copilot Studio Integration Caveat

The LiteLLM quick start sends two headers:

```http
Authorization: Bearer <delegated-user-token>
x-litellm-api-key: <virtual-key>
```

Copilot Studio's standard MCP onboarding wizard selects one server
authentication method: None, API key, or OAuth 2.0. Therefore, the quick-start
curl flow must not be assumed to work unchanged in Copilot Studio.

Two integration patterns are possible:

### Pattern A: OAuth-only LiteLLM JWT authentication

Enable LiteLLM JWT authentication so the delegated Entra token is both:

- The LiteLLM admission credential.
- The OBO subject token for Agent 365.

The caller does not send `x-litellm-api-key`. MCP access is granted through a
LiteLLM team with `deepwiki` permission.

Tradeoff: there is no virtual key for the request, so the evaluation does not
receive a virtual-key alias as its agent ID.

### Pattern B: OAuth plus a separate virtual-key header

Use OAuth 2.0 for the delegated user token and customize the generated MCP
connector to send `x-litellm-api-key` as an additional header.

Tradeoffs:

- This is beyond the standard onboarding wizard.
- Custom-header behavior must be validated in the target Copilot Studio
  environment.
- The virtual key becomes another credential that must be stored and rotated.

The initial MVP should validate the documented two-header flow with Azure CLI
and `curl`. A separate decision and test are required before claiming Copilot
Studio support. Pattern A is simpler for Copilot Studio; Pattern B preserves
the virtual-key alias in Agent 365 evaluations.

## Proposed LiteLLM Configuration

```yaml
model_list:
  - model_name: customer-chat
    litellm_params:
      model: azure/o4-mini
      api_base: https://agent365-teams-agents.openai.azure.com/
      api_version: "2025-04-01-preview"
    model_info:
      base_model: azure/o4-mini

guardrails:
  - guardrail_name: agent365-mcp
    litellm_params:
      guardrail: agent_365
      mode: pre_mcp_call
      default_on: true
      tenant_id: os.environ/AGENT365_TENANT_ID
      client_id: os.environ/AGENT365_CLIENT_ID
      client_secret: os.environ/AGENT365_CLIENT_SECRET

mcp_servers:
  deepwiki:
    transport: http
    url: https://mcp.deepwiki.com/mcp

litellm_settings:
  enable_azure_ad_token_refresh: true
  drop_params: true

general_settings:
  master_key: os.environ/PROXY_MASTER_KEY
```

The `model_list` block is retained because it is the gateway's existing model
route. It is not required by the Agent 365 guardrail quick start and can be
explained independently:

| Field | Meaning |
|-------|---------|
| `model_name: customer-chat` | Stable name clients send to LiteLLM |
| `model: azure/o4-mini` | LiteLLM provider and physical Azure deployment |
| `api_base` | Existing Azure AI account endpoint |
| `api_version` | Azure API version used by LiteLLM |
| `base_model` | Cost and metadata mapping; it does not change routing |

## Virtual Key for the Quick Start

Use a standard LiteLLM virtual key with explicit MCP object permission:

```json
{
  "key_alias": "agent365-deepwiki-mvp",
  "object_permission": {
    "mcp_servers": ["deepwiki"]
  }
}
```

The quick start creates this through `POST /key/generate`; it does not specify
a key-type field. For the MVP, prefer the API over the current Admin UI because
the API request explicitly proves the `deepwiki` object permission. The
current UI's `AI APIs` label and its `Owned By` choice do not replace
`object_permission.mcp_servers`.

Do not assign the `customer-chat` model merely to make the MCP key work. Model
permission and MCP permission are separate LiteLLM authorization surfaces.

### Key Alias Is Not the Copilot Studio Agent Name

`agent365-deepwiki-mvp` is an example LiteLLM key alias. The Copilot Studio
agent does not need to have that display name.

When a guarded request uses the virtual key, LiteLLM sends the key alias as the
agent ID field in the Agent 365 evaluation. The value is correlation metadata:
it lets administrators distinguish calls made with different gateway keys.

For a production design, use an alias that maps cleanly to the real agent, for
example:

```text
copilot-sales-assistant-prod
```

The mapping should be documented because LiteLLM does not automatically verify
that the alias equals the Copilot Studio agent's registered or display name.

## Data Sent to Agent 365

For each guarded tool call, LiteLLM sends the pending call to the Agent 365
evaluation API. According to the LiteLLM documentation, this can include:

- Tool name.
- Tool arguments.
- MCP server name.
- Conversation ID.
- Tool description and input schema when already known.
- Virtual-key alias as agent ID when a key alias exists.

The user's prompt is not sent as part of this guardrail evaluation. Agent 365
returns an allow/block result and correlation information. LiteLLM records the
result and either invokes DeepWiki or refuses the call.

This is a synchronous security decision, not merely telemetry sent after tool
execution.

## Rotated Client Secret: Where It Goes

The previously shared client secret must be revoked and replaced in the
gateway app registration in Microsoft Entra ID. Do not paste the replacement
into chat or commit it.

The rotated value will be stored in this Kubernetes object:

```text
Namespace: litellm
Secret:    litellm-agent365
Key:       AGENT365_CLIENT_SECRET
```

The same Secret will contain the non-secret identifiers for a single,
consistent injection path:

```text
AGENT365_TENANT_ID
AGENT365_CLIENT_ID
AGENT365_CLIENT_SECRET
```

The Helm values will reference the Secret by name:

```yaml
environmentSecrets:
  - litellm-agent365
```

The deployment script should prompt locally for the rotated value with input
echo disabled, create or update the Kubernetes Secret without printing it, and
unset the shell variable immediately. The value must not be passed with Helm
`--set`, because Helm would retain it in release state.

The intended one-time POC procedure is:

```bash
read -rsp "Rotated Agent 365 client secret: " AGENT365_CLIENT_SECRET
printf '\n'

printf '%s\n' \
  'AGENT365_TENANT_ID=<tenant-id>' \
  'AGENT365_CLIENT_ID=<gateway-client-id>' \
  "AGENT365_CLIENT_SECRET=${AGENT365_CLIENT_SECRET}" |
  kubectl create secret generic litellm-agent365 \
    --namespace litellm \
    --from-env-file=/dev/stdin \
    --dry-run=client \
    --output yaml |
  kubectl apply -f -

unset AGENT365_CLIENT_SECRET
```

Run this only from a trusted terminal with shell tracing disabled. Replace the
two identifier placeholders locally; never put the secret value directly in
the command text. Before using this procedure, the deployment script and
target Kubernetes context will be reviewed and explicit mutation approval will
be obtained.

For this POC, Kubernetes Secret storage is acceptable with the documented
tradeoff that Kubernetes Secrets are base64-encoded API objects, not an
external secrets vault. Production should use an approved secret manager such
as Azure Key Vault with workload identity and the Secrets Store CSI Driver.

## Validation Plan

1. Rotate and revoke the exposed Entra client secret.
2. Use the validated, pinned LiteLLM `1.105.0` chart and image.
3. Add the environment Secret reference and proposed configuration.
4. Render and lint the merged Helm release locally.
5. Obtain explicit approval before changing Kubernetes.
6. Roll out the Agent 365 configuration and verify readiness.
7. Confirm the `deepwiki` MCP server is registered.
8. Create the `deepwiki`-restricted virtual key.
9. Obtain a delegated test-user token with the correct audience and scope.
10. Call `/mcp-rest/tools/call` through a local port-forward with both headers.
11. Verify an allowed call reaches DeepWiki.
12. Verify a blocked or unevaluated call does not reach DeepWiki.
13. Correlate the LiteLLM log and Agent 365 record.
14. Rerun `customer-chat` inference to prove chat behavior is unchanged.
15. Separately choose and validate a Copilot Studio integration pattern.

Public ingress is not required for the local MVP test. It is required before a
hosted Copilot Studio agent can call the gateway.

## References

- [LiteLLM Microsoft Agent 365 guardrail](https://docs.litellm.ai/docs/proxy/guardrails/microsoft_agent_365)
- [LiteLLM virtual keys](https://docs.litellm.ai/docs/proxy/virtual_keys)
- [Copilot Studio: connect an existing MCP server](https://learn.microsoft.com/en-us/microsoft-copilot-studio/mcp-add-existing-server-to-agent)
- [Copilot Studio: extend an agent with MCP](https://learn.microsoft.com/en-us/microsoft-copilot-studio/agent-extend-action-mcp)
- [Agent 365 observability concepts](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/observability-concepts)
