# Copyright (c) Microsoft. All rights reserved.

"""Compose and start the Foundry Responses protocol service.

This is the hosted agent's composition root: it validates deployment
configuration, creates the fixed DeepWiki adapter, and connects the adapter to
the AgentServer SDK. It contains no OBO logic and owns no middleware secret;
the only request credential it receives is the delegated token that Foundry
forwards in ``ResponseContext.client_headers``.
"""

import asyncio

from azure.ai.agentserver.responses import (
    CreateResponse,
    ResponseContext,
    ResponsesAgentServerHost,
    ResponsesServerOptions,
    TextResponse,
)

from agent import DeepWikiQuestionClient, answer_question
from config import Settings
from deepwiki import DeepWikiClient


def create_app(
    settings: Settings | None = None,
    deepwiki_client: DeepWikiQuestionClient | None = None,
) -> ResponsesAgentServerHost:
    """Construct the configured AgentServer application.

    Args:
        settings: Optional validated settings used by tests. Production callers
            omit this argument so configuration is loaded from environment
            variables and validated before the server starts.
        deepwiki_client: Optional constrained client used by protocol-level
            tests. Production callers omit it so the real MCP adapter is
            created from validated settings.

    Returns:
        A host with one Responses handler bound to the deterministic DeepWiki
        request flow.

    Raises:
        SettingsError: A required setting is missing or violates the fixed
            destination policy.
    """
    # Stage 1: Resolve configuration once at startup so an unsafe container
    # never becomes ready and then fails unpredictably on its first request.
    resolved_settings = Settings.from_env() if settings is None else settings

    # Stage 2: Create one adapter whose URL, repository, tool, and internal key
    # are fixed for the lifetime of this process. Tests can inject the same
    # narrow protocol to exercise AgentServer without using real credentials.
    resolved_client = (
        DeepWikiClient(resolved_settings)
        if deepwiki_client is None
        else deepwiki_client
    )

    # AgentServer owns the HTTP endpoints and Responses event lifecycle. The
    # SDK requires a positive history count; the handler intentionally ignores
    # history because each POC request is one independent question.
    app = ResponsesAgentServerHost(
        options=ResponsesServerOptions(default_fetch_history_count=1),
    )

    @app.response_handler
    async def handler(
        request: CreateResponse,
        context: ResponseContext,
        _cancellation_signal: asyncio.Event,
    ) -> TextResponse:
        """Handle one Foundry request and emit one completed text response.

        ``answer_question`` owns token and input validation. This wrapper only
        adapts its returned text to the protocol object expected by Foundry.
        Exceptions remain explicit so AgentServer records a failed response
        rather than returning a success-shaped fallback.
        """
        answer = await answer_question(context, resolved_client)
        return TextResponse(context, request, text=answer)

    return app


if __name__ == "__main__":
    # Importing this module is side-effect free for tests; executing it starts
    # the HTTP service used by local and Foundry-hosted containers.
    create_app().run()
