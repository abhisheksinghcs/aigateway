# Foundry OBO Middleware

This FastAPI service is the trusted application backend in Microsoft's
[application-managed OBO flow](https://learn.microsoft.com/azure/foundry/agents/how-to/use-on-behalf-of-flow#understand-the-delegated-access-flow).
It does not create or configure Microsoft Entra applications.

## What Customers Deploy

This directory is a reusable middleware package, not a set of Python files that
each customer recreates for every hosted agent. We build the production modules
into one container image and deploy it with the manifests under `k8s/`.

Customers supply their tenant-specific Entra registrations, delegated scopes,
confidential OBO credential, AKS workload identity, Foundry endpoint and
permissions, container image, and secret values. The separate hosted-agent code
reads the forwarded delegated token and calls LiteLLM with an internally stored
restricted virtual key; it does not contain or duplicate this FastAPI service.

See `../docs/foundry-middleware.md` for the complete component ownership model,
per-customer configuration checklist, and deployment sequence.

## Request Flow

```text
CLI
  | middleware-audience user token
  v
FastAPI middleware
  | validate signature, issuer, audience, lifetime, tenant, scope, oid
  | exchange the same assertion for the LiteLLM delegated scope
  | acquire a separate Foundry workload token
  v
Foundry hosted agent
  | forwarded x-client-litellm-user-token
  v
LiteLLM
```

The public API is deliberately narrow:

```http
POST /v1/responses
Authorization: Bearer <middleware-audience-user-token>
Content-Type: application/json

{
  "input": "Ask DeepWiki a question.",
  "stream": false,
  "background": false,
  "store": false
}
```

Unknown fields, streaming, background execution, and stored responses are
rejected. This prevents the service from becoming a general-purpose proxy.

## Code Walkthrough

### 1. Configuration

`src/foundry_middleware/config.py` loads runtime configuration with the
`MIDDLEWARE_` prefix. The client secret is represented as `SecretStr`.
For Microsoft Entra v2 access tokens, the default expected audience is the
middleware application's client ID.

The service fails during startup if required values are missing. No placeholder
configuration silently enables authentication.

#### Pydantic Field Validators

`field_validator` is a Pydantic hook that checks or transforms selected fields
while `Settings` is being created. `normalize_identifier` lowercases tenant and
client IDs so comparisons are consistent. `reject_blank_value` prevents a
scope containing only whitespace from passing startup validation.

`Field(...)` handles declarative constraints such as string length and numeric
ranges. `field_validator` is used when the rule requires custom Python logic.

#### Cached Properties

`cached_property` makes a method available through property syntax and stores
the value after its first evaluation. It is used for values derived from the
immutable startup configuration:

- Expected token audience
- Tenant authority
- Token issuer
- OpenID configuration URL

For example, `settings.authority` is calculated from `tenant_id` once and then
reused. These calculations are inexpensive and could also use `property`;
`cached_property` is safe because the service treats settings as immutable
after startup. Mutating `tenant_id` after first access would leave the cached
derived values stale and is therefore unsupported.

#### Why OpenID Metadata Is Used

The client sends an OAuth access token, not an OpenID ID token. The middleware
uses Microsoft Entra's OpenID Connect discovery document as the authoritative
source for token-validation metadata:

```text
https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration
```

The document identifies the expected issuer and the `jwks_uri` containing
Entra's current public signing keys. The middleware follows that URI and uses
the matching public key to validate the access token's signature. Discovery
avoids hard-coding keys that Microsoft rotates.

OAuth performs authorization and the OBO exchange. OpenID Connect supplies the
standard discovery and signing-key metadata used to validate the OAuth access
token.

### 2. Incoming Token Validation

`src/foundry_middleware/auth.py`:

1. Reads only the untrusted JWT header to select a signing key.
2. Requires the `RS256` algorithm and a key ID.
3. Downloads tenant-specific OpenID metadata and signing keys.
4. Validates signature, issuer, audience, lifetime, and required claims.
5. Requires the configured delegated scope.
6. Returns the validated `oid`; it never trusts a caller-supplied
   `x-ms-user-identity`.

Signing keys are cached and refreshed when they expire or an unknown key ID is
encountered.

The cache uses `time.monotonic()`, an elapsed-time clock that only moves
forward and is unaffected by time-zone changes or operating-system clock
corrections. The code stores an expiration point as the current monotonic value
plus the configured cache duration, then compares future monotonic values
against it.

An unfamiliar `kid` can indicate legitimate Entra key rotation, so it can
trigger an early refresh before normal cache expiration. Because `kid` comes
from an untrusted header, those early refreshes have a short cooldown to prevent
arbitrary key IDs from causing one Entra metadata request per caller request.

The JWT header check requires both an approved signing algorithm and a
string-valued key ID:

```python
if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str):
    raise TokenValidationError("Access token signing header is unsupported.")
```

`header.get("kid")` retrieves the key identifier from the untrusted JWT header.
`isinstance(..., str)` returns `True` only when that value is a string.
`not isinstance(...)` therefore detects a missing `kid` (`None`) or a malformed
non-string value. The middleware rejects those tokens before using `kid` to
look up a public signing key.

This check does not prove the token is authentic. It only validates the shape
of the untrusted header. Authenticity is established later when PyJWT verifies
the signature with the selected Entra public key.

### 3. OBO Exchange

`src/foundry_middleware/obo.py` uses MSAL's
`acquire_token_on_behalf_of`. The incoming validated access token becomes the
user assertion, and the only requested downstream permission is
`MIDDLEWARE_DOWNSTREAM_SCOPE`.

The exchange returns a new user token with the LiteLLM API as its audience. It
does not turn the user token into an application-only token.

The confidential client secret is read at runtime from
`MIDDLEWARE_CLIENT_SECRET`. For AKS, that value will come from a Kubernetes
Secret that we create manually after the Entra registration is ready.

### 4. Foundry Workload Authentication

`src/foundry_middleware/foundry.py` uses `DefaultAzureCredential` to acquire:

```text
https://ai.azure.com/.default
```

In AKS, `DefaultAzureCredential` selects Azure Workload Identity. This token
authenticates the middleware itself to Foundry and is separate from the
delegated LiteLLM token.

### 5. Foundry Invocation

`FoundryClient` sends:

```http
Authorization: Bearer <Foundry-workload-token>
x-client-litellm-user-token: <delegated-LiteLLM-token>
x-ms-user-identity: <validated-user-object-id>
```

The Foundry URL is fixed by configuration. Neither the user nor model can
select a destination for either token.

### 6. HTTP API

`src/foundry_middleware/app.py` composes the preceding components and exposes:

- `GET /healthz`
- `GET /readyz`
- `POST /v1/responses`

Dependencies are represented by protocols and injected through `Services`.
Tests therefore verify header and token flow without calling Entra or Foundry.

## Local Validation

```bash
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/pytest
.venv/bin/ruff check .
.venv/bin/ruff format --check .
```

The unit tests use synthetic RSA keys and tokens. They do not use tenant
credentials.

## Kubernetes Packaging

The `k8s/` directory contains non-deployable placeholders for:

- A two-replica, non-root Deployment.
- A ClusterIP Service.
- A ConfigMap for non-secret identifiers and endpoints.
- A placeholder Secret for the OBO client secret.
- A workload-identity ServiceAccount for Foundry invocation.

Do not apply these manifests until we have manually completed and verified:

1. The middleware API registration and delegated scope.
2. The CLI public-client registration.
3. The middleware confidential-client credential.
4. The AKS user-assigned identity and federated credential.
5. Foundry Agent Consumer and user-identity impersonation permissions.
6. The deployed hosted-agent Responses endpoint.
7. A real container image in an accessible registry.
