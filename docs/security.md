# Security Model

## Trust Boundaries

### Client Authentication

The client authenticates to LiteLLM. The initial administrative credential is a randomly generated LiteLLM master key stored only as a Kubernetes Secret. It is never committed to Git.

Virtual keys replace use of the master key by demo applications after PostgreSQL is introduced.

### Downstream Authentication

LiteLLM authenticates to Azure AI Services using Microsoft Entra Workload Identity:

1. The LiteLLM pod uses the `litellm` Kubernetes service account.
2. AKS projects a short-lived service-account token into the pod.
3. Microsoft Entra ID validates the federated identity credential.
4. `DefaultAzureCredential` obtains an Azure AI access token.
5. Azure RBAC authorizes the identity with `Cognitive Services OpenAI User`.

No Azure AI API key or client secret is required.

## Initial Controls

| Layer | Control |
|-------|---------|
| Azure subscription | Inherited deny, modify, and diagnostic policies |
| AKS control plane | Microsoft Entra authentication, Azure RBAC, local accounts disabled |
| Pod identity | OIDC issuer and Workload Identity |
| Network | Azure CNI Overlay with Cilium network-policy support |
| Gateway exposure | ClusterIP only; no public HTTP endpoint |
| Gateway credential | Random master key in a Kubernetes Secret |
| Model authorization | Least-privilege Azure RBAC assignment |
| Telemetry | Log Analytics baseline; secrets and authorization headers must not be logged |
| Source control | No keys, passwords, kubeconfigs, or connection strings |

## Known Phase 1 Tradeoffs

- The AKS API server is public, but it requires Microsoft Entra ID and Azure RBAC.
- The Azure AI endpoint remains public and is protected by Microsoft Entra authentication.
- The LiteLLM master key is initially a Kubernetes Secret because inherited policy makes a new Key Vault private-only. Key Vault integration is added together with private connectivity rather than bypassing policy.
- One LiteLLM replica proves the path but is not highly available.
- AKS Free tier has no financially backed control-plane uptime SLA.

## Deferred Hardening

- Private Key Vault endpoint and Secrets Store CSI integration
- Public HTTPS ingress with customer-owned DNS and certificate
- Private Azure AI endpoint and private DNS
- Restricted egress through an approved enterprise path
- PostgreSQL with Microsoft Entra authentication where supported by LiteLLM
- Redis with Microsoft Entra authentication where supported by LiteLLM
- Namespace egress network policies after required endpoints are enumerated
- Multiple LiteLLM replicas, anti-affinity, and availability validation

## Prohibited Practices

- Do not add `SecurityControl=Ignore` to bypass inherited policy without an explicit approved exception.
- Do not store the LiteLLM master key in `values.yaml`, `config.yaml`, shell history, or Git.
- Do not use Azure AI API keys while Workload Identity is available.
- Do not expose the ClusterIP service through public HTTP.
- Do not claim identity validation based only on pod readiness; inspect the federated identity and execute a real model request.
