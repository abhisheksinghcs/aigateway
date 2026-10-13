from typing import Any, Protocol

import httpx
from azure.core.credentials import AccessToken
from azure.identity.aio import DefaultAzureCredential

from .config import Settings


class FoundryInvocationError(Exception):
    """Foundry rejected the invocation or returned an unusable response."""

    def __init__(self, status_code: int, request_id: str | None) -> None:
        super().__init__(f"Foundry invocation failed with status {status_code}.")
        self.status_code = status_code
        self.request_id = request_id


class FoundryTokenProvider(Protocol):
    """Provide a workload token that authenticates the middleware to Foundry."""

    async def get_token(self) -> str: ...

    async def close(self) -> None: ...


class WorkloadIdentityTokenProvider:
    """Acquire Foundry tokens through DefaultAzureCredential.

    In AKS, the workload-identity webhook supplies the environment and projected
    token file that DefaultAzureCredential uses.
    """

    def __init__(
        self,
        settings: Settings,
        credential: DefaultAzureCredential | None = None,
    ) -> None:
        self._scope = settings.foundry_scope
        self._credential = credential or DefaultAzureCredential()

    async def get_token(self) -> str:
        token: AccessToken = await self._credential.get_token(self._scope)
        return token.token

    async def close(self) -> None:
        await self._credential.close()


class FoundryClient:
    """Invoke one fixed hosted-agent Responses endpoint for a validated user."""

    def __init__(
        self,
        settings: Settings,
        http_client: httpx.AsyncClient,
        token_provider: FoundryTokenProvider,
    ) -> None:
        self._endpoint = str(settings.foundry_responses_endpoint)
        self._http_client = http_client
        self._token_provider = token_provider

    async def create_response(
        self,
        payload: dict[str, Any],
        delegated_token: str,
        user_object_id: str,
    ) -> dict[str, Any]:
        workload_token = await self._token_provider.get_token()
        # These values serve separate trust purposes: Authorization authenticates the
        # middleware workload, x-client-* transports the OBO token to agent code, and
        # x-ms-user-identity scopes Foundry's per-user context.
        response = await self._http_client.post(
            self._endpoint,
            headers={
                "Authorization": f"Bearer {workload_token}",
                "x-client-litellm-user-token": delegated_token,
                "x-ms-user-identity": user_object_id,
            },
            json=payload,
        )

        if response.is_error:
            # Return only status and request correlation. Do not reflect an upstream
            # body that might contain tenant details or token-related diagnostics.
            raise FoundryInvocationError(
                status_code=response.status_code,
                request_id=response.headers.get("x-ms-request-id"),
            )

        try:
            body = response.json()
        except ValueError as exc:
            raise FoundryInvocationError(
                status_code=502,
                request_id=response.headers.get("x-ms-request-id"),
            ) from exc

        if not isinstance(body, dict):
            raise FoundryInvocationError(
                status_code=502,
                request_id=response.headers.get("x-ms-request-id"),
            )
        return body
