# ROLE

Act as a senior Azure Cloud Architect, Kubernetes Platform Engineer, AI Platform Engineer, and Security Architect.

Help me design and deploy LiteLLM on Azure Kubernetes Service (AKS) as an enterprise-style AI Gateway.

This environment is primarily for CUSTOMER DEMONSTRATIONS, technical workshops, architecture discussions, and experimentation with advanced enterprise AI use cases.

I want this to be more than "LiteLLM running in Kubernetes."

I want a reusable AI Gateway lab that demonstrates:

- centralized model access
- model abstraction
- multi-model routing
- authentication and authorization
- virtual keys
- rate limiting
- quotas
- model fallback
- load balancing
- usage tracking
- cost tracking
- logging
- observability
- guardrails
- security controls
- secrets management
- enterprise networking
- multiple AI model providers

IMPORTANT:

Do NOT immediately deploy anything.

First inspect my environment, design the architecture, explain the design, create the necessary files, and then walk through deployment incrementally.

Before running commands that CREATE, MODIFY, or DELETE Azure resources, show me the command and explain what it will change.

Never run destructive Azure commands without my explicit approval.


# HIGH-LEVEL ARCHITECTURE

The architecture should conceptually look like this:


                 CUSTOMER DEMO APPLICATIONS
                          
                Agents / Apps / Scripts
                         |
                         |
              OpenAI-compatible API
                         |
                         v

              +-----------------------+
              |                       |
              |       AI GATEWAY      |
              |                       |
              |       LiteLLM         |
              |                       |
              |       Azure AKS       |
              |                       |
              +----------+------------+
                         |
                         |
             +-----------+-----------+
             |           |           |
             v           v           v

       Azure OpenAI   Azure AI     External
          Models      Foundry      Providers
                       Models

             |           |           |
             +-----------+-----------+
                         |
                   AI MODEL LAYER


The basic request flow should be:

Application / Agent
        |
        | OpenAI-compatible request
        v
     LiteLLM
        |
        | routing / policy
        v
     AI Model
        |
        v
     LiteLLM
        |
        v
Application / Agent


# ENTERPRISE ARCHITECTURE

Design the larger environment conceptually like this:


 +---------------------------------------------------------------+
 |                         AZURE                                 |
 |                                                               |
 |   +-------------------------------------------------------+   |
 |   |                       VNET                            |   |
 |   |                                                       |   |
 |   |        +-------------------------------------+        |   |
 |   |        |              AKS                    |        |   |
 |   |        |                                     |        |   |
 | Client --->| Ingress ---> LiteLLM Pods           |        |   |
 |   |        |                    |                |        |   |
 |   |        +--------------------|----------------+        |   |
 |   |                             |                         |   |
 |   |             +---------------+---------------+         |   |
 |   |             |               |               |         |   |
 |   |             v               v               v         |   |
 |   |        PostgreSQL         Redis         Key Vault      |   |
 |   |                                                       |   |
 |   +-------------------------------------------------------+   |
 |                         |                                     |
 |                    Azure Monitor                              |
 |                    Log Analytics                              |
 |                         |                                     |
 +-------------------------|-------------------------------------+
                           |
                           |
                 +---------+----------+
                 |                    |
                 v                    v
           Azure OpenAI         Azure AI Foundry
              Models                Models

Additional external model providers should be possible later.


# DEPLOYMENT PLATFORM

Use:

Azure Kubernetes Service (AKS)

Deploy LiteLLM using the current official/recommended LiteLLM Helm deployment pattern when applicable.

Start with the simplest reasonable production-style LiteLLM architecture.

Prefer the monolithic LiteLLM deployment initially.

Do NOT introduce a complicated microservices architecture unless there is a clear requirement.

Design the repository so we could evolve toward a more scalable architecture later.


# INFRASTRUCTURE AS CODE

Use Bicep for Azure infrastructure.

Use Helm for Kubernetes/LiteLLM deployment.

