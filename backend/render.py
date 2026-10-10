import asyncio
import json
import math
from pathlib import Path
import shutil

from .openai_client import ServiceError


class Renderer:
    def __init__(self, dimensions=None):
        self.dimensions = dimensions or {"portrait": (720, 1280), "landscape": (1280, 720), "square": (720, 720)}

    @property
    def available(self):
        return bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))

    async def run(self, *arguments, cwd=None):
        process = await asyncio.create_subprocess_exec(*arguments, cwd=cwd,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        except (asyncio.CancelledError, TimeoutError):
            if process.returncode is None:
                process.terminate()
                try:
                    await asyncio.wait_for(process.communicate(), 5)
                except TimeoutError:
                    process.kill()
                    await process.communicate()
            raise
        if process.returncode:
            raise ServiceError("Video rendering failed. The AI service administrator can check its FFmpeg configuration.")
        return stdout

    async def duration_ms(self, path: Path):
        output = await self.run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path))
        try:
            seconds = float(json.loads(output)["format"]["duration"])
            if not math.isfinite(seconds) or seconds <= 0 or seconds > 240:
                raise ValueError("Invalid duration")
            return round(seconds * 1000)
        except (KeyError, ValueError, TypeError):
            raise ServiceError("Generated media duration could not be read.") from None

    async def scene(self, image: Path, audio: Path, seconds: int, ratio: str, output: Path):
        voice_duration = await self.duration_ms(audio)
        if voice_duration > 30_000:
            raise ServiceError("A scene's narration is too long. Shorten its script and generate again.")
        frames = math.ceil(max(seconds * 1000, voice_duration + 250) / 1000 * 30)
        width, height = self.dimensions[ratio]
        video_filter = (
            f"scale={width * 2}:{height * 2}:force_original_aspect_ratio=increase,crop={width * 2}:{height * 2},"
            f"zoompan=z='min(zoom+0.0007,1.12)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d={frames}:s={width}x{height}:fps=30,format=yuv420p"
        )
        await self.run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(image), "-i", str(audio),
            "-vf", video_filter, "-af", "apad", "-t", f"{frames / 30:.6f}", "-threads", "2",
            "-c:v", "libx264", "-preset", "fast", "-crf", "21", "-c:a", "aac", "-b:a", "128k",
            "-ar", "48000", "-ac", "2", "-movflags", "+faststart", str(output))
        return await self.duration_ms(output)

    @staticmethod
    def timecode(milliseconds):
        seconds, fraction = divmod(milliseconds, 1000)
        minutes, seconds = divmod(seconds, 60)
        hours, minutes = divmod(minutes, 60)
        return f"{hours:02}:{minutes:02}:{seconds:02},{fraction:03}"

    async def assemble(self, directory: Path, scenes: list[dict]):
        # Names come only from the worker, never from user text or an HTTP filename.
        (directory / "concat.txt").write_text("".join(f"file '{scene['filename']}'\n" for scene in scenes))
        position = 0
        captions = []
        for index, scene in enumerate(scenes, 1):
            end = position + scene["duration_ms"]
            text = scene["caption"].replace("\r", "").replace("\n\n", "\n")
            captions.append(f"{index}\n{self.timecode(position)} --> {self.timecode(end)}\n{text}\n")
            position = end
        (directory / "captions.srt").write_text("\n".join(captions), encoding="utf-8")
        await self.run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "1",
            "-i", "concat.txt", "-vf", "subtitles=captions.srt:force_style='FontName=DejaVu Sans,FontSize=18,Outline=2,MarginV=30'",
            "-threads", "2", "-c:v", "libx264", "-preset", "fast", "-crf", "21", "-c:a", "aac", "-b:a", "128k",
            "-metadata", "comment=AI-generated images and voice. Created with FrameForge.",
            "-movflags", "+faststart", "video.mp4", cwd=directory)
        return await self.duration_ms(directory / "video.mp4")
