"""Verify hosted-agent deployment configuration fails closed."""

import pytest

from config import Settings, SettingsError

VALID_ENV = {
    "LITELLM_MCP_URL": "https://gateway.example.com/mcp",
    "LITELLM_VIRTUAL_KEY": "sk-restricted",
    "DEEPWIKI_REPOSITORY": "microsoft/semantic-kernel",
}


def test_settings_load_valid_fixed_configuration() -> None:
    """Prove valid deployment-controlled settings load unchanged."""
    settings = Settings.from_env(VALID_ENV)

    assert settings.litellm_mcp_url == "https://gateway.example.com/mcp"
    assert settings.deepwiki_repository == "microsoft/semantic-kernel"


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("LITELLM_MCP_URL", "http://gateway.example.com/mcp"),
        ("LITELLM_MCP_URL", "https://gateway.example.com/other"),
        ("LITELLM_MCP_URL", "https://user:password@gateway.example.com/mcp"),
        ("DEEPWIKI_REPOSITORY", "not-a-repository"),
        ("DEEPWIKI_REPOSITORY", "../other/repository"),
    ],
)
def test_settings_reject_unsafe_configuration(name: str, value: str) -> None:
    """Prove unsafe endpoints and repository shapes fail startup validation."""
    values = VALID_ENV | {name: value}

    with pytest.raises(SettingsError):
        Settings.from_env(values)


def test_settings_error_does_not_include_virtual_key() -> None:
    """Prove a separate validation failure cannot disclose the virtual key."""
    secret = "sk-do-not-display"
    values = VALID_ENV | {
        "LITELLM_VIRTUAL_KEY": secret,
        "DEEPWIKI_REPOSITORY": "invalid",
    }

    with pytest.raises(SettingsError) as error:
        Settings.from_env(values)

    assert secret not in str(error.value)
