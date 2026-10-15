# Foundry Hosted Agent Middleware

This POC can preserve LiteLLM virtual-key authorization and delegated Agent 365
user context by using a custom Foundry hosted agent and a trusted middleware
service. The middleware runs as a separate workload in the existing AKS
cluster.

## Why the Middleware Runs on AKS

The middleware can reuse the cluster's ingress, Workload Identity,
observability, and deployment controls. It remains a separate Deployment,
Service, service account, and identity from LiteLLM.

Co-location does not place the Foundry hosted agent inside the AKS network.
Foundry-managed compute still calls a routable HTTPS LiteLLM endpoint unless a
future private-network design is added.

## Authentication Flow

This follows Microsoft's
[application-managed OBO and token-forwarding flow](https://learn.microsoft.com/azure/foundry/agents/how-to/use-on-behalf-of-flow#understand-the-delegated-access-flow).
Foundry does not perform the OBO exchange. The AKS middleware is the trusted
application backend that authenticates the user, performs OBO, authenticates
separately to Foundry, and invokes the hosted agent.

For a visual introduction, see
[Foundry delegated access: concept-to-code diagrams](./foundry-obo-flow.md).
It maps each of Microsoft's six steps to the middleware and hosted-agent files,
then shows how data moves between the hosted-agent modules.

1. A public CLI client signs in a user and obtains a token for the middleware
   API's `access_as_user` scope.
2. The middleware validates the token's signature, issuer, audience, lifetime,
   and delegated scope.
3. The middleware exchanges the incoming assertion through OAuth on-behalf-of
   for the existing LiteLLM gateway `access_as_user` scope.
4. The middleware invokes the Foundry hosted agent with:
   - Its separate Foundry workload token in `Authorization`.
   - The delegated LiteLLM token in an `x-client-*` header.
   - The validated user's object ID in `x-ms-user-identity`.
5. Foundry forwards the `x-client-*` header, but not the caller's
   `Authorization` header, to the hosted-agent container.
6. Hosted-agent code calls LiteLLM with:

   ```http
   Authorization: Bearer <delegated-user-token>
   x-litellm-api-key: <deepwiki-only-virtual-key>
   ```

The virtual key authenticates and authorizes the LiteLLM request. The delegated
token supplies the user context required by the Agent 365 guardrail.

### Component Responsibilities

| Component | Responsibility |
| --- | --- |
| CLI or future UI | Interactively signs in the user and sends a middleware-audience access token. It never receives the LiteLLM virtual key. |
| AKS middleware | Validates the incoming token, performs OBO for the LiteLLM delegated scope, derives the user object ID from validated claims, acquires a separate Foundry workload token, and invokes Foundry. |
| Foundry | Authenticates the middleware workload identity, checks that it can represent the user, establishes per-user context, and forwards `x-client-*` headers to the hosted-agent container. |
| Foundry hosted agent | Reads the forwarded delegated token and calls only the configured LiteLLM endpoint with both the delegated token and an internally supplied LiteLLM key. |
| LiteLLM | Uses the virtual key for gateway authentication and authorization while making the delegated token available to the Agent 365 guardrail. |

The three values sent to Foundry are not interchangeable:

| Foundry request header | Value | Purpose |
| --- | --- | --- |
| `Authorization` | Foundry workload access token | Authenticates the middleware to Foundry. Foundry does not forward it to the hosted-agent container. |
| `x-client-litellm-user-token` | Delegated LiteLLM access token without a `Bearer` prefix | Carries the request-scoped downstream token to hosted-agent code. The `x-client-` prefix enables forwarding. |
| `x-ms-user-identity` | Object ID from the validated user context | Associates the Foundry request and conversation with the represented user. It is not a token and grants no downstream permission by itself. |

The middleware must never trust `x-ms-user-identity` or a downstream token
supplied directly by the client. It derives both from the validated incoming
identity and OBO result. Tokens remain request-scoped and must not be written to
prompts, model inputs, logs, exceptions, conversation history, or responses.

### Identity Separation

The middleware uses two identity mechanisms:

1. The `litellm-foundry-middleware-api` confidential application validates
   user-audience tokens and performs the delegated OBO exchange.
2. The AKS workload identity acquires the Foundry workload token. It requires
   **Foundry Agent Consumer** and the
   `Microsoft.CognitiveServices/accounts/AIServices/agents/endpoints/UserIdentityImpersonation/action`
   data action at the appropriate Foundry scope.

Keeping these identities separate prevents the OBO credential from also being
the Azure workload identity used to invoke Foundry.

## Customer Deployment Model

Customers do not recreate the middleware Python files for each hosted-agent
deployment. The files under `middleware/src/foundry_middleware/` are the
reusable trusted-service implementation:

| File | Reusable responsibility |
| --- | --- |
| `app.py` | Builds the FastAPI application and orchestrates validation, OBO, and Foundry invocation. |
| `auth.py` | Validates the incoming middleware-audience Entra access token. |
| `obo.py` | Exchanges the validated assertion for a LiteLLM-audience delegated token. |
| `foundry.py` | Acquires the separate Foundry workload token and invokes the fixed hosted-agent endpoint. |
| `config.py` | Loads and validates customer-specific runtime configuration. |
| `models.py` | Defines the intentionally narrow public request contract. |

These files are built once into the middleware container image using
`middleware/Dockerfile`. Customers deploy that image with the resources under
`middleware/k8s/`; they should modify the Python source only if their API or
identity requirements differ from the supported flow.

### Separate Deployable Components

The solution has three related but independently deployed components:

1. The client obtains a middleware-audience user token and calls the AKS
   middleware.
2. The reusable middleware container validates the user, performs OBO, and
   invokes Foundry.
3. The Foundry hosted agent receives the forwarded delegated token and calls
   LiteLLM.

The middleware source is not copied into the hosted-agent project. The
hosted-agent code has a smaller responsibility: read
`x-client-litellm-user-token`, obtain its internal DeepWiki-only LiteLLM
virtual key from a secret store, and call the fixed LiteLLM endpoint with both
values. It must never accept the virtual key from the caller or log either
credential.

### Per-Customer Configuration

Each customer supplies environment-specific resources and values rather than
rewriting the middleware:

1. Create the confidential middleware API registration, expose its delegated
   scope, and grant it the LiteLLM `access_as_user` delegated permission.
2. Create or configure the user-facing client registration and grant it the
   middleware's delegated scope. A CLI, web application, native application,
   and Copilot surface can require different client registration settings.
3. Create the AKS workload identity, Kubernetes service account, and federated
   credential used to invoke Foundry.
4. Grant that workload identity **Foundry Agent Consumer** and
   `Microsoft.CognitiveServices/accounts/AIServices/agents/endpoints/UserIdentityImpersonation/action`
   at the appropriate Foundry scope.
5. Deploy the hosted agent and provide its fixed Responses endpoint to the
   middleware.
6. Configure the tenant ID, middleware client ID, expected audience, delegated
   LiteLLM scope, Foundry endpoint, workload identity client ID, and deployable
   container image through the Kubernetes ConfigMap and Deployment.
7. Inject the OBO credential through a Kubernetes Secret. The current POC uses
   a client secret; production should evaluate a certificate or stronger
   credential strategy.
8. Store the hosted agent's restricted LiteLLM virtual key in its secret store,
   never in source, configuration committed to Git, prompts, or caller input.
9. Run end-to-end tests proving valid user admission, invalid issuer/audience
   rejection, OBO failure handling, Foundry invocation, and the guarded
   LiteLLM call.

The expected customer experience is therefore:

```text
Consume the deployment package
  -> create tenant-specific identities and permissions
  -> deploy/configure the Foundry hosted agent
  -> supply runtime configuration and secrets
  -> deploy the middleware image and Kubernetes manifests
  -> run end-to-end validation
```

Customers should not independently reimplement `auth.py` or `obo.py`. Keeping
the security-sensitive validation and exchange logic in the versioned
middleware package makes fixes, testing, and upgrades consistent across
deployments.

### Secret and `.env` Handling

No `.env` file is required for AKS. The repository includes
`middleware/.env.example` only as a local-development template, while
`middleware/.env` is intentionally absent and ignored by Git. Developers who
need local execution can copy the template to `.env`, restrict it to mode
`0600`, and populate it locally.

Do not replace `REPLACE_ME` in `middleware/k8s/secret.yaml`. That file is a
tracked, non-deployable shape declaration and must never contain a real
credential. Before deploying the middleware, run:

```bash
scripts/configure-foundry-middleware-secret.sh
```

The helper prompts without echoing the value and creates or updates the live
Kubernetes Secret `litellm/litellm-foundry-middleware-secret` with key
`MIDDLEWARE_CLIENT_SECRET`. The Deployment imports that key as an environment
variable through `envFrom`; [config.py](../middleware/src/foundry_middleware/config.py)
then loads it through the `MIDDLEWARE_` settings prefix.

## App Registration 1: Middleware API

Create this registration first.

1. In the Azure portal, open **Microsoft Entra ID** >
   **App registrations** > **New registration**.
2. Enter the name `litellm-foundry-middleware-api`.
3. Select **Accounts in this organizational directory only**.
4. Leave **Redirect URI** empty and select **Register**.
5. Record the **Application (client) ID**. It is not a secret.
6. Open **Expose an API** and set the Application ID URI to:

   ```text
   api://<middleware-application-id>
   ```

7. Add a scope with these values:

   | Field | Value |
   | --- | --- |
   | Scope name | `access_as_user` |
   | Who can consent | Admins and users |
   | Admin consent display name | `Access the Foundry middleware as a user` |
   | Admin consent description | `Allow the client to access the Foundry middleware as the signed-in user.` |
   | User consent display name | `Access the Foundry middleware as you` |
   | User consent description | `Allow this application to access the Foundry middleware on your behalf.` |
   | State | Enabled |

8. Open **Manifest** and set `requestedAccessTokenVersion` under `api` to `2`.
9. Open **API permissions** > **Add a permission** >
   **APIs my organization uses**.
10. Select the existing `litellm` application.
11. Select **Delegated permissions** > `access_as_user`, then add the
    permission.

This registration represents both the protected middleware API and the
confidential application that performs the OBO exchange. Do not create its
credential yet; credential design is a separate step.

## App Registration 2: CLI Client

1. Create another app registration named `litellm-foundry-cli-client`.
2. Select **Accounts in this organizational directory only**.
3. Leave **Redirect URI** empty during initial registration and select
   **Register**.
4. Open **Authentication** > **Add a platform**.
5. In the current Entra portal, under **Mobile and desktop applications**,
   select **Mobile and desktop applications**. This is the current portal name
   for the platform older instructions call **Public client/native**.
6. Under the custom redirect URI option, enter:

   ```text
   http://localhost
   ```

7. Select **Configure**.
8. On the **Authentication** page, under **Advanced settings**, set
   **Allow public client flows** to **Yes**, then select **Save**.
9. Open **API permissions** > **Add a permission** >
   **My APIs**.
10. Select `litellm-foundry-middleware-api`.
11. Select **Delegated permissions** > `access_as_user`, then add the
   permission.
12. Return to **App registrations** > **All applications** and open
   `litellm-foundry-middleware-api`. Confirm the page heading shows the
   middleware API, not `litellm-foundry-cli-client`.
13. In the middleware registration, open **Expose an API** and verify
   `access_as_user` appears under **Scopes defined by this API**. This scope
   was created during App Registration 1; do not create a scope on the CLI
   registration.
14. Still in the middleware registration, under
   **Authorized client applications**, select **Add a client application**.
15. Enter the CLI registration's **Application (client) ID**, select the
   middleware `access_as_user` scope, and authorize it.

The CLI is a public client and must not have a client secret. It uses device
code or authorization code with PKCE for interactive sign-in.

Microsoft's current redirect-URI guidance calls this platform
**Mobile and desktop applications**. Do not select **Web** or
**Single-page application** for this CLI registration; those represent
different client types and token-handling assumptions.

The CLI consumes the middleware API; it does not expose an API of its own.
Therefore, do not set an Application ID URI, add a scope, or add an authorized
client application on `litellm-foundry-cli-client`. The CLI's **Expose an API**
page can remain empty. If an Application ID URI was set accidentally, it does
not grant access or break this flow, but it should be removed from the CLI
registration's manifest by restoring `identifierUris` to an empty array after
review.

## Consent

Both custom scopes are configured for user consent. Tenant policy can still
require administrator approval. Grant tenant-wide admin consent only when the
customer wants all authorized users to avoid an interactive consent prompt.

Preauthorizing the CLI on the middleware scope prevents an extra consent prompt
for that first-party relationship. It does not grant the user access to
LiteLLM directly; the middleware performs the downstream OBO exchange.

## Reproducible Automation

The portal steps are automated by:

```bash
APPROVE_ENTRA_CHANGES=yes \
  scripts/configure-foundry-middleware-apps.sh
```

The script is idempotent by display name, creates both service principals,
configures both delegated permission relationships, preauthorizes the CLI, and
writes non-secret IDs to the ignored file:

```text
.azure/foundry-middleware-apps.env
```

The script intentionally requires explicit approval and does not run during
clone, prerequisite checks, or deployment. Creating tenant identities
automatically during repository download would be unsafe and would fail for
users without the required directory permissions.

The script does not create a secret, certificate, federated credential, Azure
role assignment, Kubernetes resource, or consent grant.

For this POC, the script is retained only as reproducible customer reference
material and must not be run. We will create and configure each Entra
registration together in the portal, record only non-secret identifiers, and
verify each setting before continuing. Middleware code and local tests will use
configuration placeholders until those manual steps are complete.
