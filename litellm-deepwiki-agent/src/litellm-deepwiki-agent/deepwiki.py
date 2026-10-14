"""Implement the only outbound capability granted to the hosted agent.

``DeepWikiClient`` combines deployment-fixed settings with two request values:
validated question text and a request-scoped delegated LiteLLM token. It opens
a short-lived MCP Streamable HTTP session, calls exactly
``deepwiki-ask_wiki_question``, converts text content to a Responses-ready
string, and replaces upstream failures with credential-safe errors.
"""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from typing import Any

import httpx2
from mcp import ClientSession
from mcp.client.streamable_http import (
    create_mcp_http_client,
    streamable_http_client,
)
from mcp.shared.exceptions import MCPError
from mcp.types import CallToolResult, TextContent

from config import Settings

_TOOL_NAME = "deepwiki-ask_wiki_question"
_READ_TIMEOUT_SECONDS = 90.0

logger = logging.getLogger(__name__)

ToolCaller = Callable[
    [str, dict[str, str], str, dict[str, Any]], Awaitable[CallToolResult]
]
"""Injectable MCP transport signature used to test the fixed outbound call."""


class DeepWikiError(RuntimeError):
    """Report a downstream failure without exposing tokens, keys, or headers."""


async def _call_mcp_tool(
    url: str,
    headers: dict[str, str],
    tool_name: str,
    arguments: dict[str, Any],
) -> CallToolResult:
    """Execute one MCP tool call and close all network resources.

    Args:
        url: Deployment-validated LiteLLM ``/mcp`` endpoint.
        headers: Authentication headers assembled by ``DeepWikiClient``.
        tool_name: Code-fixed, LiteLLM-prefixed DeepWiki tool name.
        arguments: Fixed repository plus validated caller question.

    Returns:
        A complete MCP tool result.

    Raises:
        DeepWikiError: The MCP SDK returns a result shape this adapter does not
            support. Network and protocol exceptions propagate to
            ``DeepWikiClient.ask`` for credential-safe translation.
    """
    # Stage 1: One request gets one HTTP client and one MCP session. Closing the
    # nested contexts prevents delegated credentials from surviving the call.
    async with (
        create_mcp_http_client(headers=headers) as http_client,
        streamable_http_client(
            url,
            http_client=http_client,
            terminate_on_close=True,
        ) as (read_stream, write_stream),
        ClientSession(
            read_stream,
            write_stream,
            read_timeout_seconds=_READ_TIMEOUT_SECONDS,
        ) as session,
    ):
        # MCP requires initialization before tool invocation so LiteLLM can
        # negotiate protocol capabilities for this short-lived session.
        await session.initialize()
        result = await session.call_tool(
            tool_name,
            arguments,
            read_timeout_seconds=_READ_TIMEOUT_SECONDS,
        )

    if not isinstance(result, CallToolResult):
        raise DeepWikiError("DeepWiki returned an unsupported response")
    return result


class DeepWikiClient:
    """Bind request data to one deployment-approved DeepWiki capability.

    The instance is created once during application startup. Its settings and
    tool caller never come from a request, so callers cannot redirect the
    destination or expand the tool surface.
    """

    def __init__(
        self,
        settings: Settings,
        tool_caller: ToolCaller = _call_mcp_tool,
    ) -> None:
        """Create a fixed adapter and optionally inject a test transport.

        Args:
            settings: Validated immutable deployment configuration.
            tool_caller: MCP transport function. Production uses
                ``_call_mcp_tool``; tests inject a recorder or failure stub.
        """
        self._settings = settings
        self._tool_caller = tool_caller

    async def ask(self, question: str, delegated_token: str) -> str:
        """Call the approved DeepWiki tool and return credential-safe text.

        Args:
            question: Validated plain text from the current Responses request.
            delegated_token: Raw request-scoped OBO token for LiteLLM.

        Returns:
            Non-empty text assembled from the MCP result.

        Raises:
            DeepWikiError: The transport fails, DeepWiki reports a tool error,
                or the result contains no usable text. Messages never contain
                the delegated token or virtual key.
        """
        # Stage 1: Build the two-header authorization contract already enforced
        # by LiteLLM: delegated user context plus an app-level restricted key.
        headers = {
            "Authorization": f"Bearer {delegated_token}",
            "x-litellm-api-key": self._settings.litellm_virtual_key,
        }
        # The repository and tool are not request parameters. Only the validated
        # question crosses from the caller into the fixed argument object.
        arguments = {
            "repoName": self._settings.deepwiki_repository,
            "question": question,
        }

        # Stage 2: Translate known network/protocol failures without including
        # exception text, because third-party exceptions may embed headers.
        try:
            result = await self._tool_caller(
                self._settings.litellm_mcp_url,
                headers,
                _TOOL_NAME,
                arguments,
            )
        except (
            httpx2.HTTPError,
            MCPError,
            OSError,
            TimeoutError,
            ExceptionGroup,
        ) as error:
            logger.error("DeepWiki MCP call failed: %s", type(error).__name__)
            raise DeepWikiError("DeepWiki is temporarily unavailable") from None

        # Stage 3: Treat both explicit tool errors and empty output as failures;
        # never return a success-shaped response when DeepWiki did not answer.
        if result.is_error:
            raise DeepWikiError("DeepWiki could not answer the question")

        text_parts = [
            item.text for item in result.content if isinstance(item, TextContent)
        ]
        answer = "\n".join(part for part in text_parts if part).strip()
        if not answer:
            raise DeepWikiError("DeepWiki returned no text")
        return answer
