"""Exchange a validated caller token for a delegated LiteLLM access token.

This module owns the Microsoft Entra on-behalf-of step. It binds the confidential
middleware application to one downstream scope and preserves claims challenges
needed when Conditional Access requires additional user interaction.
"""

import asyncio
from typing import Any

from msal import ConfidentialClientApplication

from .config import Settings


class OboExchangeError(Exception):
    """Microsoft Entra did not issue the requested delegated downstream token."""

    def __init__(self, error_code: str, claims: str | None = None) -> None:
        super().__init__(error_code)
        self.error_code = error_code
        self.claims = claims


class OboTokenExchanger:
    """Exchange a validated middleware token for a user token scoped to LiteLLM."""

    def __init__(
        self,
        settings: Settings,
        application: ConfidentialClientApplication | None = None,
    ) -> None:
        # Stage 1: bind the exchanger to one downstream permission and one tenant.
        #
        # The confidential application proves the middleware's identity to Entra.
        # The user assertion supplied later proves which user is being represented.
        self._scope = settings.downstream_scope
        self._application = application or ConfidentialClientApplication(
            client_id=settings.client_id,
            authority=settings.authority,
            client_credential=settings.client_secret.get_secret_value(),
        )
        self._lock = asyncio.Lock()

    async def exchange(self, user_assertion: str) -> str:
        # Stage 2: exchange the validated incoming token for a new token whose
        # audience and delegated permission are limited to the configured LiteLLM API.
        #
        # MSAL is synchronous. Run it off the event loop and serialize access to its
        # in-memory token cache.
        async with self._lock:
            result: dict[str, Any] = await asyncio.to_thread(
                self._application.acquire_token_on_behalf_of,
                user_assertion=user_assertion,
                scopes=[self._scope],
            )

        # Stage 3: return only a real access token; treat every other MSAL result as
        # an authentication failure rather than manufacturing a success-shaped value.
        access_token = result.get("access_token")
        if isinstance(access_token, str) and access_token:
            return access_token

        error_code = str(result.get("error", "obo_exchange_failed"))
        claims = result.get("claims")
        # Stage 4: carry an interaction challenge back to the client when Conditional
        # Access requires additional user action.
        #
        # Preserve a Conditional Access claims challenge, but do not expose MSAL's
        # error_description because it can contain unnecessary tenant details.
        raise OboExchangeError(
            error_code=error_code,
            claims=claims if isinstance(claims, str) else None,
        )
