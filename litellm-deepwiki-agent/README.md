# LiteLLM DeepWiki hosted agent

This project is a deterministic Microsoft Foundry hosted agent. It accepts a
question through the Responses protocol and calls exactly one tool:
DeepWiki's `ask_wiki_question`, reached through the existing LiteLLM MCP
gateway.

The agent does not call a model, choose tools, accept an MCP destination from
the caller, or accept a repository from the caller.

## Request flow

1. A client sends a user token for the middleware API.
2. The AKS middleware validates that token and performs the Entra
   on-behalf-of exchange for the LiteLLM delegated scope.
3. The middleware calls Foundry with its workload identity and forwards the
   delegated token in `x-client-litellm-user-token`.
4. Foundry provides forwarded request headers to the Python handler through
   `ResponseContext.client_headers`.
5. The agent combines the delegated token with its internal, DeepWiki-only
   LiteLLM virtual key.
6. The agent opens an MCP Streamable HTTP session to the configured LiteLLM
   `/mcp` endpoint and calls only `deepwiki-ask_wiki_question`.
7. LiteLLM enforces both the delegated Agent 365 guardrail and the virtual
   key's `deepwiki` object permission before forwarding the call to DeepWiki.
8. The agent converts the MCP text result to a normal Responses
   `TextResponse`.

## Code walkthrough

### `config.py`: deployment boundary

`Settings.from_env()` reads three values:

| Variable | Purpose |
|----------|---------|
| `LITELLM_MCP_URL` | The fixed LiteLLM Streamable HTTP endpoint, ending in `/mcp`. HTTPS is required except for localhost development. |
| `LITELLM_VIRTUAL_KEY` | An internal LiteLLM key restricted to the `deepwiki` MCP server. It is never accepted from a request. |
| `DEEPWIKI_REPOSITORY` | The one allowed public GitHub repository in `owner/repository` form. |

Startup fails if any value is missing or malformed. Errors identify the
variable but never include its value.

### `auth.py`: delegated user boundary

`get_delegated_token()` looks only for
`x-client-litellm-user-token`. The middleware forwards the raw token, so the
agent rejects a value with a `Bearer` prefix rather than trying to repair it.
The token is held only for the current call and is never logged.

### `agent.py`: caller input boundary

`answer_question()` accepts only plain question text. It rejects an empty
question or one longer than 4,000 characters. The caller cannot provide a
repository, URL, server ID, tool name, virtual key, or outbound headers.

### `deepwiki.py`: fixed tool adapter

`DeepWikiClient.ask()` constructs the only allowed outbound call:

```text
URL:  LITELLM_MCP_URL
Tool: deepwiki-ask_wiki_question
Arguments:
  repoName: DEEPWIKI_REPOSITORY
  question: <validated caller question>
Headers:
  Authorization: Bearer <delegated user token>
  x-litellm-api-key: <restricted internal virtual key>
```

The MCP session is short lived. It initializes, invokes the fixed tool,
extracts text content, and closes. Transport failures are converted to
credential-safe errors; exception text from the HTTP or MCP library is not
returned.

### `main.py`: Foundry protocol boundary

`create_app()` validates configuration once, builds the fixed DeepWiki
client, and registers the Responses handler. The AgentServer SDK owns the
HTTP endpoints, health checks, telemetry integration, and Responses event
lifecycle. The handler returns a `TextResponse`; no model deployment is
needed.

## Local setup

Python packages must come only from the approved Microsoft package proxy.
[`uv.toml`](src/litellm-deepwiki-agent/uv.toml) configures that proxy as the
sole index, and the lockfile was generated through it.

```bash
cd src/litellm-deepwiki-agent
uv sync --frozen --python 3.13
```

Copy [`.env.example`](src/litellm-deepwiki-agent/.env.example) to an ignored
`.env` only for local development. Never add a real virtual key to
`.env.example`, `azure.yaml`, source code, or Git.

To start the server after exporting the three required variables:

```bash
uv run --no-sync python main.py
```

The AgentServer listens on port `8088`.

## Validation

```bash
cd src/litellm-deepwiki-agent
uv run --no-sync python -m pytest
uv run --no-sync ruff check .
uv run --no-sync ruff format --check .
python -m compileall -q -x '[.]venv' .
```

The tests verify missing-token rejection, fixed destination/repository/tool
selection, MCP text conversion, configuration validation, and credential
redaction.

## Deployment configuration

[`azure.yaml`](azure.yaml) reuses the existing Foundry project and declares
the three application settings. It does not declare a model deployment.

Before deployment, set:

- `LITELLM_MCP_URL` to the public LiteLLM `/mcp` URL.
- `DEEPWIKI_REPOSITORY` to the customer-approved repository.
- `LITELLM_VIRTUAL_KEY` through the approved deployment secret mechanism,
  using a key whose LiteLLM object permission contains only `deepwiki`.

Do not provision or deploy until the configuration and code have been
reviewed. The middleware OBO client secret belongs only in the AKS middleware
and must never be supplied to this agent.
