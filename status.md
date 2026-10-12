# AI Gateway Lab Status

Last updated: 2026-10-12 12:00 EDT

## Current State

The approved POC is deployed and functionally verified. Azure infrastructure and LiteLLM are running in `eastus2`. PostgreSQL-backed administration and the Microsoft Agent 365 guardrail MVP are operational. Public, trusted HTTPS now exposes only LiteLLM's authenticated `/mcp` route; the Copilot Studio connector and final authentication pattern remain to be built.

## Azure Context

- Subscription: `MultiCloudTeam`
- Subscription ID: `d18f2ff3-4ef1-4102-8c8f-3a344037aeed`
- Tenant ID: `e0ca6a1b-554d-4f12-87c9-92ec42abb750`
- Resource group: `rg-litellm-gateway-demo-eus2`
- Deployment: `litellm-gateway-demo`
- Deployment state: `Succeeded`
- Plan status: `Validated`

## Deployed Resources

- AKS cluster: `litellm-demo-aks`
  - Kubernetes 1.35 / nodes 1.35.8
  - Two `Standard_D4as_v6` Azure Linux nodes
  - AKS Free control-plane tier
  - Azure CNI Overlay and Cilium
  - Microsoft Entra authentication and Azure RBAC
  - Local Kubernetes accounts disabled
  - OIDC issuer and AKS Workload Identity enabled
- Virtual network: `litellm-demo-vnet`
  - AKS subnet: `10.40.0.0/22`
  - Reserved private-endpoint subnet: `10.40.4.0/24`
- Log Analytics workspace: `litellm-demo-law-khtkwbank4rg6`
- User-assigned workload identity: `litellm-demo-workload-id`
- Federated subject: `system:serviceaccount:litellm:litellm`

## LiteLLM State

- Namespace/release: `litellm`
- Chart and image version: `1.105.0`
- OCI chart digest: `sha256:9d907efc6799afb994d15add76c90ea7557d9a3348450a895ddf4eb09a812f55`
- Multi-architecture image index digest: `sha256:60947db020b57e204823d3fbc8bb295c85be890d7c9adcc77fb4f5fc2fe410b2`
- Replicas: one Ready pod
- Service: `ClusterIP` on port 4000 behind public NGINX ingress for `/mcp` only
- Temporary Agent 365 hostname: `57.167.155.123.nip.io`
- Public MCP endpoint: `https://57.167.155.123.nip.io/mcp`
- Public TLS: Let's Encrypt certificate Ready and valid through 2027-01-10
- Public route boundary: `/mcp` reaches LiteLLM; `/ui` and `/v1` return ingress-level HTTP 404
- Logical model: `customer-chat`
- Physical backend: Azure `o4-mini` deployment in `Agent365-Teams-Agents`
- Azure model version: `2025-04-16`
- Authentication: AKS Workload Identity; no Azure AI API key
- LiteLLM cost mapping: `model_info.base_model: azure/o4-mini`
- PostgreSQL: bundled single-node instance approved for the POC admin panel
- Redis: disabled/not deployed
- PostgreSQL image: `bitnamilegacy/postgresql@sha256:ea55532b6f75afbc97f617d91ec5efae17609c8eb825a31845fa9cb9e4aa13e1`
- PostgreSQL storage: bound 8 Gi PVC
- Migration Job: enabled for schema management; latest run completed and was removed by TTL
- Agent 365 guardrail: `agent365-mcp`, default-on `pre_mcp_call`, fail-closed
- MCP server: `deepwiki`; three upstream tools discovered

## Validation Evidence

- Bicep compilation, parameter compilation, linting, subscription validation, Azure Policy review, and what-if passed.
- Infrastructure deployment completed successfully.
- Both AKS nodes are Ready.
- All `kube-system` pods are Running or Completed.
- LiteLLM pod is Ready with zero restarts at final verification.
- Azure Workload Identity environment variables and projected token are present.
- Operator role is `Azure Kubernetes Service RBAC Cluster Admin`, scoped to the AKS cluster.
- Workload role is `Cognitive Services OpenAI User`, scoped to the existing Azure AI account.
- The obsolete, incorrectly selected AKS control-plane role assignment was deleted.
- A real OpenAI-compatible request returned exactly:

  `LiteLLM gateway path verified.`

