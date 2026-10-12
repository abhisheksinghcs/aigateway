# Azure Deployment Plan

> **Status:** Validated

Generated: 2026-10-08 17:24 EDT

---

## 1. Project Overview

**Goal:** Build an enterprise-style LiteLLM AI Gateway lab on Azure Kubernetes Service for customer demonstrations, workshops, architecture discussions, and experimentation.

**Path:** New project

**Initial success condition:** A client sends an OpenAI-compatible request using logical model alias `customer-chat`; LiteLLM running on AKS authenticates with Microsoft Entra Workload Identity, routes the request to the existing `o4-mini` deployment, and returns a valid model response.

**Current boundary:** This plan prepares the repository and the first deployment wave. Azure resources must not be created until this plan is approved, generated artifacts pass validation, the required RBAC roles are granted, and the user separately approves the resource-changing deployment command.

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | POC / customer demonstration |
| Scale | Small workshops, fewer than 25 concurrent users |
| Budget | Balanced, cost-conscious demo |
| Subscription | MultiCloudTeam (`d18f2ff3-4ef1-4102-8c8f-3a344037aeed`) |
| Tenant | `e0ca6a1b-554d-4f12-87c9-92ec42abb750` |
| Location | `eastus2` |
| Compliance | Inherited Azure Policy only; no additional regulated-data requirement |
| IaC | Bicep |
| Kubernetes packaging | Official LiteLLM Helm chart |
| Initial physical model | Existing `o4-mini` deployment in `Agent365-Teams-Agents` |
| Initial logical model | `customer-chat` |

### Deployment Permissions

The signed-in principal has the required inherited authority:

- `Contributor` inherited from management group `GBB-Development`.
- `User Access Administrator` inherited from the tenant root scope.

Azure template validation with the planned role assignments enabled succeeded on 2026-10-08.

The required role assignments include:

- AKS administrative access for the deployment principal.
- `Cognitive Services OpenAI User` for the LiteLLM workload identity on the existing AI account.
- Key Vault data-plane access when Key Vault is introduced.

### Policy Constraints

- AKS clusters with more than 10 agent pools are denied.
- High-cost H, M, and N VM SKU families are denied.
- Provisioned Azure OpenAI capacity is denied.
- Cognitive Services local authentication is modified to disabled unless an approved exclusion applies.
- Key Vault public network access is modified to disabled unless an approved exclusion applies.
- AKS node OS automatic upgrade is enabled by policy.
- Cognitive Services and Foundry diagnostic settings are deployed by policy.
- No `SecurityControl=Ignore` exception will be added merely to bypass governance.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| LiteLLM gateway | API gateway | LiteLLM monolithic proxy | To be configured under `kubernetes/` and `litellm/` |
| Azure infrastructure | Infrastructure | Bicep | To be generated under `infra/` |
| Deployment automation | Operations | Bash, Azure CLI, kubectl, Helm | To be generated under `scripts/` |
| Architecture and demo documentation | Documentation | Markdown and Mermaid | To be generated under `docs/` |
| Existing model backend | AI model | Azure AI Services, `o4-mini` | Existing resource in `MC-abhi` |

The current Python hello-world files are starter placeholders and are not part of the target runtime.

---

## 4. Recipe Selection

**Selected:** Bicep plus explicit Azure CLI deployment scripts

**Rationale:**

- The user explicitly requires Bicep.
- The workload is AKS-centric and benefits from explicit control of subscription-scope and resource-group-scope deployments.
- Helm remains the appropriate deployment mechanism for LiteLLM.
- No application build or custom container image is required initially.
- The repository can adopt `azd` later if environment management or CI/CD warrants it, but it is not required for the first lab.

---

## 5. Architecture

**Stack:** Containers on AKS Standard configuration

### Initial Request Flow

```text
Demo client
    |
    | HTTPS + LiteLLM client credential
    v
Public ingress / Standard Load Balancer
    |
    v
LiteLLM monolithic proxy on AKS
    |
    | Microsoft Entra token from Workload Identity
    v
Existing Agent365-Teams-Agents account
    |
    v
o4-mini deployment
```

### Day-0 AKS Decisions

