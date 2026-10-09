# LiteLLM AI Gateway on AKS

Enterprise-style, cost-conscious LiteLLM AI Gateway lab for customer demonstrations and workshops.

## Current Scope

- Azure Kubernetes Service in East US 2
- Two `Standard_D4as_v6` nodes
- Azure CNI Overlay with Cilium
- Microsoft Entra authentication and AKS Workload Identity
- Existing Azure AI Services `o4-mini` deployment
- Logical LiteLLM model alias: `customer-chat`
- ClusterIP-only initial gateway exposure
- Bicep infrastructure and Helm application deployment

PostgreSQL, Redis, virtual keys, multi-model routing, fallback, FinOps, guardrails, public HTTPS ingress, and private model networking are introduced in later phases.

## Approval Boundaries

Repository artifacts may be generated and validated locally. No Azure deployment, Azure RBAC change, Helm installation, or destructive operation is authorized unless it is separately explained and explicitly approved.

The source-of-truth plan is [.azure/deployment-plan.md](.azure/deployment-plan.md). The cross-session handoff is [status.md](status.md).

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
  --version 1.90.2 \
  --namespace litellm \
  --values kubernetes/values.yaml \
  --set-string serviceAccount.annotations.azure\\.workload\\.identity/client-id=00000000-0000-0000-0000-000000000000
```

## Deployment Status

The approved POC scope is deployed and functionally verified. The gateway remains ClusterIP-only and is accessed with a local port-forward:

```bash
kubectl port-forward -n litellm service/litellm 4000:4000
```

Run `scripts/status.sh` for current Azure and Kubernetes state. See [status.md](status.md) for the deployment handoff and known operational notes.

See [docs/architecture.md](docs/architecture.md) and [docs/security.md](docs/security.md) for design details.