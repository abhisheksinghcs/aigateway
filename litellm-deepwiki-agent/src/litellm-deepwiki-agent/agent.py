"""Orchestrate one validated Foundry request without choosing tools or routes.

This module is the request boundary between AgentServer and the DeepWiki
adapter. It extracts the middleware-issued delegated token, accepts only plain
question text, and passes those two values to an adapter whose destination,
repository, tool, and internal key were fixed at process startup.
"""

from __future__ import annotations

from typing import Protocol

from auth import get_delegated_token

_MAX_QUESTION_LENGTH = 4_000


class DeepWikiQuestionClient(Protocol):
    """Describe the only downstream operation request handling is allowed.

    Production uses ``DeepWikiClient`` and tests use an in-memory fake. Keeping
    this interface narrow prevents orchestration code from selecting an MCP
    server, URL, repository, or tool.
    """

    async def ask(self, question: str, delegated_token: str) -> str:
        """Return text for one question using request-scoped user delegation."""


class RequestContext(Protocol):
    """Describe the small AgentServer context surface this module consumes.

    The real ``ResponseContext`` has many capabilities, but this flow needs
    only forwarded headers and current input text. The reduced protocol makes
    that trust boundary visible and keeps tests independent of SDK internals.
    """

    client_headers: dict[str, str]

    async def get_input_text(self) -> str:
        """Return the caller's current Responses input as text."""


class QuestionError(ValueError):
    """Reject input that is empty or exceeds the deterministic POC limit."""


async def answer_question(
    context: RequestContext,
    deepwiki_client: DeepWikiQuestionClient,
) -> str:
    """Validate one request and return its DeepWiki answer.

    Args:
        context: AgentServer request context containing forwarded headers and
            current input text.
        deepwiki_client: Already-configured client limited to the approved
            repository and tool.

    Returns:
        Plain answer text that ``main.py`` wraps in ``TextResponse``.

    Raises:
        DelegatedTokenError: The middleware-issued downstream token is absent
            or malformed.
        QuestionError: The current input is empty or longer than 4,000
            characters.
        DeepWikiError: LiteLLM or DeepWiki cannot produce a usable answer.
    """
    # Stage 1: Establish delegated user context before doing any downstream
    # work. A question alone is never sufficient authorization.
    delegated_token = get_delegated_token(context.client_headers)

    # Stage 2: Treat only current plain text as caller-controlled data. No
    # repository, endpoint, tool, or header can enter through this boundary.
    question = (await context.get_input_text()).strip()
    if not question:
        raise QuestionError("A question is required")
    if len(question) > _MAX_QUESTION_LENGTH:
        raise QuestionError(
            f"Question must be at most {_MAX_QUESTION_LENGTH} characters"
        )
    # Stage 3: Delegate to the client that was constrained at startup.
    return await deepwiki_client.ask(question, delegated_token)