Do not manually create production resources through the Azure Portal unless there is no practical Infrastructure-as-Code alternative.

Target workflow should ideally become:

az login

        |
        v

Azure CLI / azd

        |
        v

Bicep deployment

        |
        +--------------------------+
        |                          |
        v                          v

Azure infrastructure          AKS cluster

                                   |
                                   v

                               Helm

                                   |
                                   v

                               LiteLLM


# AZURE COMPONENTS

Evaluate and provision only the components actually required.

Expected components may include:

- Azure Resource Group
- Azure Virtual Network
- AKS
- Azure Container Registry, if needed
- Azure Key Vault
- PostgreSQL
- Redis
- Azure Monitor
- Log Analytics
- Managed Identity
- Microsoft Entra Workload Identity
- Azure OpenAI / Azure AI Foundry connectivity
- ingress/load balancer
- private endpoints where appropriate
- private DNS where appropriate

Do NOT create infrastructure just because it appears in this list.

For each Azure resource, explain:

1. Why it exists.
2. Whether LiteLLM requires it or whether it is an architectural recommendation.
3. Approximate security implications.
4. Whether it materially increases cost.
5. Whether it can be omitted for the initial demo.


# LITELLM ARCHITECTURE

Initial architecture:

                    Load Balancer / Ingress
                             |
                             v
                 +-----------------------+
                 |                       |
                 |    LiteLLM Gateway    |
                 |                       |
                 |       AKS Pod(s)      |
                 |                       |
                 +-----------+-----------+
                             |
               +-------------+-------------+
               |                           |
               v                           v

          PostgreSQL                     Redis
          
     configuration                 routing/state
     users                         caching
     keys                          rate limiting
     usage/spend                   multi-instance state


Use current LiteLLM documentation to determine exactly when PostgreSQL and Redis are required.

Do not assume.


# IDENTITY AND SECRET MANAGEMENT

Prefer identity-based authentication wherever Azure and LiteLLM currently support it.

Desired pattern:


          LiteLLM Pod
               |
               |
       AKS Workload Identity
               |
               v
       Microsoft Entra ID
               |
               +------> Key Vault
               |
               +------> Azure AI resource
               |
               +------> other Azure resources


Avoid static credentials wherever possible.

NEVER hardcode:

- API keys
- passwords
- connection strings
- master keys
- client secrets
- database credentials

Never commit secrets to Git.

Use Azure Key Vault and Kubernetes secret integration using an appropriate supported design.

If LiteLLM requires a secret rather than identity-based authentication for a particular capability:

1. explain why
2. store it securely
3. explain how it reaches the LiteLLM container


# MODEL ARCHITECTURE

Initially configure ONE model only.

Example:

Application
     |
     | model="demo-model"
     v
 LiteLLM
     |
     v
Azure-hosted model


Do not start with ten models.

Prove one path works first.

Afterwards we will add multiple models.


# FUTURE MULTI-MODEL DEMO

Eventually I want something like:


                       LiteLLM

                          |
      +-------------------+-------------------+
      |                   |                   |
      v                   v                   v

   Fast Model        Reasoning Model      Specialty Model

      |                   |                   |
      v                   v                   v

 Azure-hosted         Azure-hosted        Other Provider
   model                model                model


Clients should ideally use logical model aliases rather than needing to understand the physical provider deployment.


# DEMO SCENARIO 01 - BASIC GATEWAY

Prove:

Client
   |
   v
LiteLLM
   |
   v
Azure-hosted model
   |
   v
LiteLLM
   |
   v
Client


Provide a curl command using an OpenAI-compatible API request.

The response must prove the path is actually working.

Do not assume successful deployment based only on Kubernetes pod status.


# DEMO SCENARIO 02 - MODEL ABSTRACTION

Demonstrate:

App

 |
 | model="customer-chat"
 v

LiteLLM

 |
 +-----------> Physical Model Deployment


The application should not need to know the provider-specific deployment details.


