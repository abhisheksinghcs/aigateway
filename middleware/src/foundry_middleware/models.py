from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class CreateResponseRequest(BaseModel):
    """Safe subset of the hosted-agent Responses request accepted by the POC."""

    model_config = ConfigDict(extra="forbid")

    input: str = Field(min_length=1, max_length=32768)
    stream: Literal[False] = False
    background: Literal[False] = False
    store: Literal[False] = False
