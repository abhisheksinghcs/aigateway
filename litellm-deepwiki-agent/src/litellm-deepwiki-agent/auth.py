"""Enforce the request-scoped delegated-token boundary.

The AKS middleware validates the original user token and exchanges it through
Entra OBO for LiteLLM. Foundry then forwards that downstream token in the
custom ``x-client-litellm-user-token`` header. This module accepts only that
header and returns the raw token without logging, decoding, or persisting it.
"""

from __future__ import annotations

from collections.abc import Mapping

DELEGATED_TOKEN_HEADER = "x-client-litellm-user-token"


class DelegatedTokenError(ValueError):
    """Reject requests that cannot prove delegated LiteLLM user context."""


def get_delegated_token(headers: Mapping[str, str]) -> str:
    """Extract the raw delegated token from Foundry-forwarded headers.

    Args:
        headers: Request headers exposed by ``ResponseContext.client_headers``.
            Header names are matched case-insensitively.

    Returns:
        The raw OBO access token for use in the outbound LiteLLM
        ``Authorization`` header.

    Raises:
        DelegatedTokenError: The trusted custom header is missing, malformed,
            padded with whitespace, or incorrectly contains a ``Bearer``
            prefix.
    """
    # Foundry may normalize header casing, so compare names case-insensitively
    # while refusing to fall back to any caller-selected authorization header.
    token = next(
        (
            value
            for name, value in headers.items()
            if name.lower() == DELEGATED_TOKEN_HEADER
        ),
        "",
    )
    if not token or token != token.strip():
        raise DelegatedTokenError(
            f"Missing or invalid {DELEGATED_TOKEN_HEADER} request header"
        )
    # The middleware forwards a raw token. Rejecting, rather than repairing, a
    # prefixed value keeps the contract unambiguous across all three services.
    if token.lower().startswith("bearer "):
        raise DelegatedTokenError(
            f"{DELEGATED_TOKEN_HEADER} must contain the raw token"
        )
    return token
