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
3. For **Redirect URI**, select **Public client/native** and enter:

   ```text
   http://localhost
   ```

4. Open **Authentication** and confirm **Allow public client flows** is
   enabled.
5. Open **API permissions** > **Add a permission** >
   **My APIs**.
6. Select `litellm-foundry-middleware-api`.
7. Select **Delegated permissions** > `access_as_user`, then add the
   permission.
8. Return to the middleware registration's **Expose an API** page.
9. Under **Authorized client applications**, add the CLI application's client
   ID and select the middleware `access_as_user` scope.

The CLI is a public client and must not have a client secret. It uses device
code or authorization code with PKCE for interactive sign-in.

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
