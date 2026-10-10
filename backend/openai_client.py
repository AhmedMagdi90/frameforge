import base64
import io
import json
import secrets
import time
from urllib.parse import quote_plus, urlencode, urlparse

import httpx
import jwt
from PIL import Image

from .models import PlanRequest, VideoPlan
from .settings import Settings
from .store import challenge, digest

ISSUER = "https://auth.openai.com"


class ServiceError(RuntimeError):
    """A safe, user-facing error; never includes a credential or provider body."""


class OpenAIIdentity:
    def __init__(self, settings: Settings, http: httpx.AsyncClient):
        self.settings, self.http = settings, http
        self._configuration = None
        self._keys = None
        self._keys_expires = 0

    async def configuration(self):
        if self._configuration is None:
            try:
                response = await self.http.get(ISSUER + "/.well-known/openid-configuration", timeout=20)
                response.raise_for_status()
                value = response.json()
                if value.get("issuer") != ISSUER:
                    raise ValueError("Wrong issuer")
                for key in ("authorization_endpoint", "token_endpoint", "jwks_uri"):
                    parsed = urlparse(value[key])
                    if parsed.scheme != "https" or parsed.hostname != "auth.openai.com" or parsed.username:
                        raise ValueError("Unexpected identity endpoint")
                self._configuration = value
            except (httpx.HTTPError, ValueError, KeyError):
                raise ServiceError("Could not reach ChatGPT sign-in. Please try again later.") from None
        return self._configuration

    async def authorize_url(self, transaction: dict):
        config = await self.configuration()
        return config["authorization_endpoint"] + "?" + urlencode({
            "client_id": self.settings.client_id, "redirect_uri": self.settings.callback_url,
            "response_type": "code", "scope": "openid profile email",
            "state": transaction["state"], "nonce": transaction["nonce"],
            "code_challenge_method": "S256", "code_challenge": challenge(transaction["verifier"]),
        })

    async def _jwks(self, refresh=False):
        config = await self.configuration()
        if refresh or self._keys is None or self._keys_expires < time.time():
            response = await self.http.get(config["jwks_uri"], timeout=20)
            response.raise_for_status()
            self._keys = response.json()["keys"]
            self._keys_expires = time.time() + 3600
        return self._keys

    async def verify_id_token(self, token: str, nonce: str):
        try:
            header = jwt.get_unverified_header(token)
            algorithm = header.get("alg")
            if algorithm not in {"RS256", "ES256"} or not isinstance(header.get("kid"), str):
                raise ValueError("Unsupported signature")
            keys = await self._jwks()
            matching = [key for key in keys if key.get("kid") == header["kid"]]
            if not matching:
                matching = [key for key in await self._jwks(refresh=True) if key.get("kid") == header["kid"]]
            if len(matching) != 1:
                raise ValueError("Unknown signing key")
            key = jwt.PyJWK.from_dict(matching[0], algorithm=algorithm).key
            claims = jwt.decode(token, key, algorithms=[algorithm], audience=self.settings.client_id,
                issuer=ISSUER, leeway=30, options={"require": ["exp", "iat", "iss", "aud", "sub", "nonce"]})
            if not isinstance(claims["nonce"], str) or not secrets.compare_digest(claims["nonce"], nonce):
                raise ValueError("Unexpected nonce")
            if not isinstance(claims["sub"], str) or not claims["sub"]:
                raise ValueError("Missing identity")
            audience = claims["aud"]
            if ("azp" in claims and claims["azp"] != self.settings.client_id) or (
                    isinstance(audience, list) and len(audience) > 1 and claims.get("azp") != self.settings.client_id):
                raise ValueError("Unexpected authorized party")
            return {
                "id": digest(ISSUER + "|" + claims["sub"]),
                "name": str(claims.get("name") or "ChatGPT user")[:100],
                "email": str(claims["email"])[:200] if claims.get("email_verified") is True and claims.get("email") else None,
            }
        except (httpx.HTTPError, jwt.PyJWTError, ValueError, KeyError, TypeError):
            raise ServiceError("Your ChatGPT sign-in could not be verified. Please sign in again.") from None

    async def identity_for_code(self, code: str, transaction: dict):
        config = await self.configuration()
        auth = None
        if self.settings.token_auth_method == "client_secret_basic":
            auth = httpx.BasicAuth(quote_plus(self.settings.client_id), quote_plus(self.settings.client_secret))
        try:
            response = await self.http.post(config["token_endpoint"], data={
                "grant_type": "authorization_code", "code": code,
                "client_id": self.settings.client_id, "redirect_uri": self.settings.callback_url,
                "code_verifier": transaction["verifier"],
            }, auth=auth, timeout=20)
            response.raise_for_status()
            token = response.json()["id_token"]
            if not isinstance(token, str):
                raise ValueError("Invalid ID token")
        except (httpx.HTTPError, KeyError, ValueError):
            raise ServiceError("ChatGPT sign-in did not complete. Please try again.") from None
        return await self.verify_id_token(token, transaction["nonce"])


