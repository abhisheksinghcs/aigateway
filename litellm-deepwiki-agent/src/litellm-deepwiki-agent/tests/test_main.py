"""Verify the AgentServer host can be constructed from validated settings."""

from config import Settings
from main import create_app


def test_create_app_builds_agentserver_host() -> None:
    """Prove validated settings can construct the complete protocol host."""
    settings = Settings(
        litellm_mcp_url="https://gateway.example.com/mcp",
        litellm_virtual_key="sk-restricted",
        deepwiki_repository="microsoft/semantic-kernel",
    )

    assert create_app(settings) is not None
