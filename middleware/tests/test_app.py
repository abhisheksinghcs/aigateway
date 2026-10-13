"""Verify FastAPI orchestration, security ordering, and public error handling.

The tests use fakes to prove validation happens before OBO and Foundry calls,
trusted identity values are forwarded, and internal failures stay sanitized.
"""

from dataclasses import dataclass, field

import httpx
import pytest

from foundry_middleware.app import Services, create_app
from foundry_middleware.auth import TokenValidationError, UserIdentity
from foundry_middleware.obo import OboExchangeError


class FakeValidator:
    async def validate(self, token: str) -> UserIdentity:
        if token != "incoming-user-token":
            raise TokenValidationError("Access token validation failed.")
        return UserIdentity(
            object_id="11111111-1111-1111-1111-111111111111",
            tenant_id="22222222-2222-2222-2222-222222222222",
            subject="user-subject",
        )


class FakeExchanger:
    def __init__(self, should_fail: bool = False) -> None:
        self.should_fail = should_fail
        self.assertion: str | None = None

    async def exchange(self, user_assertion: str) -> str:
        self.assertion = user_assertion
        if self.should_fail:
            raise OboExchangeError("interaction_required", claims="claims-challenge")
        return "delegated-litellm-token"


@dataclass
class FakeFoundryClient:
    calls: list[dict[str, object]] = field(default_factory=list)

    async def create_response(
        self,
        payload: dict[str, object],
        delegated_token: str,
        user_object_id: str,
    ) -> dict[str, object]:
        self.calls.append(
            {
                "payload": payload,
                "delegated_token": delegated_token,
                "user_object_id": user_object_id,
            }
        )
        return {"id": "response-1", "status": "completed"}


@pytest.fixture
def service_fakes() -> tuple[Services, FakeExchanger, FakeFoundryClient]:
    exchanger = FakeExchanger()
    foundry_client = FakeFoundryClient()
    return (
        Services(
            validator=FakeValidator(),
            exchanger=exchanger,
            foundry_client=foundry_client,
        ),
        exchanger,
        foundry_client,
    )


async def test_response_flow_uses_validated_identity_and_obo_token(
    service_fakes: tuple[Services, FakeExchanger, FakeFoundryClient],
) -> None:
    services, exchanger, foundry_client = service_fakes
    app = create_app(services)
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/v1/responses",
                headers={"Authorization": "Bearer incoming-user-token"},
                json={"input": "List my approved DeepWiki tools."},
            )

    assert response.status_code == 200
    assert response.json() == {"id": "response-1", "status": "completed"}
    assert exchanger.assertion == "incoming-user-token"
    assert foundry_client.calls == [
        {
            "payload": {
                "input": "List my approved DeepWiki tools.",
                "stream": False,
                "background": False,
                "store": False,
            },
            "delegated_token": "delegated-litellm-token",
            "user_object_id": "11111111-1111-1111-1111-111111111111",
        }
    ]


async def test_missing_bearer_token_is_rejected(
    service_fakes: tuple[Services, FakeExchanger, FakeFoundryClient],
) -> None:
    services, _, _ = service_fakes
    app = create_app(services)
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post("/v1/responses", json={"input": "hello"})

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


async def test_streaming_and_unknown_fields_are_rejected(
    service_fakes: tuple[Services, FakeExchanger, FakeFoundryClient],
) -> None:
    services, _, _ = service_fakes
    app = create_app(services)
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/v1/responses",
                headers={"Authorization": "Bearer incoming-user-token"},
                json={"input": "hello", "stream": True, "target_url": "https://example.com"},
            )

    assert response.status_code == 422


async def test_claims_challenge_is_returned_to_client() -> None:
    services = Services(
        validator=FakeValidator(),
        exchanger=FakeExchanger(should_fail=True),
        foundry_client=FakeFoundryClient(),
    )
    app = create_app(services)
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/v1/responses",
                headers={"Authorization": "Bearer incoming-user-token"},
                json={"input": "hello"},
            )

    assert response.status_code == 401
    assert "interaction_required" in response.headers["www-authenticate"]
    assert "claims-challenge" in response.headers["www-authenticate"]
