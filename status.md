# AI Gateway Lab Status

Last updated: 2026-10-14 10:53 EDT

## Current State

The approved POC is deployed and healthy in `eastus2`. Both AKS workers are Ready, PostgreSQL and LiteLLM are Ready, and public route validation passes. Azure Resource Health classified the latest unexplained stops as `UserInitiated` by an authorized user or process, but the initiating actor remains unknown. A guarded Azure Monitor and Logic App workflow is now enabled to make one delayed recovery attempt when nodes stop reporting or become NotReady.

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
- Temporary Agent 365 hostname: `litellm-agent365-mcp-d18f2ff3.eastus2.cloudapp.azure.com`
- Public MCP endpoint: `https://litellm-agent365-mcp-d18f2ff3.eastus2.cloudapp.azure.com/mcp`
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
- Helm revision 9 is `deployed` with issuer-bound JWT authentication; revision 8 is the pre-JWT rollback point, revision 7 is the pre-login-hardening rollback point, revision 6 is the pre-guardrail `1.105.0` rollback point, and revision 5 is the `1.90.2` rollback point.
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
- Copilot Studio created the OAuth connection but could not retrieve MCP tools or resources. Its detailed error was a Microsoft Entra Internet Access denial for `57.167.155.123.nip.io/mcp`, categorized as `ComputersAndTechnology, IllegalSoftware`. Ingress logs confirmed that no Copilot request reached AKS, so the failure occurred before LiteLLM authentication.
- The selected remediation replaced `nip.io` with the Azure-managed DNS label `litellm-agent365-mcp-d18f2ff3.eastus2.cloudapp.azure.com` on the existing ingress public IP.
- ingress-nginx revision 5 is deployed with the Azure DNS-label annotation. A new Let's Encrypt order completed, and the certificate covers the Azure-managed hostname through 2027-01-10.
- The new endpoint resolves to `57.167.155.123`; trusted HTTPS `/mcp` reaches LiteLLM and returns the expected unauthenticated HTTP 401, while `/ui` and `/v1` return ingress-level HTTP 404.
- An unnecessary cert-manager Helm upgrade conflicted with the policy-managed `admissionsenforcer` webhook field. The healthy release was restored with a client-side rollback and is deployed at revision 3. The ingress deployment script now installs cert-manager only when it is absent.
- At 2026-10-12 14:28 EDT, Copilot Studio reported `upstream connect error or disconnect/reset before headers. reset reason: connection timeout`. Both VMSS instances had again been externally deallocated while AKS and the node pool still reported Running. Both Kubernetes nodes were `NotReady`, ingress had no endpoints, and all application workloads were Pending.
- The user approved restarting VMSS instances 0 and 1. By 14:38 EDT both VMs and Kubernetes nodes were Running/Ready, ingress-nginx had two active endpoints, LiteLLM and PostgreSQL were Ready, and trusted public `/mcp` again returned the expected HTTP 401 in 280 ms.
- Copilot Studio now reaches LiteLLM and sends an OAuth bearer JWT, but tool discovery receives HTTP 401 because the deployed gateway still treats the JWT as a virtual key. The connector's `[{"jsonrpc":"2.0"}]` detail masks this authentication failure.
- The live LiteLLM `1.105.0` schema confirms `/team/new` accepts an explicit `team_id` and `object_permission`. The selected mapping uses the Entra v1 `appid` claim as a deterministic team ID and `oid` as the user ID.
- The local LiteLLM configuration now enables issuer-bound JWT authentication for the gateway API audience and exact tenant issuer. It also enables forwarded-address handling only for MCP requests arriving from the `10.244.0.0/16` AKS pod CIDR and selects the rightmost client address after one trusted ingress proxy hop.
- Local validation passed against the running LiteLLM `1.105.0` JWT schema, and Helm `1.105.0` rendered successfully with the updated repository values. Both AKS nodes, LiteLLM, and PostgreSQL were Ready before the planned rollout.
- The deterministic LiteLLM team `18f77e7f-8bf9-4f43-b014-e2168b6c5574` now exists with alias `copilot-studio-deepwiki`, no model access, and an object-permission record whose only MCP server is `deepwiki`.
- The approved deployment completed as Helm revision 9. The ConfigMap, issuer-bound JWT authentication, and trusted MCP ingress-proxy settings are active, and the restarted LiteLLM deployment reached Ready.
- A live, correctly signed Entra token with the configured issuer, audience, and matching `appid` reached LiteLLM's JWT path but was rejected with HTTP 403 because LiteLLM JWT authentication requires an Enterprise license. No `LITELLM_LICENSE` is configured. This licensing gate is now the blocker; it occurs after connectivity and before MCP tool discovery.
- Revision 9 did not regress existing paths. A temporary DeepWiki-only virtual key listed all three tools with HTTP 200 and was deleted, and `customer-chat` returned exactly `JWT rollout regression passed.` The first inference probe used too small an output-token budget for `o4-mini` and returned empty content; the corrected 200-token probe passed.
- Microsoft documentation confirms that the Copilot Studio MCP onboarding wizard selects one server authentication mode: `None`, `API key`, or `OAuth 2.0`. It does not provide a supported way to combine the delegated OAuth bearer token with LiteLLM's additional virtual-key credential.
- The Microsoft 365 Copilot API-key-authentication article applies only to OpenAPI API plugins and explicitly states that MCP plugins do not support API-key authentication. Copilot Studio's separate standard-harness MCP wizard does expose API-key mode, but selecting it replaces OAuth rather than adding a second credential.
- API-key-only MCP authentication could authenticate LiteLLM with the persistent virtual key and should permit tool discovery, but it would not send the delegated Entra user token required by the default-on Agent 365 guardrail. Actual guarded tool calls would therefore fail the existing missing-user-token check unless the POC's user-context security requirement were removed or a trusted server-side adapter supplied both credentials.
- Copilot Studio remains technically viable through either licensed LiteLLM JWT admission or a server-side OAuth-validating adapter that injects the virtual key while preserving the delegated user token. API-key-only Copilot authentication is insufficient for the current Agent 365 guardrail because it removes delegated user context.
- Microsoft Foundry supports key-based authentication, agent or project managed identity, and OAuth identity passthrough for MCP connections. Switching only the agent host does not remove the LiteLLM limitation: OAuth or Entra still sends a JWT that unlicensed LiteLLM rejects, while key-only authentication still omits delegated user context.
- A Foundry agent connected directly to MCP tools is a viable alternative POC, and published Foundry agents integrate natively with the Agent 365 registry. That option changes the demonstration from “LiteLLM gateway enforces Agent 365 before MCP calls” to “Foundry agent uses native Agent 365 governance,” so it should be treated as an explicit scope change rather than a connector fix.
- A Foundry **hosted agent with custom code** provides another viable architecture: its code can call LiteLLM with both `Authorization: Bearer <delegated-user-token>` and `x-litellm-api-key: <virtual-key>`. This preserves the already validated two-header LiteLLM/Agent 365 flow and does not require LiteLLM Enterprise JWT authentication because the virtual key remains LiteLLM's authentication credential.
- Delegated-token delivery to hosted-agent code is not automatic. Microsoft's documented pattern requires a trusted application backend to authenticate the user, perform or manage the OBO exchange for the gateway audience, invoke Foundry with a separate Foundry workload token, pass the delegated gateway token in an `x-client-*` header, and set `x-ms-user-identity`. Foundry forwards the `x-client-*` value to the container but does not forward the caller's `Authorization` header.
- In that hosted-agent design, the LiteLLM virtual key must be obtained from a secret store at runtime and never accepted from the end user, stored in source, or logged. The agent then adds the delegated token and virtual key only on its outbound request to LiteLLM.
- The trusted middle tier is an application component that must be written and hosted in front of the Foundry agent. It also needs an Entra application identity: preferably a dedicated app registration that exposes the middle-tier API to the client and acts as the confidential OBO client for the downstream LiteLLM gateway scope. When hosted in Azure, the same deployed service should use a managed identity, rather than the OBO client secret, to obtain its Foundry invocation token.
- The middle-tier code and Entra registration are separate concerns but belong to one logical component. The code validates the incoming user token, performs OBO, derives `x-ms-user-identity` from the validated user, and invokes Foundry. The app registration supplies the OAuth/API identity and delegated-permission configuration required for those operations.
- The middle tier can be deployed as a separate Kubernetes Deployment and ClusterIP Service in the existing AKS cluster. This is the preferred POC hosting option because it reuses the current ingress, Workload Identity, observability, and deployment boundary while preserving a separate service account and least-privilege identity.
- Co-location does not make the Foundry hosted agent part of the AKS network. Foundry-managed compute must still reach LiteLLM or an adapter through a routable HTTPS endpoint unless a later private-network design is added.
- Entra registration design depends on the user-facing client. A server-hosted web UI can use one confidential web application registration for interactive sign-in and delegated gateway-token acquisition. A separate SPA, native client, Copilot surface, or reusable API pattern normally uses a public client registration plus a separate confidential middle-tier API/OBO registration.
- The selected first client is a command-line/Postman-style public client, with a UI deferred. The design therefore uses two single-tenant registrations: `litellm-foundry-middleware-api` and `litellm-foundry-cli-client`.
- A manual customer walkthrough is documented in `docs/foundry-middleware.md`. The matching idempotent script is `scripts/configure-foundry-middleware-apps.sh`; it requires `APPROVE_ENTRA_CHANGES=yes`, creates no credential, and has not been run.
- The script writes only non-secret generated IDs and scopes to the ignored `.azure/foundry-middleware-apps.env` file. App registrations are never created automatically during clone or prerequisite checks.
- The app-registration script passed Bash syntax validation, its no-approval execution stopped at the required approval gate, and the repository passed `git diff --check`. No Entra object was created or changed during validation.