# DEMO SCENARIO 03 - MULTI-MODEL ROUTING

Demonstrate:

                        LiteLLM
                           |
              +------------+------------+
              |                         |
              v                         v
        general-model             reasoning-model
              |                         |
              v                         v
         Provider A                 Provider B


Explain why centralized model routing can be useful in enterprise architecture.


# DEMO SCENARIO 04 - FALLBACK

Demonstrate something conceptually like:


Application
    |
    v
LiteLLM
    |
    v
Primary Model
    |
   FAIL
    |
    v
Fallback Model
    |
    v
Application


Only implement this using documented LiteLLM capabilities.

Create a test that intentionally demonstrates the fallback behavior.


# DEMO SCENARIO 05 - LOAD BALANCING

Eventually demonstrate:


                       LiteLLM
                          |
                model="customer-chat"
                          |
                +---------+---------+
                |                   |
                v                   v
           Deployment A        Deployment B


Show how requests can be distributed appropriately according to supported LiteLLM functionality.


# DEMO SCENARIO 06 - VIRTUAL KEYS

Demonstrate clients receiving gateway credentials rather than direct model-provider credentials.


            Application A --------+
                                  |
            Application B --------+----> LiteLLM
                                  |
            Application C --------+
                                         |
                                         v
                                     AI Models


Demonstrate, if supported by the deployed LiteLLM edition/configuration:

- per-application identity
- model permissions
- budgets
- rate limits
- usage attribution

Verify each capability against current documentation before implementation.


# DEMO SCENARIO 07 - AI FINOPS

Create a demo showing how centralized gateway usage can provide visibility such as:

Application / Agent
       |
       v
    LiteLLM
       |
       +-------- Usage
       |
       +-------- Tokens
       |
       +-------- Model
       |
       +-------- Costs
       |
       +-------- Caller / virtual key
       |
       v
     Models


Clearly distinguish between:

- what LiteLLM provides
- what Azure provides
- what we calculate ourselves


# DEMO SCENARIO 08 - OBSERVABILITY

Design observability conceptually as:


Apps / Agents
     |
     v
  LiteLLM
     |
     +---------- Gateway telemetry
     |
     +---------- request metadata
     |
     +---------- errors
     |
     +---------- latency
     |
     +---------- usage
     |
     v
  AI Models

     |
     v

Azure Monitor / Log Analytics


Determine what telemetry LiteLLM exposes and how it can appropriately integrate with Azure observability.

Do not invent unsupported native integrations.

If OpenTelemetry is appropriate and supported, explain and use it.


# DEMO SCENARIO 09 - RATE LIMITING / QUOTAS

Demonstrate a scenario conceptually like:


                  LiteLLM
                     |
        +------------+------------+
        |            |            |
        v            v            v

     Agent A       Agent B       Agent C

     100 RPM        20 RPM       10 RPM


The actual values should be configurable and should be chosen for easy demonstration, not treated as production recommendations.


# DEMO SCENARIO 10 - GUARDRAILS

Eventually demonstrate:


User
 |
 v
Agent
 |
 v
LiteLLM
 |
 +-------- authentication
 |
 +-------- policy
 |
 +-------- guardrail
 |
 +-------- model routing
 |
 v
Model


Use only documented LiteLLM or integrated guardrail capabilities.

Clearly identify WHERE each security control executes.


# SECURITY MODEL

Treat this as an enterprise reference architecture even though this is a demo environment.

Follow these principles:

- least privilege
- Microsoft Entra identities
- managed identity/workload identity where supported
- Azure Key Vault
- Kubernetes RBAC
- Azure RBAC
- HTTPS
- network segmentation
- no credentials committed to Git
- centralized logging
- secure container configuration
- secrets separation
- separate gateway authentication from model-provider authentication

Always explain the trust boundary.

Distinguish:

CLIENT AUTHENTICATION

Client
  |
  | credential
  v
LiteLLM


from:

DOWNSTREAM AUTHENTICATION

