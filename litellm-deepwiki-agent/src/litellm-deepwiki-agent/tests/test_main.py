"""Verify the AgentServer host can be constructed from validated settings."""

from dataclasses import dataclass, field

import httpx
import pytest

from config import Settings
from main import create_app


@dataclass
class FakeDeepWikiClient:
    """Return a deterministic answer while recording the protocol input."""

    calls: list[tuple[str, str]] = field(default_factory=list)

    async def ask(self, question: str, delegated_token: str) -> str:
        """Capture the validated request values and return local test text."""
        self.calls.append((question, delegated_token))
        return "Protocol integration answer"


def test_create_app_builds_agentserver_host() -> None:
    """Prove validated settings can construct the complete protocol host."""
    settings = Settings(
        litellm_mcp_url="https://gateway.example.com/mcp",
        litellm_virtual_key="sk-restricted",
        deepwiki_repository="microsoft/semantic-kernel",
    )

    assert create_app(settings) is not None


@pytest.mark.asyncio
async def test_responses_route_returns_answer_with_forwarded_token() -> None:
    """Prove the real HTTP route reaches the constrained client successfully."""
    settings = Settings(
        litellm_mcp_url="https://gateway.example.com/mcp",
        litellm_virtual_key="sk-restricted",
        deepwiki_repository="microsoft/semantic-kernel",
    )
    client = FakeDeepWikiClient()
    app = create_app(settings, deepwiki_client=client)

    # ASGITransport exercises the SDK's real /responses route in process. The
    # fake client prevents network access and keeps test credentials synthetic.
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://agent.test",
    ) as http_client:
        response = await http_client.post(
            "/responses",
            headers={"x-client-litellm-user-token": "delegated-test-token"},
            json={"input": "How does the repository work?", "store": False},
        )

    assert response.status_code == 200
    assert response.json()["output"][0]["content"][0]["text"] == (
        "Protocol integration answer"
    )
    assert client.calls == [("How does the repository work?", "delegated-test-token")]
