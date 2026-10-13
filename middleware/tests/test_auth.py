import base64
import time
from typing import Any

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from foundry_middleware.auth import EntraTokenValidator, TokenValidationError
from foundry_middleware.config import Settings

TENANT_ID = "22222222-2222-2222-2222-222222222222"
CLIENT_ID = "33333333-3333-3333-3333-333333333333"
USER_ID = "11111111-1111-1111-1111-111111111111"
KEY_ID = "test-key"


def base64url_uint(value: int) -> str:
    width = (value.bit_length() + 7) // 8
    return base64.urlsafe_b64encode(value.to_bytes(width, "big")).rstrip(b"=").decode()


def make_signing_material() -> tuple[rsa.RSAPrivateKey, dict[str, str]]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_numbers = private_key.public_key().public_numbers()
    jwk = {
        "kty": "RSA",
        "use": "sig",
        "kid": KEY_ID,
        "alg": "RS256",
        "n": base64url_uint(public_numbers.n),
        "e": base64url_uint(public_numbers.e),
    }
    return private_key, jwk


def make_settings() -> Settings:
    return Settings(
        tenant_id=TENANT_ID,
        client_id=CLIENT_ID,
        client_secret="synthetic-test-value",
        downstream_scope="api://gateway/access_as_user",
        foundry_responses_endpoint=(
            "https://example.services.ai.azure.com/api/projects/project/agents/agent/"
            "endpoint/protocols/openai/responses?api-version=v1"
        ),
    )


def issue_token(
    private_key: rsa.RSAPrivateKey,
    *,
    scopes: str = "access_as_user",
    audience: str = CLIENT_ID,
    tenant_id: str = TENANT_ID,
) -> str:
    now = int(time.time())
    claims: dict[str, Any] = {
        "aud": audience,
        "exp": now + 3600,
        "iat": now,
        "iss": f"https://login.microsoftonline.com/{TENANT_ID}/v2.0",
        "nbf": now,
        "oid": USER_ID,
        "scp": scopes,
        "sub": "user-subject",
        "tid": tenant_id,
    }
    return jwt.encode(
        claims,
        private_key,
        algorithm="RS256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def make_http_client(settings: Settings, jwk: dict[str, str]) -> httpx.AsyncClient:
    jwks_uri = "https://login.microsoftonline.com/test/discovery/v2.0/keys"

    def handler(request: httpx.Request) -> httpx.Response:
        if str(request.url) == settings.openid_configuration_url:
            return httpx.Response(200, json={"jwks_uri": jwks_uri})
        if str(request.url) == jwks_uri:
            return httpx.Response(200, json={"keys": [jwk]})
        return httpx.Response(404)

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_valid_v2_access_token_returns_trusted_user_identity() -> None:
    settings = make_settings()
    private_key, jwk = make_signing_material()
    async with make_http_client(settings, jwk) as http_client:
        identity = await EntraTokenValidator(settings, http_client).validate(
            issue_token(private_key)
        )

    assert identity.object_id == USER_ID
    assert identity.tenant_id == TENANT_ID
    assert identity.subject == "user-subject"


@pytest.mark.parametrize(
    ("token_overrides", "expected_message"),
    [
        ({"scopes": "other_scope"}, "required delegated scope"),
        ({"audience": "44444444-4444-4444-4444-444444444444"}, "validation failed"),
        ({"tenant_id": "55555555-5555-5555-5555-555555555555"}, "tenant is not allowed"),
    ],
)
async def test_invalid_token_boundaries_are_rejected(
    token_overrides: dict[str, str],
    expected_message: str,
) -> None:
    settings = make_settings()
    private_key, jwk = make_signing_material()
    async with make_http_client(settings, jwk) as http_client:
        validator = EntraTokenValidator(settings, http_client)
        with pytest.raises(TokenValidationError, match=expected_message):
            await validator.validate(issue_token(private_key, **token_overrides))