| Decision | Selection | Rationale |
|----------|-----------|-----------|
| AKS mode | Standard configuration | Predictable node count, explicit networking, and lower demo cost than AKS Automatic's mandatory Standard control-plane tier |
| Control-plane tier | Free | Appropriate for evaluation/non-production; no financially backed uptime SLA |
| Node pool | One system pool with two `Standard_D4as_v6` Linux nodes | Balanced workshop capacity using a current SKU allowed by AKS preflight in this subscription and region |
| Availability zones | No zone pinning | Azure preflight reported no supported zones for this East US 2 pool configuration; two nodes provide host-level capacity but not zonal resilience |
| Pod networking | Azure CNI Overlay | Conserves VNet address space and is a recommended general-purpose pod IP model |
| Dataplane | Cilium | Network policy enforcement and modern eBPF dataplane |
| API server | Public endpoint initially | Avoids private-cluster troubleshooting overhead in the first phase |
| Cluster authentication | Microsoft Entra ID with Azure RBAC | No local Kubernetes accounts |
| Workload authentication | OIDC issuer plus Workload Identity | Eliminates static Azure model-provider credentials |
| Outbound type | Standard Load Balancer | Lowest-complexity initial egress; controlled egress is deferred |
| Upgrade | Supported stable Kubernetes version selected at deployment time; node OS auto-upgrade follows policy | Avoids pinning a version before regional version validation |
| Registry | No ACR initially | Official LiteLLM image is pulled from GHCR; add ACR only if mirroring or custom images are required |

### Address Plan

| Network | CIDR |
|---------|------|
| VNet | `10.40.0.0/16` |
| AKS node subnet | `10.40.0.0/22` |
| Future private-endpoint subnet | `10.40.4.0/24` |
| Pod overlay CIDR | `10.244.0.0/16` |
| Kubernetes service CIDR | `10.0.0.0/16` |
| Kubernetes DNS service IP | `10.0.0.10` |

These ranges do not overlap one another. Connectivity to an enterprise hub or on-premises network will require a later overlap review.

### Service Mapping

| Component | Azure Service | SKU / Configuration | Phase |
|-----------|---------------|---------------------|-------|
| Resource boundary | Resource group | `rg-litellm-gateway-demo-eus2` | 1 |
| Gateway compute | AKS | Free tier, two `Standard_D4as_v6` nodes | 1 |
| Network | VNet | `/16`, AKS and private-endpoint subnets | 1 |
| Workload identity | User-assigned managed identity | No paid SKU | 1 |
| Central logs | Log Analytics | Pay-as-you-go, 30-day retention target | 1 |
| Gateway | LiteLLM | Monolithic official Helm chart | 2 |
| Initial entry point | Kubernetes ClusterIP plus local port-forward | Private administrative access | 2 |
| MCP entry point | NGINX HTTPS ingress with Let's Encrypt and temporary `nip.io` DNS | Exposes only authenticated `/mcp`; customer-owned DNS remains a production requirement | 7 |
| Model | Existing Azure AI Services deployment | `o4-mini`, GlobalStandard | 3 |
| Secrets hardening | Key Vault | Standard, RBAC, public access disabled, private endpoint | 5 |
| Persistent gateway state | PostgreSQL Flexible Server | Cost-conscious burstable SKU selected in Phase 6 | 6 |
| Shared cache/state | Azure Managed Redis or supported Azure Redis option | SKU selected after current service lifecycle review | 6 |

### LiteLLM Deployment Choice

- Use the current official monolithic chart: `oci://ghcr.io/berriai/litellm-helm`.
- Pin the chart and container image to an explicit reviewed release.
- Begin with one LiteLLM replica to prove the path.
- Configure resource requests, limits, probes, a PodDisruptionBudget, and topology spread behavior.
- PostgreSQL is not part of the first inference path. It is added when virtual keys, users, budgets, and per-request spend persistence are introduced.
- Redis is not part of the first inference path. It is added when multiple replicas/workers require shared caching, routing, or rate-limit state.
- The componentized `gateway`/`backend`/`ui` chart is deferred because it requires external PostgreSQL and Redis and adds complexity not needed for the first lab.

### Trust Boundaries

