# Security Model

## Trust Boundaries

### Client Authentication

The client authenticates to LiteLLM. The initial administrative credential is a randomly generated LiteLLM master key stored only as a Kubernetes Secret. It is never committed to Git.

Virtual keys replace use of the master key by demo applications after PostgreSQL is introduced.

For the proposed Agent 365 MCP guardrail, the delegated user Entra token and LiteLLM virtual key serve different purposes. The user token supplies the signed-in user context for the OBO evaluation. The virtual key grants access to the selected MCP server. See [Microsoft Agent 365 MCP Guardrail Guide](agent365-mcp-guardrail.md).

Environment-credential login to the Admin UI is disabled after two database-backed `proxy_admin` users with passwords were verified and a personal administrator login succeeded. The master key remains available for authenticated management API recovery but is rejected by the UI login form.

### Copilot Studio OAuth Identity

The POC permits the existing gateway Entra application to act as both the
Copilot Studio OAuth client and the LiteLLM resource API. Copilot Studio must
use a dedicated client-secret credential on that registration; it must not
reuse the Agent 365/OBO secret stored in Kubernetes.

Production should use a separate Copilot Studio client registration with
delegated `access_as_user` permission to the gateway API. This isolates Power
Platform redirect URIs, credentials, consent, audit events, and credential
rotation from LiteLLM's confidential OBO identity.

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
| Gateway exposure | Trusted HTTPS ingress exposes only `/mcp`; `/ui` and `/v1` return ingress-level 404 responses |
| Gateway credential | Random master key in a Kubernetes Secret |
| POC database credentials | Random PostgreSQL passwords in Kubernetes Secrets and Helm release state |
| Model authorization | Least-privilege Azure RBAC assignment |
| Telemetry | Log Analytics baseline; secrets and authorization headers must not be logged |
| Source control | No keys, passwords, kubeconfigs, or connection strings |

## Known Phase 1 Tradeoffs

- The AKS API server is public, but it requires Microsoft Entra ID and Azure RBAC.
- The Azure AI endpoint remains public and is protected by Microsoft Entra authentication.
- The LiteLLM master key and bundled PostgreSQL credentials are Kubernetes Secrets for this POC because inherited policy makes a new Key Vault private-only. Helm also retains the database values in its release Secret. Key Vault and managed PostgreSQL are required before treating this as a production design.
- One LiteLLM replica proves the path but is not highly available.
- AKS Free tier has no financially backed control-plane uptime SLA.

## Deferred Hardening

- Private Key Vault endpoint and Secrets Store CSI integration
- Customer-owned production DNS and certificate to replace the temporary Azure-managed `cloudapp.azure.com` hostname
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
- Do not expose the LiteLLM service directly or bypass the authenticated HTTPS ingress.
- Do not claim identity validation based only on pod readiness; inspect the federated identity and execute a real model request.
- Do not reuse the Agent 365 application client secret that was exposed during design discussion. Revoke it before rollout.
- Do not store the replacement Agent 365 client secret in Git, LiteLLM configuration, Helm values, Helm command-line values, logs, or documentation.
