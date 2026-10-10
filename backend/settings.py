from dataclasses import dataclass
import os
from pathlib import Path
from urllib.parse import urlparse


@dataclass(frozen=True)
class Settings:
    data_dir: Path = Path("/tmp/frameforge-ai")
    public_url: str = "http://127.0.0.1:8000"
    client_id: str = ""
    client_secret: str = ""
    token_auth_method: str = "none"
    api_key: str = ""
    text_model: str = "gpt-6.1-sol"
    image_model: str = "gpt-image-2.5-sunburst"
    speech_model: str = "gpt-4o-mini-tts"
    daily_jobs: int = 10
    hourly_plans: int = 30
    max_workers: int = 2
    session_seconds: int = 7 * 86400

    @property
    def callback_url(self) -> str:
        return self.public_url.rstrip("/") + "/auth/openai/callback"

    def validate(self) -> None:
        parsed = urlparse(self.public_url)
        local = parsed.hostname in {"127.0.0.1", "localhost", "::1"}
        if parsed.scheme != "https" and not (parsed.scheme == "http" and local):
            raise ValueError("PUBLIC_URL must use HTTPS, or loopback HTTP for development.")
        if not parsed.netloc or parsed.path not in {"", "/"} or parsed.query or parsed.fragment or parsed.username:
            raise ValueError("PUBLIC_URL must be an origin, without a path, credentials or query.")
        if self.token_auth_method not in {"none", "client_secret_basic"}:
            raise ValueError("Unsupported OpenAI token authentication method.")
        if self.token_auth_method == "client_secret_basic" and not self.client_secret:
            raise ValueError("This OAuth client requires OPENAI_CLIENT_SECRET.")
        if not 1 <= self.max_workers <= 4 or not 1 <= self.daily_jobs <= 100 or not 1 <= self.hourly_plans <= 100:
            raise ValueError("Invalid generation concurrency or quota.")

    @classmethod
    def from_env(cls):
        settings = cls(
            data_dir=Path(os.getenv("FRAMEFORGE_DATA_DIR", "/tmp/frameforge-ai")),
            public_url=os.getenv("PUBLIC_URL", "http://127.0.0.1:8000").rstrip("/"),
            client_id=os.getenv("OPENAI_CLIENT_ID", ""),
            client_secret=os.getenv("OPENAI_CLIENT_SECRET", ""),
            token_auth_method=os.getenv("OPENAI_TOKEN_AUTH_METHOD", "none"),
            api_key=os.getenv("OPENAI_API_KEY", ""),
            text_model=os.getenv("OPENAI_TEXT_MODEL", "gpt-6.1-sol"),
            image_model=os.getenv("OPENAI_IMAGE_MODEL", "gpt-image-2.5-sunburst"),
            speech_model=os.getenv("OPENAI_SPEECH_MODEL", "gpt-4o-mini-tts"),
            daily_jobs=int(os.getenv("DAILY_VIDEO_LIMIT", "10")),
            hourly_plans=int(os.getenv("HOURLY_PLAN_LIMIT", "30")),
            max_workers=int(os.getenv("GENERATION_WORKERS", "2")),
        )
        settings.validate()
        return settings