1. Client to LiteLLM: gateway credential and HTTPS.
2. LiteLLM pod to Microsoft Entra ID: projected service-account token.
3. Microsoft Entra ID to Azure AI Services: short-lived access token.
4. AKS to Azure control plane and monitoring: managed identities and Azure RBAC.
5. Future secret retrieval: workload identity to private Key Vault endpoint.

---

## 6. Cost Profile

| Resource | Expected cost behavior |
|----------|------------------------|
| Two `Standard_D4as_v6` Linux nodes | Current retail rate is approximately USD 0.182/hour per node in eastus2; two continuously running nodes are approximately USD 265.72/month before disks, bandwidth, taxes, or discounts |
| AKS Free tier | No cluster-management charge; no financially backed control-plane SLA |
| Managed disks | Additional low monthly cost based on selected OS disk SKU and size |
| Log Analytics | Usage-based ingestion and retention; demo traffic should remain low, but verbose prompt/response logging must not be enabled by default |
| Standard Load Balancer and public IP | Low usage-based/network cost |
| Existing `o4-mini` model | Token-based consumption; no new model deployment is planned |
| Key Vault, private endpoint, PostgreSQL, Redis | Deferred, so they do not increase initial standing cost |

Cost control:

- Provide a stop/start script for the AKS cluster.
- Do not use Spot for the only system node pool.
- Do not deploy PostgreSQL, Redis, ACR, NAT Gateway, Firewall, Application Gateway, or private model endpoints in the initial wave.

---

## 7. Provisioning Limit Checklist

The Azure CLI `quota` extension was installed and used first. Unsupported/non-quota resources were counted with Azure Resource Graph and are marked as not having a regional capacity quota exposed by the quota API.

| Resource Type | Number to Deploy | Total After Deployment | Limit / Quota | Evidence and Result |
|---------------|------------------|------------------------|---------------|---------------------|
| Resource groups | 1 | 66 | 980 documented subscription limit | Existing count 65; within limit |
| `Microsoft.ContainerService/managedClusters` | 1 | 5 | No regional quota exposed; inherited policy permits up to 10 agent pools per cluster | Existing count 4; one pool planned |
| `Microsoft.Compute/virtualMachines` - `Standard_D4as_v6` | 2 VMs / 8 vCPUs | 2 VMs / 8 added vCPUs | AKS provider preflight allows the SKU; no separate DAsv6 family quota entry is exposed | Provider preflight passed SKU availability after replacing disallowed D4as_v5 |
| `Microsoft.Compute/virtualMachines` - total regional | 8 vCPUs | 24 vCPUs used | 100 vCPUs | `az quota`: 16 used before deployment; within limit |
| `Microsoft.Network/virtualNetworks` | 1 | 11 | 1000 | `az quota`: 10 used; within limit |
| `Microsoft.OperationalInsights/workspaces` | 1 | 26 | No regional capacity quota exposed by `az quota` | Azure Resource Graph existing count 25 |
| `Microsoft.ManagedIdentity/userAssignedIdentities` | 1 | 15 | No regional capacity quota exposed by `az quota` | Azure Resource Graph existing count 14 |
| `Microsoft.Network/loadBalancers` | 0 initially; 1 with later HTTPS ingress | 4 initially, 5 later | 1000 Standard SKU | `az quota`: 4 used; within limit |
| `Microsoft.Network/publicIPAddresses` | 0 initially; 1 with later HTTPS ingress | 13 initially, 14 later | 1000 | `az quota`: 13 used; within limit |
| `Microsoft.KeyVault/vaults` | 1 in Phase 5 | 7 | No regional capacity quota exposed by `az quota` | Azure Resource Graph existing count 6 |
| `Microsoft.Network/privateEndpoints` | 1 in Phase 5 | 3 regional quota usage | 65536 | `az quota`: 2 used; within limit |
| `Microsoft.Network/privateDnsZones` | 1 in Phase 5 | 6 | No regional capacity quota exposed by `az quota` | Azure Resource Graph existing count 5 |

**Status:** All planned resources are within reported limits and the required inherited Azure RBAC is confirmed.

---

