# Architecture

## High-Level Architecture

```mermaid
flowchart TD
    Client[Demo client or agent]
    PortForward[kubectl port-forward]
    Gateway[LiteLLM AI Gateway on AKS]
    Entra[Microsoft Entra ID]
    Model[o4-mini in Agent365-Teams-Agents]
    Monitor[Azure Monitor and Log Analytics]

    Client -->|OpenAI-compatible request<br/>model: customer-chat| PortForward
    PortForward --> Gateway
    Gateway -->|Projected service-account token| Entra
    Entra -->|Short-lived access token| Gateway
    Gateway -->|Azure OpenAI request| Model
    Gateway --> Monitor
```

The first deployment intentionally has no public gateway endpoint. Customer-facing HTTPS ingress is added only after DNS and certificate ownership are known.

## Azure Infrastructure

```mermaid
flowchart TB
    subgraph Azure["MultiCloudTeam / East US 2"]
        subgraph RG["rg-litellm-gateway-demo-eus2"]
            subgraph VNet["VNet 10.40.0.0/16"]
                AKSSubnet["AKS subnet 10.40.0.0/22"]
                PESubnet["Future private endpoint subnet 10.40.4.0/24"]
                AKS["AKS<br/>2 x Standard_D4as_v6<br/>non-zonal"]
                AKSSubnet --> AKS
            end
            Identity[LiteLLM workload identity]
            LAW[(Log Analytics)]
        end
        ExistingAI["Existing Agent365-Teams-Agents<br/>o4-mini"]
    end

    AKS --> LAW
    AKS --> Identity
    Identity --> ExistingAI
```

## Request Flow

```mermaid
sequenceDiagram
    participant Client
    participant LiteLLM
    participant Entra as Microsoft Entra ID
    participant AzureAI as Azure AI Services

    Client->>LiteLLM: POST /v1/chat/completions<br/>model=customer-chat
    LiteLLM->>Entra: Exchange projected workload token
    Entra-->>LiteLLM: Azure AI access token
    LiteLLM->>AzureAI: Invoke deployment o4-mini
    AzureAI-->>LiteLLM: Model response
    LiteLLM-->>Client: OpenAI-compatible response
```

## Identity Flow

```mermaid
flowchart LR
    Pod[LiteLLM pod<br/>azure.workload.identity/use=true]
    SA[Kubernetes service account<br/>litellm/litellm]
    OIDC[AKS OIDC issuer]
    FIC[Federated identity credential]
    UAMI[User-assigned managed identity]
    RBAC[Cognitive Services OpenAI User]
    AI[Azure AI account]

    Pod --> SA --> OIDC --> FIC --> UAMI --> RBAC --> AI
```

## Model Routing

```mermaid
flowchart LR
    App[Application]
    Alias["Logical alias: customer-chat"]
    Gateway[LiteLLM router]
    Physical["Physical deployment: o4-mini"]

    App --> Alias --> Gateway --> Physical
```

The client does not receive or need the Azure deployment name.

## Observability

```mermaid
flowchart LR
    Gateway[LiteLLM]
    ContainerLogs[Container stdout/stderr]
    AKSLogs[AKS platform logs]
    LAW[(Log Analytics)]
    FutureOTel[Future OpenTelemetry pipeline]

    Gateway --> ContainerLogs --> LAW
    AKSLogs --> LAW
    Gateway -. later .-> FutureOTel
```

Phase 1 enables the AKS monitoring baseline. LiteLLM-specific metrics and OpenTelemetry integration are introduced only after their current supported configuration is validated.

## Network Boundaries

```mermaid
flowchart TB
    Local[Authorized operator workstation]
    APIServer[Public AKS API server<br/>Entra ID + Azure RBAC]
    ClusterIP[LiteLLM ClusterIP]
    AKS[AKS node and pod network]
    AzureAI[Public Azure AI endpoint<br/>Entra authentication]
    FuturePrivate[Future private endpoints]

    Local -->|kubectl over TLS| APIServer
    Local -->|port-forward tunnel| ClusterIP
    ClusterIP --> AKS
    AKS -->|HTTPS| AzureAI
    AKS -. Phase 12 .-> FuturePrivate
```

The public AKS API server is a Day-0 simplification, not an anonymous endpoint. Kubernetes local accounts are disabled and access requires Microsoft Entra ID plus Azure RBAC.
