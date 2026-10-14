"""Define the hosted agent's deployment-controlled security boundary.

The caller must not choose where the agent connects or which repository it
queries. This module loads those decisions from container environment
variables, validates them before startup, and returns an immutable object for
the rest of the process. Validation errors mention variable names only and
never echo the LiteLLM virtual key.
"""

from __future__ import annotations

import os
import re
from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import urlsplit

_REPOSITORY_PATTERN = re.compile(
    r"^[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,99})/"
    r"[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,99})$"
)


class SettingsError(ValueError):
    """Report missing or unsafe deployment settings without exposing values."""


@dataclass(frozen=True)
class Settings:
    """Immutable configuration shared by the deterministic DeepWiki adapter.

    Attributes:
        litellm_mcp_url: Fixed LiteLLM Streamable HTTP endpoint ending in
            ``/mcp``.
        litellm_virtual_key: Internal LiteLLM key restricted to the DeepWiki
            MCP server. This value must never be logged or returned.
        deepwiki_repository: One deployment-approved GitHub repository in
            ``owner/repository`` form.
    """

    litellm_mcp_url: str
    litellm_virtual_key: str
    deepwiki_repository: str

    @classmethod
    def from_env(cls, environ: Mapping[str, str] | None = None) -> Settings:
        """Load, validate, and return fail-closed deployment configuration.

        Args:
            environ: Optional mapping supplied by tests. When omitted, values
                come from the current process environment.

        Returns:
            A validated, immutable settings object.

        Raises:
            SettingsError: A required value is absent, the endpoint is unsafe,
                or the repository does not use ``owner/repository`` form.
                Error messages never include configuration values.
        """
        values = os.environ if environ is None else environ

        # Stage 1: Check all required names together so an operator receives one
        # actionable startup error without any secret values being displayed.
        required = ("LITELLM_MCP_URL", "LITELLM_VIRTUAL_KEY", "DEEPWIKI_REPOSITORY")
        missing = [name for name in required if not values.get(name)]
        if missing:
            raise SettingsError(
                f"Missing required configuration: {', '.join(sorted(missing))}"
            )

        url = values["LITELLM_MCP_URL"]
        virtual_key = values["LITELLM_VIRTUAL_KEY"]
        repository = values["DEEPWIKI_REPOSITORY"]

        # Stage 2: Restrict the network destination to an HTTPS MCP endpoint.
        # Local HTTP is allowed only for loopback development and tests.
        if url != url.strip():
            raise SettingsError("LITELLM_MCP_URL must not contain outer whitespace")
        parsed_url = urlsplit(url)
        is_local_http = parsed_url.scheme == "http" and parsed_url.hostname in {
            "127.0.0.1",
            "localhost",
        }
        if parsed_url.scheme != "https" and not is_local_http:
            raise SettingsError("LITELLM_MCP_URL must use HTTPS")
        if (
            not parsed_url.hostname
            or parsed_url.username
            or parsed_url.password
            or parsed_url.query
            or parsed_url.fragment
            or parsed_url.path.rstrip("/") != "/mcp"
        ):
            raise SettingsError("LITELLM_MCP_URL must be an origin plus the /mcp path")

        # Stage 3: Validate shape without revealing or transforming the key.
        # The repository is fixed here so request data cannot redirect DeepWiki.
        if virtual_key != virtual_key.strip():
            raise SettingsError("LITELLM_VIRTUAL_KEY must not contain outer whitespace")
        if not _REPOSITORY_PATTERN.fullmatch(repository):
            raise SettingsError("DEEPWIKI_REPOSITORY must use owner/repository format")

        return cls(
            litellm_mcp_url=url,
            litellm_virtual_key=virtual_key,
            deepwiki_repository=repository,
        )
