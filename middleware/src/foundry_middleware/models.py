"""Define the constrained public request models accepted by the middleware.

The models deliberately expose only the POC's supported response fields and
reject unknown options that could turn the service into an open proxy.
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class CreateResponseRequest(BaseModel):
    """Safe subset of the hosted-agent Responses request accepted by the POC."""

    # Reject fields such as a caller-selected endpoint, tool configuration, or model.
    model_config = ConfigDict(extra="forbid")

    # Bound input size limits request memory and prevents an accidental open proxy.
    input: str = Field(min_length=1, max_length=32768)
    # The first POC stays request-scoped: no streaming connection, background token
    # lifetime, or platform-managed storage.
    stream: Literal[False] = False
    background: Literal[False] = False
    store: Literal[False] = False
