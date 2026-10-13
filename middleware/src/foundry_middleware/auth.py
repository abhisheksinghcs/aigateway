"""Authenticate callers by validating Microsoft Entra access tokens.

This module retrieves and caches Entra signing keys, verifies each JWT's
signature and required claims, and returns only identity fields that are safe
for later authorization and OBO decisions.
"""

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
        self._unknown_key_refresh_after = 0.0
        self._refresh_lock = asyncio.Lock()

    async def validate(self, token: str) -> UserIdentity:
        # Stage 1: inspect the untrusted JWT header.
        #
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
            # Stage 2: authenticate the token and validate its standard JWT claims.
            #
            # This is the trust boundary: signature, issuer, audience, lifetime, and
            # required standard claims must all validate before claims are consumed.
            claims: dict[str, Any] = jwt.decode(
                token,
                # Verify the signature with the Entra public key selected by kid.
                key=key.key,
                # Never accept an algorithm chosen dynamically by the token.
                algorithms=["RS256"],
                # Ensure the token was issued for this middleware API.
                audience=self._settings.expected_audience,
                # Ensure the token came from this tenant's Entra v2 issuer.
                issuer=self._settings.issuer,
                # Permit only a small clock difference between systems.
                leeway=self._settings.clock_skew_seconds,
                options={
                    # Require audience, expiration, issue time, issuer, activation
                    # time, subject, and tenant claims. PyJWT also validates exp and
                    # nbf using the current time and configured leeway.
                    "require": ["aud", "exp", "iat", "iss", "nbf", "sub", "tid"],
                },
            )
        except InvalidTokenError as exc:
            raise TokenValidationError("Access token validation failed.") from exc

        # Stage 3: enforce application-specific identity and authorization rules.
        #
        # These claims are read only after PyJWT has authenticated the token.
        tenant_id = claims.get("tid")  # Tenant that issued the token.
        object_id = claims.get("oid")  # Stable Entra user object ID.
        subject = claims.get("sub")  # User subject scoped to this application.
        # scp is a space-delimited list of delegated permissions.
        scopes = set(str(claims.get("scp", "")).split())

        # Signature validation alone is insufficient. Bind the token to this tenant,
        # require a user identity, and enforce the delegated API permission.
        if tenant_id != self._settings.tenant_id:
            raise TokenValidationError("Access token tenant is not allowed.")
        # Foundry's x-ms-user-identity must come from a validated oid claim.
        if not isinstance(object_id, str) or not object_id:
            raise TokenValidationError("Access token does not contain a user object ID.")
        # A delegated user token must identify a subject, not only an application.
        if not isinstance(subject, str) or not subject:
            raise TokenValidationError("Access token does not contain a subject.")
        # Possessing a valid token is not enough; the caller must have access_as_user.
        if self._settings.required_scope not in scopes:
            raise TokenValidationError("Access token is missing the required delegated scope.")

        # Only validated values leave this class and become trusted request context.
        return UserIdentity(object_id=object_id, tenant_id=tenant_id, subject=subject)

    async def _get_key(self, key_id: str) -> PyJWK:
        # Refresh on cache expiry and also when Entra rotates to an unfamiliar key ID.
        if time.monotonic() >= self._keys_expire_at:
            await self._refresh_keys()
        elif key_id not in self._keys:
            await self._refresh_keys(required_key_id=key_id)

        key = self._keys.get(key_id)
        if key is None:
            raise TokenValidationError("Access token signing key was not found.")
        return key

    async def _refresh_keys(self, required_key_id: str | None = None) -> None:
        # Only one concurrent request should refresh discovery metadata and JWKS.
        async with self._refresh_lock:
            now = time.monotonic()
            cache_is_current = now < self._keys_expire_at and bool(self._keys)
            if cache_is_current:
                # Another request may have refreshed the required key while this
                # request waited for the lock.
                if required_key_id is None or required_key_id in self._keys:
                    return
                # Unknown key IDs come from untrusted headers. Limit forced refreshes
                # so arbitrary IDs cannot cause one Entra request per caller request.
                if now < self._unknown_key_refresh_after:
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
            refreshed_at = time.monotonic()
            self._keys_expire_at = refreshed_at + self._settings.jwks_cache_seconds
            self._unknown_key_refresh_after = (
                refreshed_at + self._settings.unknown_kid_refresh_seconds
            )
