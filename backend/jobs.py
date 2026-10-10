import asyncio
from pathlib import Path
import shutil

from .models import GenerationRequest
from .openai_client import OpenAIContent, ServiceError
from .render import Renderer
from .store import Store


class Jobs:
    def __init__(self, store: Store, data_dir: Path, content: OpenAIContent, renderer: Renderer, concurrency: int):
        self.store, self.data_dir, self.content, self.renderer = store, data_dir, content, renderer
        self.semaphore = asyncio.Semaphore(concurrency)
        self.tasks: dict[str, asyncio.Task] = {}

    def start(self, job_id: str, request: GenerationRequest):
        task = asyncio.create_task(self._generate(job_id, request))
        self.tasks[job_id] = task
        task.add_done_callback(lambda _: self.tasks.pop(job_id, None))

    async def _generate(self, job_id: str, request: GenerationRequest):
        directory = self.data_dir / "jobs" / job_id
        try:
            async with self.semaphore:
                directory.mkdir(parents=True, exist_ok=True, mode=0o700)
                self.store.update_job(job_id, status="running", message="Creating scene images and AI voice")
                scenes = []
                total = len(request.plan.scenes)
                for index, scene in enumerate(request.plan.scenes, 1):
                    self.store.update_job(job_id, progress=(index - 1) / total * .85, message=f"Creating scene {index} of {total}")
                    image_path, audio_path = directory / f"image{index:02}.png", directory / f"voice{index:02}.wav"
                    image_path.write_bytes(await self.content.image(scene.image_prompt, request.plan.ratio))
                    audio_path.write_bytes(await self.content.speech(scene.narration, request.voice))
                    filename = f"scene{index:02}.mp4"
                    duration = await self.renderer.scene(image_path, audio_path, scene.seconds, request.plan.ratio, directory / filename)
                    scenes.append({"filename": filename, "duration_ms": duration, "caption": scene.caption, "narration": scene.narration})
                    image_path.unlink(missing_ok=True); audio_path.unlink(missing_ok=True)
                self.store.update_job(job_id, progress=.9, message="Assembling the finished video")
                duration = await self.renderer.assemble(directory, scenes)
                manifest = {"title": request.plan.title, "ratio": request.plan.ratio, "scenes": scenes,
                    "video": "video.mp4", "subtitles": "captions.srt", "duration_ms": duration, "ai_voice": True}
                self.store.update_job(job_id, status="completed", progress=1, message="Your video is ready", manifest=manifest)
        except asyncio.CancelledError:
            self.store.update_job(job_id, status="cancelled", message="Generation cancelled")
            shutil.rmtree(directory, ignore_errors=True)
        except Exception as error:
            message = str(error) if isinstance(error, ServiceError) else "Video generation failed. Please retry or contact the AI service administrator."
            self.store.update_job(job_id, status="failed", error=message, message="Generation failed")
            shutil.rmtree(directory, ignore_errors=True)

    async def cancel(self, job_id: str):
        self.store.update_job(job_id, status="cancelled", message="Generation cancelled")
        task = self.tasks.get(job_id)
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        shutil.rmtree(self.data_dir / "jobs" / job_id, ignore_errors=True)

    async def close(self):
        pending = list(self.tasks.items())
        tasks = [task for _, task in pending]
        for job_id, _ in pending:
            self.store.update_job(job_id, status="failed", message="Generation interrupted",
                error="The AI service stopped. Create a new generation to retry.")
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        for job_id, _ in pending:
            job_directory = self.data_dir / "jobs" / job_id
            # A completion may have won the race with shutdown; preserve its assets.
            with self.store.connect() as db:
                row = db.execute("SELECT status FROM jobs WHERE id=?", (job_id,)).fetchone()
            if row is not None and row["status"] != "completed":
                shutil.rmtree(job_directory, ignore_errors=True)
