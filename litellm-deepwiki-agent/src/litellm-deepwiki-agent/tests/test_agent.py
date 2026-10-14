"""Verify request validation and delegated-token handling."""

from dataclasses import dataclass, field

import pytest

from agent import QuestionError, answer_question
from auth import DelegatedTokenError


class FakeContext:
    """Provide only the request-context surface consumed by ``agent.py``."""

    def __init__(self, question: str, headers: dict[str, str]) -> None:
        """Store deterministic input text and forwarded headers for one test."""
        self._question = question
        self.client_headers = headers

    async def get_input_text(self) -> str:
        """Return the current test question without using AgentServer storage."""
        return self._question


@dataclass
class FakeDeepWikiClient:
    """Record adapter calls so tests can inspect the orchestration boundary."""

    answer: str = "DeepWiki answer"
    calls: list[tuple[str, str]] = field(default_factory=list)

    async def ask(self, question: str, delegated_token: str) -> str:
        """Capture request values and return a deterministic answer."""
        self.calls.append((question, delegated_token))
        return self.answer


@pytest.mark.asyncio
async def test_answer_question_requires_delegated_token() -> None:
    """Prove missing user delegation prevents every downstream call."""
    client = FakeDeepWikiClient()
    context = FakeContext("How does this work?", {})

    with pytest.raises(DelegatedTokenError):
        await answer_question(context, client)

    assert client.calls == []


@pytest.mark.asyncio
async def test_answer_question_rejects_empty_question() -> None:
    """Prove whitespace-only input is rejected after token validation."""
    client = FakeDeepWikiClient()
    context = FakeContext("  ", {"X-Client-LiteLLM-User-Token": "user-token"})

    with pytest.raises(QuestionError):
        await answer_question(context, client)


@pytest.mark.asyncio
async def test_answer_question_passes_only_question_and_token() -> None:
    """Prove orchestration forwards only validated text and delegation."""
    client = FakeDeepWikiClient()
    context = FakeContext(
        "How does this work?",
        {"X-Client-LiteLLM-User-Token": "user-token"},
    )

    answer = await answer_question(context, client)

    assert answer == "DeepWiki answer"
    assert client.calls == [("How does this work?", "user-token")]
