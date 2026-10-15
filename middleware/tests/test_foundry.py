"""Verify Foundry transport failures are translated without leaking credentials."""

import httpx
import pytest

from foundry_middleware.config import Settings
from foundry_middleware.foundry import FoundryClient, FoundryInvocationError


class FakeTokenProvider:
    """Return a synthetic workload token without contacting Microsoft Entra."""

    async def get_token(self) -> str:
        return "synthetic-workload-token"

    async def close(self) -> None:
        return None


def make_settings() -> Settings:
    """Create the minimum valid fixed-destination middleware configuration."""

    return Settings(
        tenant_id="11111111-1111-1111-1111-111111111111",
        client_id="22222222-2222-2222-2222-222222222222",
        client_secret="synthetic-client-secret",
        downstream_scope="api://33333333-3333-3333-3333-333333333333/access_as_user",
        foundry_responses_endpoint=(
            "https://example.services.ai.azure.com/api/projects/example/agents/"
            "test/endpoint/protocols/openai/responses?api-version=v1"
        ),
    )


async def test_foundry_read_timeout_becomes_gateway_timeout() -> None:
    """Translate an HTTP read timeout into a sanitized Foundry error."""

    async def timeout_handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("synthetic timeout", request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(timeout_handler)) as http_client:
        client = FoundryClient(make_settings(), http_client, FakeTokenProvider())
        with pytest.raises(FoundryInvocationError) as error:
            await client.create_response(
                payload={"input": "Explain fallbacks."},
                delegated_token="synthetic-delegated-token",
                user_object_id="44444444-4444-4444-4444-444444444444",
            )

    assert error.value.status_code == 504
    assert error.value.request_id is None
