import asyncio
import time
from dataclasses import dataclass
from typing import Any

import httpx
import jwt
from jwt import InvalidTokenError, PyJWK

from .config import Settings


class TokenValidationError(Exception):
    """A caller token could not be proven valid for this middleware."""

    pass


@dataclass(frozen=True)
class UserIdentity:
    """Identity claims that are trusted only after full JWT validation."""

    object_id: str
    tenant_id: str
    subject: str


class EntraTokenValidator:
    """Validate middleware-audience access tokens with tenant-specific Entra keys."""

    def __init__(self, settings: Settings, http_client: httpx.AsyncClient) -> None:
        self._settings = settings
        self._http_client = http_client
        self._keys: dict[str, PyJWK] = {}
        self._keys_expire_at = 0.0
        self._refresh_lock = asyncio.Lock()

    async def validate(self, token: str) -> UserIdentity:
        # The header is untrusted. Decode only enough to select a candidate public key;
        # jwt.decode below performs the cryptographic and claim validation.
        try:
            header = jwt.get_unverified_header(token)
        except InvalidTokenError as exc:
            raise TokenValidationError("Access token header is invalid.") from exc

        # Pin the algorithm to prevent algorithm-confusion attacks. Entra key IDs are
        # strings; a missing or malformed kid cannot safely select a JWKS key.
        if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str):
            raise TokenValidationError("Access token signing header is unsupported.")

        key = await self._get_key(header["kid"])
        try:
            # This is the trust boundary: signature, issuer, audience, lifetime, and
            # required standard claims must all validate before claims are consumed.
            claims: dict[str, Any] = jwt.decode(
                token,
                key=key.key,
                algorithms=["RS256"],
                audience=self._settings.expected_audience,
                issuer=self._settings.issuer,
                leeway=self._settings.clock_skew_seconds,
                options={
                    "require": ["aud", "exp", "iat", "iss", "nbf", "sub", "tid"],
                },
            )
        except InvalidTokenError as exc:
            raise TokenValidationError("Access token validation failed.") from exc

        tenant_id = claims.get("tid")
        object_id = claims.get("oid")
        subject = claims.get("sub")
        scopes = set(str(claims.get("scp", "")).split())

        # Signature validation alone is insufficient. Bind the token to this tenant,
        # require a user identity, and enforce the delegated API permission.
        if tenant_id != self._settings.tenant_id:
            raise TokenValidationError("Access token tenant is not allowed.")
        if not isinstance(object_id, str) or not object_id:
            raise TokenValidationError("Access token does not contain a user object ID.")
        if not isinstance(subject, str) or not subject:
            raise TokenValidationError("Access token does not contain a subject.")
        if self._settings.required_scope not in scopes:
            raise TokenValidationError("Access token is missing the required delegated scope.")

        return UserIdentity(object_id=object_id, tenant_id=tenant_id, subject=subject)

    async def _get_key(self, key_id: str) -> PyJWK:
        # Refresh on cache expiry and also when Entra rotates to an unfamiliar key ID.
        if time.monotonic() >= self._keys_expire_at or key_id not in self._keys:
            await self._refresh_keys()

        key = self._keys.get(key_id)
        if key is None:
            raise TokenValidationError("Access token signing key was not found.")
        return key

    async def _refresh_keys(self) -> None:
        # Only one concurrent request should refresh discovery metadata and JWKS.
        async with self._refresh_lock:
            if time.monotonic() < self._keys_expire_at and self._keys:
                return

            try:
                # Discovery keeps the signing-key endpoint tenant-specific and avoids
                # hard-coding keys that Microsoft rotates.
                metadata_response = await self._http_client.get(
                    self._settings.openid_configuration_url
                )
                metadata_response.raise_for_status()
                jwks_uri = metadata_response.json()["jwks_uri"]
                jwks_response = await self._http_client.get(jwks_uri)
                jwks_response.raise_for_status()
                raw_keys = jwks_response.json()["keys"]
                # Convert each public JWK into the PyJWT representation used later for
                # RSA signature verification.
                keys = {
                    raw_key["kid"]: PyJWK.from_dict(raw_key)
                    for raw_key in raw_keys
                    if isinstance(raw_key.get("kid"), str)
                }
            except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
                raise TokenValidationError("Unable to load token-signing metadata.") from exc

            if not keys:
                raise TokenValidationError("No token-signing keys are available.")

            self._keys = keys
            self._keys_expire_at = time.monotonic() + self._settings.jwks_cache_seconds