## 8. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace
- [x] Gather requirements
- [x] Confirm subscription and location
- [x] Inspect inherited Azure Policy
- [x] Inventory existing AKS and Azure AI resources
- [x] Select initial model deployment
- [x] Select AKS cost/reliability profile
- [x] Prepare resource inventory
- [x] Validate quota and capacity
- [x] Select Bicep recipe
- [x] Plan architecture
- [x] Identify deployment RBAC blocker
- [x] User approved this plan

### Phase 2: Repository Preparation

- [x] Generate Bicep infrastructure modules and demo parameter file
- [x] Generate architecture and security documentation
- [x] Generate prerequisite, deployment, status, and test scripts
- [x] Generate initial LiteLLM and Helm configuration without secrets
- [x] Add secret-safe ignore rules
- [x] Build Bicep and the Bicep parameter file
- [x] Render and lint the pinned Helm chart
- [x] Verify the chart does not deploy PostgreSQL, Redis, or a migration job
- [x] Validate shell syntax
- [x] Run subscription deployment validation and what-if
- [x] Update plan status to `Ready for Validation`
- [x] Invoke `azure-validate`

### Phase 3: Azure Deployment

- [x] Present the exact subscription deployment command and explain every resource it creates or changes
- [x] Obtain explicit approval for the resource-changing command
- [x] Invoke `azure-deploy`
- [x] Verify AKS, identity, network, and monitoring resources
- [x] Update plan with deployment outputs

### Validation Workflow

- [x] All validation checks pass
  - [x] 1. Core Validation (CLI, auth, build, validate, what-if)
  - [x] 2. Linting
  - [x] 3. Azure Policy Validation
  - [x] Static role-assignment verification

### Phase 4: LiteLLM and Model Path

- [x] Present Helm and Kubernetes mutation commands
- [x] Deploy LiteLLM monolithic chart
- [x] Configure the `customer-chat` alias for `o4-mini`
- [x] Configure Workload Identity and model RBAC
- [x] Establish a local `kubectl port-forward` to the ClusterIP service
- [x] Send a real OpenAI-compatible inference request
- [x] Prove which physical deployment served the request

### Later Capability Phases

- [ ] Key Vault and secret hardening
- [x] Bundled PostgreSQL for POC admin-panel persistence
- [ ] Managed PostgreSQL and Redis
- [ ] Multiple models
- [ ] Routing, fallback, and load balancing
- [ ] Virtual keys, quotas, and FinOps
- [ ] Observability
- [ ] Guardrails
- [ ] Customer-facing HTTPS ingress, DNS, and certificate
- [ ] Private model networking and enterprise hardening

---

## 9. Planned Commands

These commands are documented only. They must not run until their prerequisites and approval gates are satisfied.

### Local validation after files are generated

```bash
az bicep build --file infra/main.bicep
```

### Read-only Azure validation

```bash
az deployment sub validate \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters infra/parameters/demo.bicepparam
```

```bash
az deployment sub what-if \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters infra/parameters/demo.bicepparam
```

### Resource-changing deployment command

```bash
az deployment sub create \
  --name litellm-gateway-demo \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters infra/parameters/demo.bicepparam
```

This command will create or update the dedicated resource group and the resources declared by the approved Bicep template. It will not be executed without a fresh explanation of the what-if output and explicit user approval.

---

## 10. Validation Proof

