"""Run one interactive positive test through the deployed OBO middleware.

The script signs in through the registered public CLI application, keeps the
middleware-audience token only in memory, and sends one constrained request to
the local Kubernetes port-forward. It never prints or persists either token.
"""

from __future__ import annotations

import argparse
import json
from typing import Any

import httpx
import msal

DEFAULT_TENANT_ID = "e0ca6a1b-554d-4f12-87c9-92ec42abb750"
DEFAULT_CLIENT_ID = "ff46988d-29af-44ca-8b66-f252e5f5388f"
DEFAULT_SCOPE = "api://ec62ae2b-7954-482f-b89a-7b03c29fc7d5/access_as_user"
DEFAULT_MIDDLEWARE_URL = (
    "https://litellm-agent365-mcp-d18f2ff3.eastus2.cloudapp.azure.com/agent/v1/responses"
)


def parse_args() -> argparse.Namespace:
    """Parse non-secret identity, endpoint, and question parameters."""

    parser = argparse.ArgumentParser(
        description="Interactively test the middleware-to-DeepWiki OBO path.",
    )
    parser.add_argument("--tenant-id", default=DEFAULT_TENANT_ID)
    parser.add_argument("--client-id", default=DEFAULT_CLIENT_ID)
    parser.add_argument("--scope", default=DEFAULT_SCOPE)
    parser.add_argument("--middleware-url", default=DEFAULT_MIDDLEWARE_URL)
    parser.add_argument(
        "--device-code",
        action="store_true",
        help="Use a device code instead of opening the system browser automatically.",
    )
    parser.add_argument(
        "--question",
        default="What problem does LiteLLM solve?",
        help="Question sent to the fixed DeepWiki repository through the hosted agent.",
    )
    return parser.parse_args()


def acquire_middleware_token(
    tenant_id: str,
    client_id: str,
    scope: str,
    *,
    use_device_code: bool,
) -> str:
    """Sign in interactively and return one middleware-audience access token.

    MSAL either opens the system browser or displays a short-lived device code.
    Failure output is limited to OAuth metadata; the successful token is never
    printed.
    """

    application = msal.PublicClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
    )
    if use_device_code:
        flow: dict[str, Any] = application.initiate_device_flow(scopes=[scope])
        if "user_code" not in flow:
            raise RuntimeError("Microsoft Entra did not return a device-code flow.")
        print(flow["message"], flush=True)
        result: dict[str, Any] = application.acquire_token_by_device_flow(flow)
    else:
        result = application.acquire_token_interactive(
            scopes=[scope],
            prompt="select_account",
        )
    access_token = result.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        error = result.get("error", "authentication_failed")
        correlation_id = result.get("correlation_id", "unavailable")
        raise RuntimeError(
            f"Interactive sign-in failed: {error} (correlation ID: {correlation_id})."
        )
    return access_token


def invoke_middleware(url: str, token: str, question: str) -> dict[str, Any]:
    """Call the constrained middleware API without logging the bearer token."""

    response = httpx.post(
        url,
        headers={"Authorization": f"Bearer {token}"},
        json={
            "input": question,
            "stream": False,
            "background": False,
            "store": False,
        },
        timeout=180.0,
    )
    if response.is_error:
        request_id = response.headers.get("x-request-id", "unavailable")
        raise RuntimeError(
            f"Middleware returned HTTP {response.status_code} (request ID: {request_id})."
        )

    body = response.json()
    if not isinstance(body, dict):
        raise TypeError("Middleware returned a non-object JSON response.")
    return body


def main() -> None:
    """Authenticate, invoke the fixed OBO path, and print only the response."""

    args = parse_args()
    token = acquire_middleware_token(
        args.tenant_id,
        args.client_id,
        args.scope,
        use_device_code=args.device_code,
    )
    response = invoke_middleware(args.middleware_url, token, args.question)
    print(json.dumps(response, indent=2))


if __name__ == "__main__":
    main()