LiteLLM
  |
  | Azure identity / provider credential
  v
Model Provider


These are DIFFERENT authentication boundaries.


# NETWORK ARCHITECTURE

Start reasonably simple but make the design capable of evolving toward:


Internet / Demo Client
          |
          v
        HTTPS
          |
          v
   Load Balancer / Ingress
          |
          v
     LiteLLM AKS
          |
     +----+----------------+
     |                     |
     v                     v
Private Azure          External provider
AI endpoint             endpoint
     |
Private Endpoint


Do not make everything private during the first deployment if that makes troubleshooting unnecessarily difficult.

Instead:

PHASE 1 = make it work securely.

PHASE 2 = harden networking.

PHASE 3 = demonstrate enterprise private networking.


# REPOSITORY STRUCTURE

Create a clean repository similar to:


litellm-ai-gateway/
|
+-- README.md
|
+-- infra/
|   |
|   +-- main.bicep
|   +-- parameters.bicepparam
|   |
|   +-- modules/
|       |
|       +-- aks.bicep
|       +-- network.bicep
|       +-- identity.bicep
|       +-- keyvault.bicep
|       +-- monitoring.bicep
|       +-- postgres.bicep
|       +-- redis.bicep
|
+-- kubernetes/
|   |
|   +-- namespace.yaml
|   +-- values.yaml
|   +-- secrets-config/
|
+-- litellm/
|   |
|   +-- config.yaml
|
+-- scripts/
|   |
|   +-- prerequisites.sh
|   +-- deploy-infra.sh
|   +-- deploy-litellm.sh
|   +-- test-gateway.sh
|   +-- status.sh
|   +-- destroy.sh
|
+-- demos/
|   |
|   +-- 01-basic-gateway/
|   +-- 02-model-alias/
|   +-- 03-multi-model/
|   +-- 04-fallback/
|   +-- 05-load-balancing/
|   +-- 06-virtual-keys/
|   +-- 07-finops/
|   +-- 08-observability/
|   +-- 09-rate-limits/
|   +-- 10-guardrails/
|
+-- docs/
|   |
|   +-- architecture.md
|   +-- security.md
|   +-- networking.md
|   +-- operations.md
|   +-- demo-guide.md
|
+-- .gitignore


Modify this structure if the actual implementation requires it.

Avoid unnecessary files.


# ARCHITECTURE DOCUMENTATION

Create:

docs/architecture.md

Use Mermaid diagrams so GitHub renders the architecture visually.

Include diagrams for:

1. High-level architecture
2. Azure infrastructure
3. Request flow
4. Identity flow
5. Model routing
6. Observability
7. Network boundaries


Example Mermaid style:


flowchart TD

    Client[Demo Client / Agent]
        --> Gateway[LiteLLM AI Gateway]

    Gateway --> AOAI[Azure-hosted Model]
    Gateway --> Other[External Model Provider]

    Gateway --> PG[(PostgreSQL)]
    Gateway --> Redis[(Redis)]
    Gateway --> KV[Azure Key Vault]

    Gateway --> Monitor[Azure Monitor]


Improve this diagram based on the actual architecture.


# CUSTOMER DEMO GUIDE

Create:

docs/demo-guide.md

For EACH demo scenario include:

## Business Problem

Explain the customer problem.

## Architecture Concept

Explain what we're demonstrating.

## Configuration

Show the relevant configuration.

## Test

Provide an exact command that exercises it.

## Expected Result

Describe exactly what success looks like.

## Evidence

Explain how to prove that the gateway performed the operation.

## Customer Talking Points

Give me 3-5 concise customer-facing talking points.


# IMPORTANT POSITIONING

Do NOT describe LiteLLM as replacing:

- Azure AI Foundry
- Microsoft Entra
- Azure API Management
- Microsoft security products
- Agent 365

Treat LiteLLM specifically as the AI Gateway component in this lab.

When capabilities overlap with another platform, document the architectural distinction rather than claiming one replaces another.