| Check | Command Run | Result | Timestamp |
|-------|-------------|--------|-----------|
| Azure CLI and authentication | `validate-deployment.sh --scope sub ...` | Pass | 2026-10-08 19:12 EDT |
| Bicep compilation | `az bicep build --file infra/main.bicep` | Pass | 2026-10-08 19:12 EDT |
| Bicep parameter compilation | `az bicep build-params --file infra/parameters/demo.bicepparam` | Pass | 2026-10-08 19:12 EDT |
| Subscription template validation | Validation helper plus explicit operator principal | Pass | 2026-10-08 19:12 EDT |
| Subscription what-if | Validation helper plus explicit operator principal | Pass: 9 create, 0 modify, 0 delete, 1 runtime-dependent role assignment reported as unsupported | 2026-10-08 19:12 EDT |
| Bicep lint | `az bicep lint --file infra/main.bicep` | Pass | 2026-10-08 19:12 EDT |
| Helm chart lint | `helm lint` against pinned `litellm-helm-1.90.2.tgz` | Pass | 2026-10-08 18:56 EDT |
| Helm semantic render | `helm template` plus database workload assertion | Pass: no PostgreSQL, Redis, or migration Job | 2026-10-08 18:56 EDT |
| Shell syntax | `bash -n scripts/*.sh` | Pass | 2026-10-08 18:56 EDT |
| Azure Policy | Azure Policy MCP inherited assignment inventory plus successful validate/what-if | Pass for planned resources; existing deploy-if-not-exists policies remain applicable | 2026-10-08 19:12 EDT |
| Static role assignments | Reviewed `model-role.bicep` and AKS-scoped assignment in `aks.bicep` | Pass: least-privilege resource scopes | 2026-10-08 19:12 EDT |
| Corrective AKS RBAC validation | Bicep lint, subscription validation, and explicit-principal what-if | Pass: 1 intended role-assignment create, 0 deletes; remaining modify entries are Azure computed/default-property comparisons | 2026-10-08 19:25 EDT |
| Database-enabled Helm lint/render | Pinned chart `1.90.2`, bundled PostgreSQL and migration Job | Pass | 2026-10-09 11:29 EDT |
| PostgreSQL migration | `litellm-migrations` Job logs | Pass: all migrations and post-migration sanity check completed | 2026-10-09 11:29 EDT |
| Admin authentication | `POST /login` with `admin` and the Kubernetes-stored master key | Pass: HTTP 303 redirect to `/ui/?login=success` | 2026-10-09 11:29 EDT |
| Post-database inference | `scripts/test-gateway.sh` | Pass: `LiteLLM gateway path verified.` | 2026-10-09 11:29 EDT |
| LiteLLM `1.105.0` chart lint/render | Pinned OCI chart with existing PostgreSQL and Workload Identity values | Pass: 14 resources rendered; migration Job and pinned PostgreSQL image retained | 2026-10-12 09:23 EDT |
| LiteLLM `1.105.0` upgrade | Approval-gated `scripts/deploy-litellm.sh` | Pass: Helm revision 6 deployed; database migrations completed | 2026-10-12 09:25 EDT |
| Agent 365 runtime support | Import `Agent365Guardrail` and inspect supported hooks in the running pod | Pass: `agent_365` registered with `pre_mcp_call` | 2026-10-12 09:25 EDT |
| Post-upgrade admin and inference | `POST /login` and `scripts/test-gateway.sh` after post-migration restart | Pass: HTTP 303 login and `LiteLLM gateway path verified.` | 2026-10-12 09:26 EDT |
| Agent 365 configuration rollout | Approval-gated Helm deployment with Kubernetes Secret reference | Pass: revision 7 deployed; guardrail initialized and three DeepWiki tools discovered | 2026-10-12 10:07 EDT |
| Agent 365 delegated allow path | Temporary DeepWiki-scoped key plus gateway-audience user token | Pass: HTTP 200, guarded `read_wiki_structure` result | 2026-10-12 10:08 EDT |
| Agent 365 mandatory user context | Guarded call without delegated bearer token | Pass: HTTP 401; tool refused before execution | 2026-10-12 10:08 EDT |
| Admin UI login hardening | Database admin count, revision 8 rollout, `/login`, authenticated management API, and personal admin login | Pass: two password-backed admins; environment UI login returns 401; master-key API returns 200; personal admin login succeeds | 2026-10-12 11:44 EDT |
| MCP ingress infrastructure validation | `validate-deployment.sh --scope sub ...`, Bicep lint, and explicit-principal structured what-if | Pass: template build and subscription validation succeeded; no resource deletion change type; both existing subnet NSG associations are preserved | 2026-10-12 11:53 EDT |
| MCP ingress manifest validation | `kubectl apply --dry-run=client` for the ClusterIssuer and public ingress | Pass: `/mcp` ingress and streaming annotations accepted | 2026-10-12 11:53 EDT |
| MCP ingress static role verification | Reviewed `model-role.bicep` and the AKS-scoped assignment in `aks.bicep` | Pass: no RBAC changes introduced by the ingress remediation | 2026-10-12 11:53 EDT |
| MCP ingress Azure deployment | Approval-gated `scripts/deploy-infra.sh` | Pass: subscription deployment succeeded; subnet NSG rule provisioned; public HTTP reached ingress-nginx | 2026-10-12 11:58 EDT |
| MCP ingress TLS and route validation | Certificate readiness, trusted `curl`, OpenSSL certificate inspection, and ingress boundary requests | Pass: Let's Encrypt certificate Ready; `/mcp` returns LiteLLM HTTP 401; `/ui` and `/v1` return ingress HTTP 404 | 2026-10-12 11:59 EDT |
| MCP ingress post-deployment regression | Bicep build/lint, shell syntax, Kubernetes health, live RBAC, and `scripts/test-gateway.sh` | Pass: all workloads Ready, required roles present, and `customer-chat` returned `LiteLLM gateway path verified.` | 2026-10-12 12:00 EDT |

