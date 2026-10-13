import pytest

from foundry_middleware.config import Settings
from foundry_middleware.obo import OboExchangeError, OboTokenExchanger


class FakeConfidentialClient:
    def __init__(self, result: dict[str, str]) -> None:
        self.result = result
        self.calls: list[dict[str, object]] = []

    def acquire_token_on_behalf_of(
        self,
        *,
        user_assertion: str,
        scopes: list[str],
    ) -> dict[str, str]:
        self.calls.append({"user_assertion": user_assertion, "scopes": scopes})
        return self.result


def make_settings() -> Settings:
    return Settings(
        tenant_id="22222222-2222-2222-2222-222222222222",
        client_id="33333333-3333-3333-3333-333333333333",
        client_secret="not-a-real-secret",
        downstream_scope="api://gateway/access_as_user",
        foundry_responses_endpoint=(
            "https://example.services.ai.azure.com/api/projects/project/agents/agent/"
            "endpoint/protocols/openai/responses?api-version=v1"
        ),
    )


async def test_obo_uses_incoming_assertion_and_only_configured_scope() -> None:
    application = FakeConfidentialClient({"access_token": "delegated-token"})
    exchanger = OboTokenExchanger(make_settings(), application=application)  # type: ignore[arg-type]

    token = await exchanger.exchange("incoming-token")

    assert token == "delegated-token"
    assert application.calls == [
        {
            "user_assertion": "incoming-token",
            "scopes": ["api://gateway/access_as_user"],
        }
    ]


async def test_obo_preserves_claims_challenge_without_token_details() -> None:
    application = FakeConfidentialClient(
        {
            "error": "interaction_required",
            "claims": "claims-challenge",
            "error_description": "description that must not be exposed",
        }
    )
    exchanger = OboTokenExchanger(make_settings(), application=application)  # type: ignore[arg-type]

    with pytest.raises(OboExchangeError) as caught:
        await exchanger.exchange("incoming-token")

    assert caught.value.error_code == "interaction_required"
    assert caught.value.claims == "claims-challenge"
    assert "description" not in str(caught.value)
