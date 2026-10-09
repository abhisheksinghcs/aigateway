# AI Gateway Lab Status

Last updated: 2026-10-09 10:32 EDT

## Current State

The approved POC scope is deployed and functionally verified. Azure infrastructure and LiteLLM are running in `eastus2`. The gateway is intentionally exposed only through a Kubernetes `ClusterIP`; there is no public endpoint.

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
- Chart and image version: `1.90.2`
- OCI chart digest: `sha256:df9be29316b0eda2b7df5ba6077a39aeb818cf20fb19b01ea4bd8937af1063b3`
- Replicas: one Ready pod
- Service: `ClusterIP` on port 4000
- Logical model: `customer-chat`
- Physical backend: Azure `o4-mini` deployment in `Agent365-Teams-Agents`
- Azure model version: `2025-04-16`
- Authentication: AKS Workload Identity; no Azure AI API key
- LiteLLM cost mapping: `model_info.base_model: azure/o4-mini`
- PostgreSQL, Redis, and migration Job: disabled/not deployed

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

## Operational Notes

- The two AKS VMSS instances were externally deallocated once while the AKS control plane still reported Running. They were started with explicit approval and recovered to Ready. Subscription-level shutdown automation may deallocate them again.
- `kubelogin` was installed with `az aks install-cli` because Homebrew was blocked by the machine's Xcode version.
- The generated LiteLLM master key exists only in the Kubernetes Secret `litellm-master-key`; it is not stored in Git.
- Access requires a local port-forward:

  ```bash
  kubectl port-forward -n litellm service/litellm 4000:4000
  ```

## Deferred Scope

- Public HTTPS ingress, DNS, and certificate ownership
- PostgreSQL-backed virtual keys, users, teams, budgets, and spend history
- Redis and multiple LiteLLM replicas
- Multiple models, routing, fallback, and load balancing
- Key Vault and private endpoints
- Private Azure AI networking
- Expanded observability, guardrails, and FinOps demonstrations

## Next Step

No required deployment work remains for the approved POC scope. Choose and approve a deferred capability before making additional Azure or Kubernetes changes.

## Handoff Rules

1. Read `local-files/gateway-prompt.md` and `.azure/deployment-plan.md`.
2. Run `scripts/status.sh` to inspect live Azure and Kubernetes state.
3. Do not expose the generated master key or commit kubeconfig/secret files.
4. Explain and obtain approval before Azure or Kubernetes mutations.
5. Obtain explicit approval before destructive actions.