## Recovered AKS Incident: 2026-10-13

- Incident impact before recovery: VMSS instances `0` and `1` were `PowerState/deallocated`; both Kubernetes nodes were `NotReady` with `NodeStatusUnknown`, shutdown, and out-of-service taints. LiteLLM had no healthy pod, PostgreSQL and replacement system workloads were Pending, and the Workload Identity webhook had no available endpoints.
- Azure's high-level AKS and node-pool surfaces misleadingly remain `Succeeded` / `Running`, and AKS Resource Health remains `Available`.
- Node 0's final kubelet heartbeat was `2026-10-13T17:07:21Z` (1:07:21 PM EDT). Resource Health recorded `Stopping and deallocating` at `17:08:25Z`, classified it as `UserInitiated`, and stated that an authorized user or process requested it. Kubernetes marked the node NotReady at `17:09:20Z`; the cloud controller first observed `powerStatus="deallocating"` at `17:09:21Z`.
- Node 1's final kubelet heartbeat was `2026-10-13T17:08:43Z` (1:08:43 PM EDT). Resource Health recorded the same `UserInitiated` `Stopping and deallocating` event at `17:12:15Z`; Kubernetes marked the node NotReady at `17:13:22Z`.
- Resource Health correlation IDs are `846cacb9-9ced-4fb1-ad45-864c331f65bd` for VM 0, `e8c66761-570b-47f9-903b-a8bc25ff5184` for VM 1, and `2fc2db1c-6c0b-4ed8-8207-088ce8b02531` for the degraded VMSS.
- The subscription Activity Log contains no VMSS `deallocate/action`, `powerOff/action`, or other ordinary compute operation before either stop. A focused query from `16:45Z` through `17:18:30Z` returned no initiating VMSS control-plane operation.
- The AKS managed identity performed `virtualMachineScaleSets/manualUpgrade/action` at `17:18:40Z` and wrote VM instance 0 at `17:19:41Z`. These operations occurred after both stops and are repair/reconciliation evidence, not the initiating action.
- `kube-audit-admin` shows normal kubelet lease updates before heartbeat loss; it does not identify an actor that initiated the VM deallocation. Control-plane logs show Kubernetes reacting to the Azure VM power state rather than requesting the stop.
- A real Activity Log alert activated at approximately `17:21:39Z`, proving that exported Alert records and the deployed rules are firing. Email delivery still needs confirmation from the recipient.
- A fresh subscription Resource Graph inventory found no DevTest shutdown schedule targeting this AKS VMSS. Existing DevTest schedules and Logic Apps target unrelated resources. VMSS automatic repairs are unset, upgrade mode is `Manual`, Spot priority is not configured, and scheduled-events configuration is absent.
- AppLens again failed to create an AKS diagnostic session with Azure `BadRequest`, so it supplied no additional attribution.
- Revised conclusion: the current strongest evidence is an authorized user-or-process deallocation, but Azure's available logs do not expose that actor. The recurrence on the current node image materially weakens the previous NodeImage hypothesis. Do not attribute the stop to AKS maintenance without additional Azure-internal evidence.
- The user initially chose to preserve the deallocated failure state, then explicitly ended preservation at 2026-10-13 15:31 EDT and approved enabling guarded auto-recovery. Starting the currently deallocated instances through the guarded workflow is now authorized; reimage, upgrade, delete, and unrelated mutations remain unapproved.
- A support-ready case draft is stored in the persistent session artifact `files/aks-support-case-2026-10-13.md`. It contains the incident timeline, resource identifiers, correlation IDs, negative evidence, prior recurrence, and specific attribution questions for Microsoft.
- Guarded node auto-recovery is deployed and enabled. The design uses a dedicated stateful node-not-ready action group, a five-minute safety delay, an exact-VMSS query, one start attempt for only deallocated instances, a three-minute verification, and a custom managed-identity role scoped to VMSS read/start operations.
- Targeted subscription deployment `litellm-aks-node-auto-recovery` succeeded at `2026-10-13T19:33:03Z`. It created Logic App `litellm-aks-node-auto-recovery`, dedicated action group `litellm-aks-auto-recovery`, custom role `LiteLLM AKS VMSS Start Operator`, and a role assignment scoped to `aks-system-18292702-vmss`. The dedicated action group is attached only to the stateful node-not-ready alert, preventing compute-lifecycle alert loops.
- The first manually triggered guarded run started at `19:33:38Z`, waited five minutes, found both instances deallocated, invoked the VMSS start action once, waited three minutes, verified no instance remained deallocated, and completed `Succeeded` at `19:42:53Z`.
- Both VMSS instances now report Running/Succeeded and both Kubernetes nodes are Ready. Workload Identity recovered with two webhook endpoints, PostgreSQL is Ready, and no pod or Deployment remains unhealthy.
- LiteLLM's ReplicaSet remained in the prior webhook `FailedCreate` backoff after node recovery. A normal Deployment rollout restart cleared the stale controller state; LiteLLM and PostgreSQL are both Ready with zero current pod restarts.
- Post-recovery public validation passed: `/mcp` returns the expected unauthenticated HTTP 401, while `/ui` and `/v1` remain blocked by ingress with HTTP 404.