- LiteLLM router logs confirmed `customer-chat` routed to `azure/o4-mini` with HTTP 200.
- No unidentified-Azure-model cost warning remained after setting `base_model`.
- Helm revision 8 is `deployed`; revision 7 is the pre-login-hardening rollback point, revision 6 is the pre-guardrail `1.105.0` rollback point, and revision 5 is the `1.90.2` rollback point.
- PostgreSQL is Ready and all LiteLLM migrations plus the post-migration sanity check completed.
- Before login hardening, bootstrap authentication with username `admin` and the existing master key returned HTTP 303 to `/ui/?login=success`.
- Post-database inference returned exactly `LiteLLM gateway path verified.`
- The running Python package reports LiteLLM `1.105.0`.
- Runtime import verification confirmed `Agent365Guardrail`, the `agent_365` registry entry, and `pre_mcp_call` support.
- The `1.105.0` database migrations completed successfully. LiteLLM was restarted after migration so the final startup schema check ran against the migrated database with no schema-drift or application-error log.
- Before login hardening, bootstrap authentication still returned HTTP 303 to `/ui?login=success` after the version upgrade.
- Post-upgrade and post-restart `customer-chat` inference returned exactly `LiteLLM gateway path verified.`
- `agent365-mcp` initialized successfully and DeepWiki exposed `ask_wiki_question`, `read_wiki_contents`, and `read_wiki_structure`.
- A delegated Azure CLI user token was verified with the gateway API audience and `access_as_user` scope.
- A temporary virtual key restricted to `deepwiki` completed `read_wiki_structure` through `/mcp-rest/tools/call` with HTTP 200.
- The guarded call is recorded in PostgreSQL as guardrail `agent365-mcp`, call type `call_mcp_tool`, status `success`, and 1,991 ms duration.
- A missing-user-token call was refused with HTTP 401 before the DeepWiki tool ran.
- Both temporary validation keys were deleted after their tests.
- The Admin UI initially displayed `TypeError: Failed to fetch`; no request reached LiteLLM. Retrying through an active port-forward in a private browser window succeeded, confirming a stale browser/access-path issue rather than a key API failure.
- The persistent virtual key alias is `copilot-deepwiki-mvp`. The UI created the alias without MCP object permission, so the existing key was updated by its non-secret ID through `/key/update`.
- Read-back verification confirms the persistent key now has a dedicated object-permission record with only `mcp_servers: ["deepwiki"]`. The raw key was not read, logged, or stored in the repository.
- Three `proxy_admin` database rows exist and two have password credentials.
- `general_settings.disable_env_credential_login: true` is deployed. Shared `admin` plus the master key is rejected by the UI with HTTP 401, the master key remains valid for management API recovery with HTTP 200, and the user confirmed a personal `proxy_admin` email/password login succeeds.
- Because the external LiteLLM ConfigMap does not trigger the chart checksum rollout, `scripts/deploy-litellm.sh` now explicitly restarts and waits for the deployment after Helm completes.
- Public-ingress diagnosis on 2026-10-12 confirmed that the AKS cluster, both nodes, both ingress-nginx controllers, the LiteLLM backend, Azure public IP, load-balancer frontend, backend pool, rules, and HTTP/HTTPS health probes are provisioned and healthy.
- The public timeout root cause is the AKS subnet NSG `litellm-demo-vnet-snet-aks-nsg-eastus2`: its default `DenyAllInBound` applies before the AKS-managed NIC NSG, but it has no Internet allow rule for ports 80 and 443. The AKS-managed NIC NSG already has the expected public-IP-specific allow rule.
- The existing ACME order is invalid because Let's Encrypt timed out reaching the HTTP-01 challenge through the blocked load balancer. A fresh certificate attempt is required after the subnet NSG is fixed.
- Predeployment structured what-if found that adding the AKS subnet NSG to source would otherwise detach the existing private-endpoint-subnet NSG. The Bicep change now preserves both existing subnet NSG associations and changes only the AKS subnet NSG rules.
- Subscription deployment `litellm-gateway-demo` completed successfully at 2026-10-12 11:58 EDT. The infrastructure-managed `AllowPublicIngressHttpHttps` subnet NSG rule is provisioned, both subnet NSG associations remain intact, and public HTTP now reaches ingress-nginx with an HTTP 308 response instead of timing out.
- `kubernetes/public-ingress.yaml` now routes only `/mcp` and disables proxy buffering with one-hour read/send timeouts for streamable HTTP.
- A fresh Let's Encrypt ACME order completed successfully. The certificate is Ready, the public `/mcp` endpoint returns LiteLLM's expected HTTP 401 authentication response without credentials, and public `/ui` and `/v1` requests return HTTP 404 before reaching LiteLLM.
- Final checks passed: Bicep build/lint, shell syntax, Kubernetes client-side apply, two Ready AKS nodes, Ready LiteLLM/PostgreSQL/ingress workloads, live AKS and model RBAC, and a post-ingress `customer-chat` response of exactly `LiteLLM gateway path verified.`