class OpenAIContent:
    def __init__(self, settings: Settings, http: httpx.AsyncClient):
        self.settings, self.http = settings, http

    async def _request(self, path: str, body: dict, timeout=90):
        if not self.settings.api_key:
            raise ServiceError("AI generation is not configured for this service yet.")
        try:
            response = await self.http.post("https://api.openai.com/v1/" + path,
                headers={"Authorization": "Bearer " + self.settings.api_key}, json=body, timeout=timeout)
            if response.status_code == 429:
                raise ServiceError("The AI service reached a usage or rate limit. Try again later.")
            if response.status_code in {401, 403}:
                raise ServiceError("The AI service needs valid API access for this model. Contact its administrator.")
            if response.status_code >= 400:
                raise ServiceError("The AI service could not complete this request. Try a different idea or try again later.")
            return response
        except httpx.HTTPError:
            raise ServiceError("The AI service could not be reached. Please try again later.") from None

    async def plan(self, request: PlanRequest) -> VideoPlan:
        scene_count = {15: 2, 30: 4, 60: 6}[request.seconds]
        instruction = (
            "You are FrameForge's video director. Turn the user's conversation into a coherent, editable "
            "narrated IMAGE video storyboard. These are still images with slow camera motion, not generated moving footage. "
            "Use the user's language for narration/captions/title. Keep the visual style consistent. "
            "Each image_prompt describes one scene without printed words, plus character/style continuity. "
            "Use concise natural narration (roughly two words per requested second), and a short readable caption. "
            "Treat previous assistant plans as drafts and incorporate the latest changes. "
            f"Use exactly {scene_count} scenes, ratio {request.ratio}, targeting about {request.seconds} seconds overall. "
            "Never claim assets have already been generated. Return only the requested structured plan."
        )
        response = await self._request("responses", {
            "model": self.settings.text_model, "store": False,
            "input": [{"role": "developer", "content": instruction}] + [message.model_dump() for message in request.messages],
            "text": {"format": {"type": "json_schema", "name": "video_plan", "strict": True,
                "schema": VideoPlan.model_json_schema()}},
        })
        try:
            data = response.json()
            if data.get("status") != "completed":
                raise ValueError("Incomplete response")
            text = "".join(content["text"] for item in data["output"] for content in item.get("content", [])
                if content.get("type") == "output_text")
            plan = VideoPlan.model_validate(json.loads(text))
            return plan.model_copy(update={"ratio": request.ratio})
        except (ValueError, KeyError, TypeError):
            raise ServiceError("The idea could not be turned into a valid scene plan. Please rephrase it.") from None

    async def image(self, prompt: str, ratio: str) -> bytes:
        response = await self._request("images/generations", {
            "model": self.settings.image_model, "prompt": prompt, "n": 1,
            "size": {"portrait": "1024x1536", "landscape": "1536x1024", "square": "1024x1024"}[ratio],
            "quality": "medium", "output_format": "png", "background": "opaque",
        }, timeout=240)
        try:
            encoded = response.json()["data"][0]["b64_json"]
            if not isinstance(encoded, str) or len(encoded) > 70_000_000:
                raise ValueError("Image too large")
            data = base64.b64decode(encoded, validate=True)
            with Image.open(io.BytesIO(data)) as image:
                if image.width * image.height > 16_000_000 or image.width <= 0 or image.height <= 0:
                    raise ValueError("Invalid image size")
                output = io.BytesIO()
                image.convert("RGB").save(output, format="PNG")
                return output.getvalue()
        except (ValueError, KeyError, IndexError, TypeError, OSError, Image.DecompressionBombError):
            raise ServiceError("A generated scene image could not be read. Please retry generation.") from None

    async def speech(self, narration: str, voice: str) -> bytes:
        response = await self._request("audio/speech", {
            "model": self.settings.speech_model, "input": narration, "voice": voice,
            "instructions": "Narrate naturally and clearly in the text's language. Do not add words.",
            "response_format": "wav",
        })
        data = response.content
        if len(data) > 20_000_000 or len(data) < 44 or data[:4] != b"RIFF":
            raise ServiceError("The AI-generated voice could not be read. Please retry generation.")
        return data