**Validated by:** azure-validate workflow

The unsupported what-if entry is the `Cognitive Services OpenAI User` assignment on the existing model account. Azure cannot calculate its deterministic name during what-if because the new managed identity principal ID is available only at deployment time. Template validation with this assignment enabled succeeded.

The infrastructure was evaluated against pinned Azure Verified Modules. VNet, Log Analytics, and the user-assigned identity use AVM. The refreshed proof above covers the resulting template.

### Live Role Verification

- The LiteLLM workload identity retains `Cognitive Services OpenAI User` on the existing `Agent365-Teams-Agents` account.
- The deployment principal retains `Azure Kubernetes Service RBAC Cluster Admin` on `litellm-demo-aks`.
- The MCP ingress remediation introduced no new role assignment and changed no application identity.
- Status: Pass, 2026-10-12 12:00 EDT.

AKS remains a direct Bicep resource after evaluating AVM `0.14.0`: its nullable OIDC issuer output resolves to null during what-if, causing the downstream Workload Identity federated credential deployment parameter to be omitted. This prevents a complete single-pass preview. VNet, Log Analytics, and the user-assigned identity continue to use pinned AVM modules.

## Role Assignment Verification

- Status: Verified
- Workload identity: `litellm-demo-workload-id`
- Model role: `Cognitive Services OpenAI User` scoped to the existing `Agent365-Teams-Agents` account
- Operator role: `Azure Kubernetes Service RBAC Cluster Admin` scoped to the new AKS cluster
- Deployment principal: inherited `Contributor` plus `User Access Administrator` has been confirmed
- No subscription-wide data-plane role is granted to the LiteLLM workload

Post-deployment Kubernetes authorization found that the initial direct AKS wrapper used the similarly named control-plane `Azure Kubernetes Service Cluster Admin Role` GUID. The wrapper was corrected to the data-plane `Azure Kubernetes Service RBAC Cluster Admin` GUID and the corrective deployment passed validation.

### Live Role Verification

- Correct operator assignment: `Azure Kubernetes Service RBAC Cluster Admin` (`b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b`) on `litellm-demo-aks` - verified
- Workload assignment: `Cognitive Services OpenAI User` on `Agent365-Teams-Agents` - verified
- Kubernetes authorization: verified by listing both Ready AKS nodes through Entra authentication
- Superseded assignment cleanup: completed with explicit approval; only the intended RBAC data-plane assignment remains
- Node runtime status: both VMSS instances were found externally deallocated; with explicit approval they were started and both returned to `Ready`
- System workload status: all `kube-system` pods recovered to `Running` or `Completed`
- Status: Pass

### Deployment Outputs

- Deployment: `litellm-gateway-demo`
- Provisioning state: `Succeeded`
- Resource group: `rg-litellm-gateway-demo-eus2`
- AKS cluster: `litellm-demo-aks`
- Log Analytics workspace: `litellm-demo-law-khtkwbank4rg6`
- Workload identity client ID: `931ce226-34a7-47ac-9d6d-6e74f786632b`
- Workload identity principal ID: `9c3c1cf7-5048-4c1e-8228-89604c7e82c5`

### LiteLLM Functional Verification