## Operational Notes

- The two AKS VMSS instances have been externally deallocated more than once while the AKS control plane and node pool report Running. They were started as a prerequisite to the approved `1.105.0` upgrade and recovered to Ready. Subscription-level shutdown automation may deallocate them again.
- `kubelogin` was installed with `az aks install-cli` because Homebrew was blocked by the machine's Xcode version.
- The generated LiteLLM master key exists only in the Kubernetes Secret `litellm-master-key`; it is not stored in Git.
- Access requires a local port-forward:

  ```bash
  kubectl port-forward -n litellm service/litellm 4000:4000
  ```
- The Microsoft Agent 365 MCP guardrail is a separate flow from ordinary chat completions. It requires a configured MCP server, a database-backed LiteLLM virtual key scoped to that server, and a delegated user Entra token on every guarded MCP call.
- DeepWiki was selected as the MVP MCP server.
- `customer-chat` is a LiteLLM model alias deployed in the gateway ConfigMap, not a separate application.
- The LiteLLM quick start's two-header flow is not a direct match for the Copilot Studio MCP wizard, which selects one server authentication method. The CLI MVP validated both headers; Copilot Studio still requires a choice between LiteLLM JWT authentication or OAuth plus a custom virtual-key header.
- The key alias is correlation metadata sent by LiteLLM as the Agent 365 evaluation's agent ID. It does not require the Copilot Studio agent to use the same display name.
- The user confirmed on 2026-10-12 that the previously exposed Agent 365 application client secret was rotated. The replacement value has not been shared or stored in the repository. Never copy it into Git, Helm values, `config.yaml`, `status.md`, logs, or shell history.
- The proposed configuration uses only `os.environ/AGENT365_TENANT_ID`, `os.environ/AGENT365_CLIENT_ID`, and `os.environ/AGENT365_CLIENT_SECRET` references. The values must be injected from a Kubernetes Secret without storing the secret in Helm release state.
- The detailed design and customer walkthrough are in `docs/agent365-mcp-guardrail.md`.
- The `agent365-mcp` guardrail, DeepWiki MCP server, and `litellm-agent365` environment Secret reference are deployed. The replacement secret exists only in Kubernetes and was entered through the hidden-prompt helper.

## Deferred Scope

- Public HTTPS ingress, DNS, and certificate ownership
- Managed PostgreSQL for production-grade persistence
- Redis and multiple LiteLLM replicas
- Multiple models, routing, fallback, and load balancing
- Key Vault and private endpoints
- Private Azure AI networking
- Expanded observability, additional guardrails, and FinOps demonstrations

## Next Step

The next build item is the Copilot Studio connectivity layer. Public MCP ingress remediation is currently in progress:

1. [x] Add an infrastructure-managed subnet NSG allow rule for public HTTP/HTTPS traffic to the AKS ingress load balancer.
2. [x] Replace the incomplete public `/v1` ingress path with LiteLLM's streamable HTTP `/mcp` route while keeping `/ui` private.
3. [x] Deploy the Kubernetes ingress change, recreate the failed ACME issuance attempt, and verify publicly trusted HTTPS.
4. Build the Copilot Studio MCP connection using delegated OAuth for the gateway audience and `access_as_user`.
5. If the two-header pattern is retained, add `x-litellm-api-key` as a connector-level secret header using the existing `copilot-deepwiki-mvp` raw key. Otherwise, enable and validate LiteLLM JWT admission before omitting the virtual-key header.
6. Validate the hosted Copilot Studio -> HTTPS `/mcp` -> LiteLLM -> Agent 365 -> DeepWiki flow.
7. Validate an administrator-configured Defender policy block separately; the MVP currently proves the allow path and mandatory-user-token refusal.

## Handoff Rules

1. Read `local-files/gateway-prompt.md` and `.azure/deployment-plan.md`.
2. Run `scripts/status.sh` to inspect live Azure and Kubernetes state.
3. Do not expose the generated master key or commit kubeconfig/secret files.
4. Explain and obtain approval before Azure or Kubernetes mutations.
5. Obtain explicit approval before destructive actions.
