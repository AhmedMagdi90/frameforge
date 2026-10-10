from typing import Literal
from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Scene(StrictModel):
    image_prompt: str = Field(min_length=10, max_length=2500)
    narration: str = Field(min_length=1, max_length=500)
    caption: str = Field(min_length=1, max_length=250)
    seconds: int = Field(ge=2, le=20)


class VideoPlan(StrictModel):
    title: str = Field(min_length=1, max_length=80)
    summary: str = Field(min_length=1, max_length=600)
    ratio: Literal["portrait", "landscape", "square"]
    scenes: list[Scene] = Field(min_length=2, max_length=6)


class ChatMessage(StrictModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=7000)


class PlanRequest(StrictModel):
    messages: list[ChatMessage] = Field(min_length=1, max_length=12)
    ratio: Literal["portrait", "landscape", "square"] = "portrait"
    seconds: Literal[15, 30, 60] = 30


class GenerationRequest(StrictModel):
    plan: VideoPlan
    request_key: str = Field(pattern=r"^[A-Za-z0-9_-]{20,100}$")
    voice: Literal["coral", "alloy", "nova", "sage", "shimmer"] = "coral"


class SessionExchange(StrictModel):
    code: str = Field(pattern=r"^[A-Za-z0-9_-]{30,100}$")
    verifier: str = Field(pattern=r"^[A-Za-z0-9_-]{43,128}$")
