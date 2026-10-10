from contextlib import asynccontextmanager
import asyncio
import re
import shutil
from urllib.parse import urlencode, urlparse

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse, StreamingResponse
import httpx

from .jobs import Jobs
from .models import GenerationRequest, PlanRequest, SessionExchange
from .openai_client import OpenAIContent, OpenAIIdentity, ServiceError
from .render import Renderer
from .settings import Settings
from .store import Store


def public_job(job):
    return {key: job[key] for key in ("id", "status", "progress", "message", "manifest", "error", "created")} | {
        "plan": job["plan"]["plan"]}


def create_app(settings=None, *, content=None, identity=None, renderer=None):
    settings = settings or Settings.from_env()
    settings.validate()
    store = Store(settings.data_dir)
    http = httpx.AsyncClient(follow_redirects=False)
    identity = identity or OpenAIIdentity(settings, http)
    content = content or OpenAIContent(settings, http)
    renderer = renderer or Renderer()
    jobs = Jobs(store, settings.data_dir, content, renderer, settings.max_workers)

    @asynccontextmanager
    async def lifespan(app):
        for interrupted in store.recover_jobs():
            if re.fullmatch(r"[a-f0-9]{32}", interrupted):
                shutil.rmtree(settings.data_dir / "jobs" / interrupted, ignore_errors=True)
        yield
        await jobs.close()
        await http.aclose()

    app = FastAPI(title="FrameForge AI service", version="0.6.0", lifespan=lifespan)
    app.state.store, app.state.jobs, app.state.settings = store, jobs, settings

    @app.middleware("http")
    async def request_limits(request: Request, call_next):
        if request.method == "POST":
            try:
                length = int(request.headers.get("content-length", "-1"))
            except ValueError:
                return JSONResponse({"detail": "Invalid request length"}, status_code=400)
            if length < 0:
                return JSONResponse({"detail": "A request length is required"}, status_code=411)
            if length > 128_000:
                return JSONResponse({"detail": "This idea is too large"}, status_code=413)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.exception_handler(ServiceError)
    async def service_failure(request, error):
        return JSONResponse({"detail": str(error)}, status_code=502)

    async def session_token(request: Request):
        header = request.headers.get("authorization", "")
        if not header.startswith("Bearer ") or len(header) > 300:
            raise HTTPException(401, "Sign in to your account first.")
        return header[7:]

    async def current_user(token=Depends(session_token)):
        user = store.session(token)
        if user is None:
            raise HTTPException(401, "Your app session expired. Sign in again.")
        return user

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.get("/api/capabilities")
    async def capabilities():
        return {"sign_in_configured": bool(settings.client_id), "planning_configured": bool(settings.api_key),
            "generation_configured": bool(settings.api_key and renderer.available),
            "generation_mode": "narrated_images", "api_billing": "service_account", "ai_voice": True,
            "daily_video_limit": settings.daily_jobs, "max_scenes": 6}

    @app.get("/auth/openai/start")
    async def begin_sign_in(device_challenge: str, device_state: str):
        if not settings.client_id:
            raise HTTPException(503, "ChatGPT sign-in has not been configured for this AI service.")
        if not re.fullmatch(r"[A-Za-z0-9_-]{43}", device_challenge) or not re.fullmatch(r"[A-Za-z0-9_-]{20,100}", device_state):
            raise HTTPException(400, "Invalid sign-in request")
        transaction = store.new_transaction(device_challenge, device_state)
        response = RedirectResponse(await identity.authorize_url(transaction), status_code=303)
        response.set_cookie("ff_auth_tx", transaction["id"], max_age=600, httponly=True,
            secure=urlparse(settings.public_url).scheme == "https", samesite="lax", path="/auth/openai")
        return response

    @app.get("/auth/openai/callback")
    async def callback(request: Request, state: str = "", code: str = "", error: str = ""):
        try:
            transaction = store.take_transaction(request.cookies.get("ff_auth_tx", ""), state)
        except ValueError as exception:
            raise HTTPException(400, str(exception)) from None
        parameters = {"state": transaction["mobile_state"]}
        if error or not code:
            parameters["error"] = "access_denied"
        else:
            try:
                user = await identity.identity_for_code(code, transaction)
                parameters["code"] = store.new_ticket(user, transaction["mobile_challenge"])
            except ServiceError:
                parameters["error"] = "sign_in_failed"
        response = RedirectResponse("frameforge-ai://login?" + urlencode(parameters), status_code=303)
        response.delete_cookie("ff_auth_tx", path="/auth/openai")
        return response

    @app.post("/api/session/exchange")
    async def exchange(request: SessionExchange):
        try:
            token, user = store.exchange_ticket(request.code, request.verifier, settings.session_seconds)
        except ValueError as exception:
            raise HTTPException(400, str(exception)) from None
        return {"token": token, "user": user, "expires_in": settings.session_seconds}

    @app.get("/api/session")
    async def profile(user=Depends(current_user)):
        return {"user": user}

    @app.delete("/api/session")
    async def logout(token=Depends(session_token)):
        store.logout(token)
        return {"signed_out": True}

    @app.post("/api/ideas/plan")
    async def plan(request: PlanRequest, user=Depends(current_user)):
        if not settings.api_key:
            raise HTTPException(503, "Idea generation has not been configured for this service.")
        try:
            store.reserve_plan(user["id"], settings.hourly_plans)
        except ValueError as exception:
            raise HTTPException(429, str(exception)) from None
        return (await content.plan(request)).model_dump()

    @app.post("/api/jobs", status_code=202)
    async def generate(request: GenerationRequest, user=Depends(current_user)):
        if not settings.api_key or not renderer.available:
            raise HTTPException(503, "Video generation has not been configured for this service.")
        try:
            job, created = store.new_job(user["id"], request.request_key, request.model_dump(), settings.daily_jobs)
        except ValueError as exception:
            raise HTTPException(409, str(exception)) from None
        if created:
            jobs.start(job["id"], request)
        return public_job(job)

    @app.get("/api/jobs")
    async def recent_jobs(user=Depends(current_user)):
        return {"jobs": [public_job(job) for job in store.jobs(user["id"])]}

    def owned_job(job_id, user):
        job = store.job(job_id, user["id"])
        if job is None:
            raise HTTPException(404, "This video could not be found.")
        return job

    @app.get("/api/jobs/{job_id}")
    async def status(job_id: str, user=Depends(current_user)):
        return public_job(owned_job(job_id, user))

    @app.delete("/api/jobs/{job_id}")
    async def cancel(job_id: str, user=Depends(current_user)):
        job = owned_job(job_id, user)
        if job["status"] not in {"queued", "running"}:
            raise HTTPException(409, "This generation has already finished.")
        await jobs.cancel(job_id)
        return public_job(owned_job(job_id, user))

    @app.get("/api/jobs/{job_id}/assets/{filename}")
    async def download(job_id: str, filename: str, user=Depends(current_user)):
        job = owned_job(job_id, user)
        manifest = job["manifest"]
        if job["status"] != "completed" or not manifest:
            raise HTTPException(409, "The video is not ready to download.")
        allowed = {"video.mp4", "captions.srt", *(scene["filename"] for scene in manifest["scenes"])}
        if filename not in allowed:
            raise HTTPException(404, "This asset could not be found.")
        path = settings.data_dir / "jobs" / job_id / filename
        if not path.is_file():
            raise HTTPException(404, "This generated asset is no longer available.")
        async def chunks():
            # A bounded read per event-loop turn keeps downloads streaming without
            # loading a video into memory or using a framework worker for each chunk.
            with path.open("rb") as source:
                while chunk := source.read(64 * 1024):
                    yield chunk
                    await asyncio.sleep(0)
        return StreamingResponse(chunks(), media_type="video/mp4" if filename.endswith(".mp4") else "application/x-subrip",
            headers={"Content-Length": str(path.stat().st_size), "Content-Disposition": f'attachment; filename="{filename}"'})

    return app


app = create_app()