- Helm release: `litellm`, revision 8, chart/image `1.105.0`
- OCI chart digest: `sha256:9d907efc6799afb994d15add76c90ea7557d9a3348450a895ddf4eb09a812f55`
- Multi-architecture image index digest: `sha256:60947db020b57e204823d3fbc8bb295c85be890d7c9adcc77fb4f5fc2fe410b2`
- Rollback points: revision 7 before UI login hardening; revision 6 before the guardrail configuration; revision 5 before the `1.105.0` upgrade
- Workload state: one Ready pod, zero restarts during validation
- Exposure: ClusterIP only; no public endpoint
- Identity: projected Azure Workload Identity token and required Azure environment variables verified
- PostgreSQL: single Ready replica with an 8 Gi bound PVC
- PostgreSQL image: pinned legacy mirror digest `sha256:ea55532b6f75afbc97f617d91ec5efae17609c8eb825a31845fa9cb9e4aa13e1` because the chart-pinned tag was removed from the primary Bitnami repository
- Migration Job: completed successfully and removed by its TTL policy
- Agent 365: `agent365-mcp` is deployed as default-on, fail-closed `pre_mcp_call`; DeepWiki allow path and missing-user-token refusal are verified
- Admin UI: database-backed administrators are enabled and environment/master-key form login is disabled; the master key remains valid for management APIs
- Redis: absent
- Admin authentication: `admin` plus the existing master key succeeds and redirects to `/ui/?login=success`
- Logical model: `customer-chat`
- Physical provider/model: Azure `o4-mini`, confirmed by LiteLLM router logs with HTTP 200
- Functional response: `LiteLLM gateway path verified.`
- Cost mapping: `model_info.base_model: azure/o4-mini`; post-change logs contain no unidentified-model cost warning
- Status: Pass

---

## 11. Files to Generate After Approval

| File | Purpose | Status |
|------|---------|--------|
| `.azure/deployment-plan.md` | Source-of-truth deployment plan | Validated |
| `README.md` | Lab overview and phased workflow | Complete |
| `infra/main.bicep` | Subscription-scope orchestration | Complete |
| `infra/parameters/demo.bicepparam` | Non-secret demo parameters | Complete |
| `infra/modules/network.bicep` | VNet and subnets | Complete |
| `infra/modules/identity.bicep` | LiteLLM workload identity | Complete |
| `infra/modules/monitoring.bicep` | Log Analytics workspace | Complete |
| `infra/modules/aks.bicep` | AKS cluster and RBAC | Complete |
| `kubernetes/namespace.yaml` | LiteLLM namespace | Complete |
| `kubernetes/values.yaml` | Secret-free monolithic chart values | Complete |
| `litellm/config.yaml` | Initial logical model configuration | Complete |
| `docs/architecture.md` | Mermaid architecture and flows | Complete |
| `docs/security.md` | Trust boundaries and controls | Complete |
| `scripts/prerequisites.sh` | Read-only prerequisite checks | Complete |
| `scripts/deploy-infra.sh` | Explained Bicep deployment wrapper | Complete |
| `scripts/deploy-litellm.sh` | Approval-gated Helm deployment | Complete |
| `scripts/test-gateway.sh` | Functional inference test | Complete |
| `scripts/status.sh` | Read-only Azure and Kubernetes status | Complete |

---

## 12. References Used

- LiteLLM production deployment: https://docs.litellm.ai/docs/proxy/deploy
- LiteLLM production guidance: https://docs.litellm.ai/docs/proxy/prod
- LiteLLM Azure authentication: https://docs.litellm.ai/docs/providers/azure
- LiteLLM database usage: https://docs.litellm.ai/docs/proxy/db_info
- LiteLLM caching: https://docs.litellm.ai/docs/proxy/caching
- AKS pricing tiers: https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers
- Azure CNI Overlay: https://learn.microsoft.com/azure/aks/azure-cni-overlay
- AKS Workload Identity: https://learn.microsoft.com/azure/aks/workload-identity-overview

---

## 13. Next Step

Run the required Azure validation workflow. Subscription validation and what-if remain blocked until the documented RBAC roles are granted. No deployment is authorized.
