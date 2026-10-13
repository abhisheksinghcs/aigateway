# LiteLLM AI Gateway on AKS

Enterprise-style, cost-conscious LiteLLM AI Gateway lab for customer demonstrations and workshops.

## Current Scope

- Azure Kubernetes Service in East US 2
- Two `Standard_D4as_v6` nodes
- Azure CNI Overlay with Cilium
- Microsoft Entra authentication and AKS Workload Identity
- Existing Azure AI Services `o4-mini` deployment
- Logical LiteLLM model alias: `customer-chat`
- Microsoft Agent 365 `pre_mcp_call` guardrail with DeepWiki MCP
- Publicly trusted HTTPS ingress for the authenticated `/mcp` route
- Bicep infrastructure and Helm application deployment

The POC includes a bundled single-node PostgreSQL instance so the LiteLLM admin panel and persistent management features work. The Agent 365 guardrail MVP is validated, and the public `/mcp` endpoint has trusted TLS. The Admin UI and `/v1` are not exposed by the public ingress. Redis, multi-model routing, fallback, expanded FinOps, additional guardrails, managed PostgreSQL, production DNS, and private model networking remain later phases.

## Approval Boundaries

Repository artifacts may be generated and validated locally. No Azure deployment, Azure RBAC change, Helm installation, or destructive operation is authorized unless it is separately explained and explicitly approved.

The source-of-truth plan is [.azure/deployment-plan.md](.azure/deployment-plan.md). The cross-session handoff is [status.md](status.md). The proposed Microsoft Agent 365 MCP integration and its Copilot Studio caveats are documented in [docs/agent365-mcp-guardrail.md](docs/agent365-mcp-guardrail.md). The Foundry hosted-agent middleware identity and token flow are documented in [docs/foundry-middleware.md](docs/foundry-middleware.md). AKS deallocation diagnostics, alerts, and investigation queries are documented in [docs/aks-observability.md](docs/aks-observability.md).

## Repository Layout

```text
infra/          Bicep infrastructure
kubernetes/     Namespace and Helm values
litellm/        LiteLLM gateway configuration
scripts/        Prerequisite, deployment, test, and status automation
docs/           Architecture and security documentation
```

## Local Validation

```bash
az bicep build --file infra/main.bicep
```

```bash
helm template litellm \
  oci://ghcr.io/berriai/litellm-helm \
  --version 1.105.0 \
  --namespace litellm \
  --values kubernetes/values.yaml \
  --set-string serviceAccount.annotations.azure\\.workload\\.identity/client-id=00000000-0000-0000-0000-000000000000
```

## Deployment Status

The approved POC scope is deployed and functionally verified. The MCP endpoint is:

```text
https://litellm-agent365-mcp-d18f2ff3.eastus2.cloudapp.azure.com/mcp
```

An unauthenticated request returns HTTP 401 from LiteLLM. The Admin UI remains private and is accessed with a local port-forward:

```bash
kubectl port-forward -n litellm service/litellm 4000:4000
```

Run `scripts/status.sh` for current Azure and Kubernetes state. See [status.md](status.md) for the deployment handoff and known operational notes.

See [docs/architecture.md](docs/architecture.md), [docs/security.md](docs/security.md), [docs/agent365-mcp-guardrail.md](docs/agent365-mcp-guardrail.md), [docs/foundry-middleware.md](docs/foundry-middleware.md), and [docs/aks-observability.md](docs/aks-observability.md) for design details.