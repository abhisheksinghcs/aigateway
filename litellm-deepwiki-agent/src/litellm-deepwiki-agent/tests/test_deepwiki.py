"""Verify the DeepWiki adapter fixes the gateway, repository, and tool."""

import pytest
from mcp.types import CallToolResult, TextContent

from config import Settings
from deepwiki import DeepWikiClient, DeepWikiError


@pytest.mark.asyncio
async def test_ask_uses_only_fixed_destination_repository_and_tool() -> None:
    """Prove caller input cannot alter the outbound capability selection."""
    captured: dict[str, object] = {}

    async def fake_tool_caller(
        url: str,
        headers: dict[str, str],
        tool_name: str,
        arguments: dict[str, object],
    ) -> CallToolResult:
        """Record the complete outbound call and return one text item."""
        captured.update(
            url=url,
            headers=headers,
            tool_name=tool_name,
            arguments=arguments,
        )
        return CallToolResult(content=[TextContent(text="Grounded answer")])

    settings = Settings(
        litellm_mcp_url="https://gateway.example.com/mcp",
        litellm_virtual_key="sk-restricted",
        deepwiki_repository="microsoft/semantic-kernel",
    )
    client = DeepWikiClient(settings, tool_caller=fake_tool_caller)

    answer = await client.ask("How does planning work?", "delegated-token")

    assert answer == "Grounded answer"
    assert captured == {
        "url": "https://gateway.example.com/mcp",
        "headers": {
            "Authorization": "Bearer delegated-token",
            "x-litellm-api-key": "sk-restricted",
        },
        "tool_name": "deepwiki-ask_wiki_question",
        "arguments": {
            "repoName": "microsoft/semantic-kernel",
            "question": "How does planning work?",
        },
    }


@pytest.mark.asyncio
async def test_ask_joins_text_content() -> None:
    """Prove multiple MCP text items become one Responses-ready answer."""

    async def fake_tool_caller(
        _url: str,
        _headers: dict[str, str],
        _tool_name: str,
        _arguments: dict[str, object],
    ) -> CallToolResult:
        """Return two text items without opening a network connection."""
        return CallToolResult(
            content=[TextContent(text="First"), TextContent(text="Second")]
        )

    settings = Settings(
        litellm_mcp_url="https://gateway.example.com/mcp",
        litellm_virtual_key="sk-restricted",
        deepwiki_repository="microsoft/semantic-kernel",
    )

    answer = await DeepWikiClient(settings, fake_tool_caller).ask(
        "Question",
        "delegated-token",
    )

    assert answer == "First\nSecond"


@pytest.mark.asyncio
async def test_ask_redacts_credentials_from_transport_errors() -> None:
    """Prove exception text containing headers cannot escape the adapter."""

    async def failing_tool_caller(
        _url: str,
        headers: dict[str, str],
        _tool_name: str,
        _arguments: dict[str, object],
    ) -> CallToolResult:
        """Simulate a transport exception that embeds sensitive headers."""
        raise OSError(f"request failed with headers {headers}")

    secret = "sk-never-display"
    token = "delegated-never-display"
    settings = Settings(
        litellm_mcp_url="https://gateway.example.com/mcp",
        litellm_virtual_key=secret,
        deepwiki_repository="microsoft/semantic-kernel",
    )

    with pytest.raises(DeepWikiError) as error:
        await DeepWikiClient(settings, failing_tool_caller).ask("Question", token)

    assert secret not in str(error.value)
    assert token not in str(error.value)