## Operational Notes

- The two AKS VMSS instances have been externally deallocated more than once while the AKS control plane and node pool report Running. They were started as a prerequisite to the approved `1.105.0` upgrade and recovered to Ready. Subscription-level shutdown automation may deallocate them again.
- The recurring outage was reinvestigated before starting the Foundry middleware build. Both VMSS instances are again `PowerState/deallocated`; both Kubernetes nodes are `NotReady` with `NodeStatusUnknown`, `node.cloudprovider.kubernetes.io/shutdown`, and `node.kubernetes.io/out-of-service` taints. AKS and the node pool still incorrectly appear healthy at the high-level resource surface (`Succeeded`/`Running`).
- The LiteLLM Deployment and one-replica ReplicaSet still exist. LiteLLM's pod is not being deleted by an application process: the ReplicaSet has recorded repeated `FailedCreate` events because the Azure Workload Identity mutating webhook has no endpoints while both nodes are down. PostgreSQL's already-created pod remains Pending because both nodes have shutdown/out-of-service taints.
- Seven-day Azure Activity Log analysis found no VMSS `deallocate/action`, `powerOff/action`, AKS `stop/action`, DevTest schedule targeting the cluster, shutdown policy, Automation account, Logic App receiver, webhook receiver, Azure Function receiver, or VMSS Spot/eviction configuration. The subscription budgets notify by email/role only and do not execute shutdown automation.
- The VMSS instance reconciliation writes are made by the AKS cluster managed identity, confirmed by `xms_mirid` pointing to `litellm-demo-aks`. They occur after kubelet heartbeats stop, so they are AKS repair/reconciliation activity rather than evidence of a user-issued shutdown.
- The leading trigger is a failing automatic AKS node-image maintenance cycle: source and live configuration set `nodeOSUpgradeChannel: NodeImage`, no planned-maintenance window exists, the installed image is `AKSAzureLinux-V3gen2-202609.15.0`, and AKS reports `AKSAzureLinux-V3gen2-202610.03.0` as the latest image. The nodes stop sequentially and AKS then writes their instance models, which matches a rolling maintenance/repair pattern. This is a high-confidence correlation but not a definitive Azure platform root cause because control-plane diagnostic settings were not enabled and AppLens could not create an AKS diagnostic session.
- Recommended remediation sequence is: start both VMSS instances to restore service; perform an explicit node-image-only upgrade to the reported latest image; add an `aksManagedNodeOSUpgradeSchedule` maintenance window of at least four hours; enable AKS control-plane diagnostic settings; and open an Azure support case with the recorded node/VMSS timestamps if deallocation recurs after the explicit upgrade.
- The user approved the immediate recovery only. VMSS instances 0 and 1 were started and both report `VM running`; both Kubernetes nodes returned to Ready. The Workload Identity webhook recovered with two endpoints, LiteLLM was recreated and became Ready, PostgreSQL became Ready, and both ingress controllers are Running.
- Post-recovery public validation passed: `/mcp` returns the expected unauthenticated HTTP 401 in approximately 296 ms, while `/ui` and `/v1` remain blocked by ingress with HTTP 404. No node-image upgrade or maintenance-setting change has yet been performed.
- The user subsequently approved an explicit node-image-only upgrade. Preflight checks confirmed the workload PDBs allowed one disruption and East US 2 had enough regional vCPU quota for the 33% surge.
- The AKS upgrade completed successfully. The system pool now runs `AKSAzureLinux-V3gen2-202610.03.0`, both VMSS instances remain Running/Succeeded, both nodes are Ready on kernel `6.6.157.1-1.azl3`, and no unhealthy `kube-system` pod remains.
- Post-upgrade LiteLLM, PostgreSQL, and both ingress controllers are Ready. Public `/mcp` returns the expected HTTP 401 in approximately 217 ms, `/ui` and `/v1` remain HTTP 404, and authenticated `customer-chat` inference returned exactly `Node image upgrade passed.`
- The explicit upgrade clears the stale image state that was the leading correlated trigger. The cluster should now be observed through the next automatic maintenance cycle; recurrence on the current image would disprove or weaken that diagnosis and should trigger an Azure support case. Planned-maintenance and control-plane diagnostic settings are still recommended and have not yet been configured.
- Eastern-time reconstruction of the last deallocation cycle shows a rolling sequence, not a simultaneous scheduled shutdown. Node 0's final kubelet heartbeat was 2026-10-12 22:06 EDT and it became `NotReady` at 22:09; AKS wrote its VMSS instance model at approximately 22:19. Node 1's final heartbeat was 2026-10-13 00:08 EDT and it became `NotReady` at 00:11; AKS wrote its instance model at approximately 00:20. Azure did not emit a timestamped `deallocate/action`, so the exact power transition is bounded by those heartbeat and reconciliation times.
- A separate earlier recurrence had already left the nodes deallocated by approximately 2026-10-12 14:28 EDT. The available evidence therefore does not support a single fixed daily shutdown time; it is more consistent with repeated maintenance/repair attempts while the node image was stale.
- At 2026-10-13 09:31 EDT, both VMSS instances remain Running/Succeeded, both nodes are Ready, and LiteLLM/PostgreSQL are Running after the explicit image upgrade. The upgrade's Activity Log shows the expected AKS-managed VMSS write, manual-upgrade, reimage, and cleanup operations between approximately 08:57 and 09:16 EDT.
- AKS observability setup began at 2026-10-13 09:33 EDT. The existing Log Analytics workspace is healthy and the AKS monitoring add-on reports enabled, but the workspace has no recent `KubeNodeInventory` or `Heartbeat` records. All `ama-logs` node agents report `No JSON file found in the specified directory` while parsing their DCR, and Azure reports no Data Collection Rule association for the cluster. A safe `az aks enable-addons` reapply was rejected because the add-on is already enabled; the supported repair requires re-onboarding the monitoring add-on or explicitly deploying its missing DCR/DCRA. No workload-impacting change occurred during this check.
- The monitoring add-on was re-onboarded against the existing workspace without restarting nodes or application workloads. Azure created DCR `MSCI-eastus2-litellm-demo-aks` and cluster association `ContainerInsightsExtension`; AKS returned `Succeeded`, both nodes remained Ready, and LiteLLM/PostgreSQL remained Running. The initial agent rollout check raced the replacement because the old `ama-logs` DaemonSet had already been removed, so ingestion verification remains pending.
- Container Insights repair is verified end to end: both replacement `ama-logs` agents are healthy with no DCR/authentication errors, and fresh `Ready` records for both nodes are present in `KubeNodeInventory`.
- AKS diagnostic setting `aks-control-plane` now exports `kube-apiserver`, `kube-audit-admin`, `kube-controller-manager`, `kube-scheduler`, `cluster-autoscaler`, `cloud-controller-manager`, `guard`, and `AllMetrics` to the existing workspace using resource-specific tables. Subscription diagnostic setting `litellm-subscription-activity` now exports Administrative, Security, ServiceHealth, Alert, Recommendation, Policy, Autoscale, and ResourceHealth events to that workspace.
- Action group `litellm-aks-operations` now emails the deployment owner using the common alert schema. The `litellm-aks-node-resource-health` and `litellm-aks-node-not-ready` alerts deployed successfully. Azure rejected the first compute-lifecycle rule because `operationName` requires explicit `anyOf` leaves; the Bicep was corrected and redeployment is pending.
- All three alert rules are now deployed and enabled. The node query runs every five minutes over a ten-minute window and detects both non-Ready status and fewer than two reporting nodes, covering the complete telemetry loss expected when nodes are deallocated. The compute-lifecycle alert also captures VMSS/instance writes because those were the only Azure operations observed immediately after the previous heartbeat loss.
- Control-plane ingestion is verified with current `AKSControlPlane` and `AKSAuditAdmin` records. The live node alert query returns no rows while both nodes report `Ready`. The action-group receiver is enabled and all rules reference it, but the Azure CLI synthetic notification endpoint rejected its test payload with `There are no valid receivers in the request`; email delivery is configured but not yet proven by a synthetic or real alert.
- Durable Bicep now declares the Container Insights DCR/DCRA, AKS control-plane diagnostics, subscription Activity Log export, action group, and alerts. The deployment script derives the signed-in user's email for notifications. Operational queries and validation steps are documented in `docs/aks-observability.md`.
- Subscription Activity Log export is verified with new Alert-category records in `AzureActivity`. The generated ARM template, Bicep compilation, alert-module validation/deployment, Bash syntax check, and `git diff --check` passed.
- A full subscription deployment was not run. Its successful what-if showed unrelated/pre-existing drift on the AKS resource, workload identity, federation issuer, and model role assignment in addition to harmless observability normalization. To avoid changing those surfaces, the live diagnostic settings and alert module were deployed directly and only the observability configuration was changed.
- The Foundry middleware design is now explicitly mapped to Microsoft's application-managed OBO flow. The AKS middleware is the trusted backend: it validates the user token, performs OBO for the LiteLLM delegated scope, acquires a separate Foundry workload token, derives `x-ms-user-identity`, and invokes Foundry. Foundry forwards only the custom `x-client-litellm-user-token` to hosted-agent code; the hosted agent then calls LiteLLM with the delegated token plus an internal DeepWiki-only virtual key.
- The user requested a collaborative middleware build and explicitly prohibited automatic Entra registration creation. `scripts/configure-foundry-middleware-apps.sh` remains reference automation only and must not be run for this POC. App registrations, permissions, credentials, consent, and Foundry identity delegation will be completed manually with the user, one reviewed portal step at a time.
- Middleware implementation stack selected collaboratively: Python 3.12+, FastAPI, MSAL, PyJWT, HTTPX, and `azure-identity`. The first API is a constrained `POST /v1/responses`; streaming, background execution, stored responses, unknown fields, and caller-selected destinations are rejected. The POC confidential credential will be a client secret injected later through a Kubernetes Secret and never stored in Git.
- The initial middleware implementation now includes fail-closed configuration, tenant-specific Entra JWT validation, delegated-scope enforcement, MSAL OBO exchange, AKS Workload Identity authentication to Foundry, trusted `x-client-litellm-user-token` and `x-ms-user-identity` forwarding, health endpoints, and sanitized upstream errors.
- Eleven focused tests pass, including real RSA-signed token validation for issuer, audience, tenant, object ID, delegated scope, and JWKS rotation. Ruff lint/format, Python compilation, and strict Pylance diagnostics pass. No Entra or Azure resource was created or modified.
- A secure non-root Python 3.12 container definition and placeholder Kubernetes Deployment, ClusterIP Service, ConfigMap, Secret, and workload-identity ServiceAccount are present under `middleware/`. They have not been built, pushed, or applied. Tenant IDs, middleware client ID, client secret, Foundry endpoint, workload identity client ID, and deployable image remain intentionally unset for the manual collaborative steps.
- Final local validation for this middleware phase passed: 11 pytest tests, Ruff lint and format, Python compilation, strict Pylance diagnostics, `git diff --check`, and Kubernetes client-side dry-run for all five manifests. The local Python interpreter is 3.14, so pytest-asyncio emits upstream Python 3.16 deprecation warnings; the runtime target remains Python 3.12.
- Docker CLI 28.3.3 is installed, but the local Docker daemon is not running. No image was built or pushed, and no Azure build service was used. Deployment remains blocked on the manual Entra registrations, confidential credential, AKS workload identity/federation, Foundry permissions and hosted-agent endpoint, container registry/image, and explicit deployment approval.
- The middleware walkthrough now documents Pydantic field validators, cached derived settings, the OAuth versus OpenID discovery distinction, JWKS key rotation, and why the untrusted JWT `kid` header must exist as a string before key lookup. It also clarifies that the header shape check is not authentication; signature verification against the selected Entra public key establishes authenticity.
- Core middleware modules now include concise docstrings and security-boundary comments for readers unfamiliar with the implementation. The annotations distinguish untrusted JWT parsing from cryptographic validation, explain algorithm pinning and `kid` lookup, JWKS rotation, OBO token-audience exchange, AKS Workload Identity, Foundry header roles, sanitized errors, and dependency injection without commenting routine syntax.
- Every middleware Python file now starts with a module-level purpose docstring. Production files explain their role in the validate -> OBO -> Foundry path, and test files identify the security boundary and behavior they prove.
- Customer deployment ownership is now documented explicitly. Customers consume the versioned middleware image and Kubernetes package rather than recreating the Python files; they provide tenant-specific Entra registrations, scopes, credentials, workload identity, Foundry endpoint and permissions, image, and secrets. The hosted-agent code remains a separate component that forwards the delegated token to LiteLLM with an internally stored restricted virtual key.
- Manual Entra registration work has started. The current portal no longer labels the native CLI redirect platform **Public client/native**; it presents **Mobile and desktop applications**. The walkthrough now instructs users to register the CLI without an initial redirect URI, then use **Authentication** > **Add a platform** > **Mobile and desktop applications**, add `http://localhost`, and enable **Allow public client flows**. The CLI remains a public client and must not receive a client secret.
- Read-only verification confirms `litellm-foundry-middleware-api` exposes an enabled `access_as_user` scope and `litellm-foundry-cli-client` already has that delegated permission, the `http://localhost` public-client redirect URI, and fallback public-client mode enabled. Preauthorization is still empty on the middleware API. The user was viewing the CLI's **Expose an API** page, where **Add a client application** is correctly unavailable because the CLI defines no scopes. The walkthrough now requires switching explicitly back to the middleware registration before adding the CLI under **Authorized client applications**. The CLI has an unnecessary Application ID URI from visiting/initializing **Expose an API**; it is non-blocking and should be removed manually after review.
- A second read-only audit after the user completed the portal steps confirms the identity chain is correctly wired. Both registrations are single-tenant and have enabled service principals. The middleware API uses v2 access tokens, exposes its enabled user-consentable `access_as_user` scope, requests the enabled LiteLLM `access_as_user` delegated scope, and preauthorizes the exact CLI application for the middleware scope. The CLI has `http://localhost`, public-client mode, no exposed scopes, no credentials, and requests the exact middleware scope. Tenant-wide delegated consent grants exist for CLI -> middleware `access_as_user` and middleware -> LiteLLM `access_as_user`. The middleware currently has no password or certificate credential, which is expected because credential creation is the next reviewed step. Non-blocking least-privilege cleanup remains: remove the accidental CLI Application ID URI and decide whether to remove the portal-default Microsoft Graph `User.Read` permission and consent grant from both new applications.
- The user created the middleware confidential-client credential. Read-only Entra metadata confirms one password credential named `middleware-access-by-cli-client`, valid from 2026-10-14 through 2028-10-13. The name is non-blocking but slightly misleading because the credential authenticates the middleware during OBO, not the CLI. The local registration file is covered by the repository's `local-files/` ignore rule, is not tracked, and was tightened from mode `0644` to owner-only `0600` without reading its contents. The secret value has not been displayed, copied into source, or injected into Kubernetes yet; Entra cannot reveal it again, so correctness of the stored value will be proven only by a real OBO token exchange. A shorter rotation period should be considered for production.
- Secret handling is now explicit and automated safely. `middleware/.env` remains intentionally absent and is optional only for ignored local development; AKS receives settings from ConfigMap and Secret environment variables. The tracked `middleware/k8s/secret.yaml` must retain `REPLACE_ME`. New helper `scripts/configure-foundry-middleware-secret.sh` uses a hidden prompt and stdin-based `kubectl` generation so the real OBO secret is not placed in YAML, command arguments, or shell output. It has not been run; the live middleware Kubernetes Secret has not yet been created.
- `auth.py` now labels the three validation stages inline and explains each `jwt.decode` control: signing key, pinned algorithm, middleware audience, tenant issuer, clock skew, and required claims. It also annotates tenant, `oid`, subject, and delegated-scope enforcement, while `app.py` identifies the validation call that must succeed before OBO.
- The same staged annotation theme now covers the remaining production modules: configuration sources and normalization in `config.py`; confidential-client binding, audience exchange, success/failure handling, and Conditional Access in `obo.py`; workload identity, fixed destinations, distinct header roles, and response sanitization in `foundry.py`; request restrictions in `models.py`; and startup, health, authentication, orchestration, and error translation in `app.py`.
- JWKS refresh behavior was reviewed while explaining `time.monotonic()`. A cache-guard bug was found where an unfamiliar `kid` could request refresh but the still-current cache caused `_refresh_keys` to return without fetching the rotated key. The implementation now distinguishes ordinary expiry from required-key refresh, rechecks after acquiring the lock, and rate-limits unknown-key refreshes with a configurable 60-second cooldown. A synthetic RSA key-rotation test covers this path.
- `kubelogin` was installed with `az aks install-cli` because Homebrew was blocked by the machine's Xcode version.
- The generated LiteLLM master key exists only in the Kubernetes Secret `litellm-master-key`; it is not stored in Git.
- Access requires a local port-forward:

  ```bash
  kubectl port-forward -n litellm service/litellm 4000:4000
  ```
