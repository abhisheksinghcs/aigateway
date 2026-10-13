"""Assemble the FastAPI application and orchestrate the complete request flow.

This is the middleware entry point: it validates the caller, performs OBO,
invokes Foundry with trusted identity headers, and translates expected failures
into sanitized HTTP responses.
"""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Annotated, Protocol

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .auth import EntraTokenValidator, TokenValidationError, UserIdentity
from .config import Settings
from .foundry import (
    FoundryClient,
    FoundryInvocationError,
    FoundryTokenProvider,
    WorkloadIdentityTokenProvider,
)
from .models import CreateResponseRequest
from .obo import OboExchangeError, OboTokenExchanger


class TokenValidator(Protocol):
    """Validate a caller token and return claims safe for authorization decisions."""

    async def validate(self, token: str) -> UserIdentity: ...


class TokenExchanger(Protocol):
    """Acquire a delegated token for the configured downstream API."""

    async def exchange(self, user_assertion: str) -> str: ...


class AgentClient(Protocol):
    """Invoke the configured hosted agent with trusted user context."""

    async def create_response(
        self,
        payload: dict[str, object],
        delegated_token: str,
        user_object_id: str,
    ) -> dict[str, object]: ...


@dataclass
class Services:
    """Dependencies grouped for startup wiring and isolated unit tests."""

    validator: TokenValidator
    exchanger: TokenExchanger
    foundry_client: AgentClient
    http_client: httpx.AsyncClient | None = None
    token_provider: FoundryTokenProvider | None = None


bearer_scheme = HTTPBearer(auto_error=False)


def build_services(settings: Settings) -> Services:
    """Create production dependencies that share one bounded HTTP client."""

    # Stage 1: compose one process-wide graph of production dependencies.
    #
    # Reusing the HTTP client preserves connection pooling and applies one timeout to
    # OpenID discovery, JWKS retrieval, and Foundry calls.
    http_client = httpx.AsyncClient(timeout=settings.request_timeout_seconds)
    token_provider = WorkloadIdentityTokenProvider(settings)
    return Services(
        validator=EntraTokenValidator(settings, http_client),
        exchanger=OboTokenExchanger(settings),
        foundry_client=FoundryClient(settings, http_client, token_provider),
        http_client=http_client,
        token_provider=token_provider,
    )


def create_app(services: Services | None = None) -> FastAPI:
    """Create the FastAPI application, optionally with test doubles."""

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
        # Stage 2: initialize fail-closed runtime services before accepting traffic.
        #
        # Tests inject fakes. Production loads fail-closed environment settings and
        # creates network clients only once for the process lifetime.
        runtime_services = services or build_services(Settings())
        app.state.services = runtime_services
        try:
            yield
        finally:
            # Close shared network transports during graceful pod termination.
            if runtime_services.http_client is not None:
                await runtime_services.http_client.aclose()
            if runtime_services.token_provider is not None:
                await runtime_services.token_provider.close()

    application = FastAPI(
        title="LiteLLM Foundry Middleware",
        version="0.1.0",
        lifespan=lifespan,
    )

    @application.get("/healthz")
    async def health() -> dict[str, str]:
        # Liveness proves that the web process can answer; it does not call Entra.
        return {"status": "healthy"}

    @application.get("/readyz")
    async def ready(request: Request) -> dict[str, str]:
        # Readiness requires successful lifespan initialization and configuration.
        if not hasattr(request.app.state, "services"):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Middleware services are not initialized.",
            )
        return {"status": "ready"}

    async def authenticated_request(
        request: Request,
        credentials: Annotated[
            HTTPAuthorizationCredentials | None,
            Depends(bearer_scheme),
        ],
    ) -> tuple[str, UserIdentity]:
        # Stage 3: authenticate the user-facing request.
        #
        # Authentication always happens before OBO. An unvalidated assertion must
        # never reach MSAL or be forwarded to another service.
        if credentials is None or credentials.scheme.lower() != "bearer":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="A bearer access token is required.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        try:
            # This call completes all three validation stages in auth.py before the
            # original token can be used as an OBO assertion.
            identity = await request.app.state.services.validator.validate(credentials.credentials)
        except TokenValidationError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=str(exc),
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc
        return credentials.credentials, identity

    @application.post("/v1/responses")
    async def create_response(
        request: Request,
        body: CreateResponseRequest,
        authentication: Annotated[
            tuple[str, UserIdentity],
            Depends(authenticated_request),
        ],
    ) -> dict[str, object]:
        # Stage 4: perform OBO and invoke Foundry only for an authenticated request.
        user_assertion, identity = authentication
        try:
            # Change the token audience through OBO, then bind the invocation to the
            # object ID extracted from the already validated incoming token.
            delegated_token = await request.app.state.services.exchanger.exchange(user_assertion)
            return await request.app.state.services.foundry_client.create_response(
                payload=body.model_dump(),
                delegated_token=delegated_token,
                user_object_id=identity.object_id,
            )
        except OboExchangeError as exc:
            # Preserve a Conditional Access challenge so the interactive client can
            # satisfy policy and retry; never substitute app-only access.
            headers = {"WWW-Authenticate": f'Bearer error="{exc.error_code}"'}
            if exc.claims:
                headers["WWW-Authenticate"] += f', claims="{exc.claims}"'
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Unable to acquire delegated downstream access.",
                headers=headers,
            ) from exc
        except FoundryInvocationError as exc:
            # Convert all Foundry failures into a stable gateway error and include only
            # a safe correlation ID for troubleshooting.
            detail: dict[str, str] = {"error": "foundry_invocation_failed"}
            if exc.request_id:
                detail["request_id"] = exc.request_id
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=detail,
            ) from exc

    return application


app = create_app()