# COST CONSIDERATIONS

This is MY DEMO TENANT.

Cost matters.

Do not automatically deploy expensive production SKUs.

For every significant resource tell me:

- what SKU you propose
- why
- whether a cheaper demo-compatible option exists
- what capability I lose by choosing the cheaper option

Prefer low-cost settings initially where they still allow the demo scenario to work.

Do not sacrifice the architecture just to minimize every dollar, but avoid unnecessarily expensive defaults.


# VALIDATION RULE

VERY IMPORTANT:

Never tell me something "works" merely because:

kubectl get pods

returns Running.

For every feature create an actual functional test.

Examples:

Gateway:
Send a real inference request.

Routing:
Demonstrate which model received the request.

Fallback:
Cause the primary route to fail and demonstrate secondary routing.

Rate limits:
Generate enough requests to trigger the configured limit.

Virtual keys:
Demonstrate allowed and denied behavior.

Observability:
Generate traffic and query the resulting telemetry.

Identity:
Show which identity is making the downstream request.


# DOCUMENTATION REQUIREMENT

For LiteLLM implementation details:

Prefer current official LiteLLM documentation.

For Azure implementation details:

Prefer current official Microsoft documentation.

For Kubernetes implementation:

Prefer official Kubernetes, AKS, and Helm documentation.

DO NOT invent configuration properties.

DO NOT assume a feature still works the same way as an older LiteLLM release.

If documentation and examples conflict, stop and highlight the discrepancy.


# WORKING STYLE

I want to understand the architecture while we build it.

Work incrementally.

Do not generate 50 files and start deploying.

For every major step:

1. Explain WHAT we are doing.
2. Explain WHY.
3. Show relevant architecture.
4. Show configuration/code.
5. Show the command.
6. Execute only when appropriate.
7. Validate what happened.
8. Explain the result.
9. Commit logical milestones when appropriate.

When a command fails:

DO NOT blindly try random fixes.

First:

1. inspect the error
2. explain the likely cause
3. inspect relevant state/configuration
4. propose the smallest correction
5. retry only after understanding the issue


# PHASED IMPLEMENTATION

Follow this sequence.


PHASE 0
Environment discovery

        |
        v

PHASE 1
AKS + minimal infrastructure

        |
        v

PHASE 2
LiteLLM deployment

        |
        v

PHASE 3
One Azure-hosted model

        |
        v

PHASE 4
End-to-end gateway test

        |
        v

PHASE 5
Identity + secrets hardening

        |
        v

PHASE 6
PostgreSQL / Redis capabilities

        |
        v

PHASE 7
Multiple models

        |
        v

PHASE 8
Routing + fallback

        |
        v

PHASE 9
Virtual keys / quotas / FinOps

        |
        v

PHASE 10
Observability

        |
        v

PHASE 11
Guardrails

        |
        v

PHASE 12
Private networking / enterprise hardening


# PHASE 0 - START HERE

DO NOT DEPLOY ANYTHING YET.

First inspect the repository.

Then help me inspect my local environment.

Check tools such as:

az --version
az account show
az account list
kubectl version --client
helm version
git --version


Do not expose access tokens or secrets in terminal output unnecessarily.

Then determine:

- active Azure subscription
- tenant
- Azure CLI state
- whether kubectl exists
- whether Helm exists
- whether Bicep is available
- existing repository contents

DO NOT CHANGE MY AZURE TENANT DURING THIS PHASE.


# YOUR FIRST RESPONSE

Do NOT start implementing yet.

Respond with ONLY:

1. Your understanding of what we are building.

2. Proposed architecture.

3. An ASCII architecture diagram.

4. Azure resources you expect will eventually be required.

5. Which resources are needed immediately versus later.

6. Proposed repository structure.

7. Security model.

8. Proposed implementation phases.

9. Phase 0 environment inspection commands.

10. Any assumptions you are making.

Then STOP.

Wait for me to provide the results of the environment inspection before moving to Phase 1.