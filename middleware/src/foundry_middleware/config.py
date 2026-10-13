from functools import cached_property

from pydantic import AnyHttpUrl, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime-only configuration loaded from MIDDLEWARE_* environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MIDDLEWARE_",
        extra="ignore",
    )

    tenant_id: str = Field(min_length=36, max_length=36)
    client_id: str = Field(min_length=36, max_length=36)
    client_secret: SecretStr
    audience: str | None = None
    required_scope: str = "access_as_user"
    downstream_scope: str
    foundry_responses_endpoint: AnyHttpUrl
    foundry_scope: str = "https://ai.azure.com/.default"
    request_timeout_seconds: float = Field(default=60.0, gt=0, le=300)
    jwks_cache_seconds: int = Field(default=3600, ge=60, le=86400)
    clock_skew_seconds: int = Field(default=60, ge=0, le=300)

    @field_validator("tenant_id", "client_id")
    @classmethod
    def normalize_identifier(cls, value: str) -> str:
        return value.lower()

    @field_validator("required_scope", "downstream_scope", "foundry_scope")
    @classmethod
    def reject_blank_value(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must not be blank")
        return value

    @cached_property
    def expected_audience(self) -> str:
        # Microsoft Entra v2 access tokens use the API application's client ID as aud.
        return self.audience or self.client_id

    @cached_property
    def authority(self) -> str:
        """Tenant-specific authority used by MSAL for the OBO exchange."""
        return f"https://login.microsoftonline.com/{self.tenant_id}"

    @cached_property
    def issuer(self) -> str:
        """Exact issuer accepted when validating incoming v2 access tokens."""
        return f"{self.authority}/v2.0"

    @cached_property
    def openid_configuration_url(self) -> str:
        """Discovery document that points to Entra's current public signing keys."""
        return f"{self.issuer}/.well-known/openid-configuration"