- The Microsoft Agent 365 MCP guardrail is a separate flow from ordinary chat completions. It requires a configured MCP server, a database-backed LiteLLM virtual key scoped to that server, and a delegated user Entra token on every guarded MCP call.
- DeepWiki was selected as the MVP MCP server.
- `customer-chat` is a LiteLLM model alias deployed in the gateway ConfigMap, not a separate application.
- The LiteLLM quick start's two-header flow is not a direct match for the Copilot Studio MCP wizard, which selects one server authentication method. The CLI MVP validated both headers; OAuth-only LiteLLM JWT authentication was selected for Copilot Studio.
- The Copilot Studio manual OAuth form may use the existing gateway application ID for this POC because one Entra registration can act as both OAuth client and resource API. Copilot Studio must use a new, dedicated secret credential on that registration and must not reuse the Kubernetes-stored Agent 365/OBO secret.
- A separate Copilot Studio client registration remains the production recommendation because it isolates redirect URIs, delegated consent, credentials, audit events, and rotation from LiteLLM's confidential OBO identity.
- Manual OAuth values are documented in `docs/agent365-mcp-guardrail.md`, including the tenant-specific authorize/token endpoints, gateway `access_as_user` scope, and post-create Web redirect-URI step.
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

1. [x] Deploy and validate guarded node auto-recovery.
2. Monitor the next alert-driven run and confirm the action-group email plus automatic trigger arrive without manual invocation.
3. Open an Azure support case using the exact heartbeat, Resource Health, and correlation-ID evidence above; request authenticated-actor attribution.
4. Resume the manual Entra registration walkthrough for the Foundry OBO middleware. Do not run the Entra automation script.

## Handoff Rules

1. Read `local-files/gateway-prompt.md` and `.azure/deployment-plan.md`.
2. Run `scripts/status.sh` to inspect live Azure and Kubernetes state.
3. Do not expose the generated master key or commit kubeconfig/secret files.
4. Explain and obtain approval before Azure or Kubernetes mutations.
5. Obtain explicit approval before destructive actions.
