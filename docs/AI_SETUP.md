# AI studio setup (version 0.6)

The mobile app offers ChatGPT identity sign-in, a conversational storyboard planner, AI image/speech generation, server-rendered MP4s, video history and import into editable local projects. The output uses still images with camera movement and synthetic narration. It does not generate moving subject footage or access a user's ChatGPT conversation history.

OpenAI documents [Sign in with ChatGPT](https://developers.openai.com/siwc), including the [registered website identity flow](https://developers.openai.com/siwc/website). As checked on October 10, 2026, website identity sign-in is available to selected commercial partners during a limited trial. Obtain an eligible registered client from OpenAI; this package cannot create that registration. A ChatGPT password or consumer subscription alone is insufficient to configure the service.

OpenAI's [deprecations page](https://developers.openai.com/api/docs/deprecations) lists the Sora/Videos API as retired on September 24, 2026. This implementation calls Responses, Images and Speech, then assembles a video with FFmpeg. It does not use the retired video endpoint.

## Credentials and billing

Configure these on the **server only** through your hosting secret manager or a private environment file:

- `OPENAI_CLIENT_ID`: the registered `oaiapp_...` identity client.
- `OPENAI_TOKEN_AUTH_METHOD`: the method assigned to that client (`none` or `client_secret_basic`). Set `OPENAI_CLIENT_SECRET` only if its registration requires it.
- `OPENAI_API_KEY`: a separate OpenAI API project key with access to your chosen text, image and speech models. Model access may require organization verification.
- `PUBLIC_URL`: the HTTPS origin where the service is deployed, for example `https://ai.yourdomain.com`.

Register this exact OpenAI redirect URL: `https://ai.yourdomain.com/auth/openai/callback`. The server completes OIDC verification and issues its own one-use login ticket, then redirects back to `frameforge-ai://login`. The native setup script registers that mobile callback scheme. The app uses the system browser, never an embedded password form.

All content requests use the server's API project, including text planning. They do **not** use ChatGPT subscription credits. See [ChatGPT and API billing](https://help.openai.com/en/articles/9039756-managing-billing-settings-on-the-chatgpt-web-and-api-platform). This identity-only mobile integration does not implement OpenAI's separate open-source loopback token-sharing flow.

Never put OpenAI keys or an OAuth client secret in Flutter, `--dart-define`, an APK, source control or a chat message. Only the service URL belongs in Flutter configuration. The app stores its opaque FrameForge session in secure device storage. The database stores hashes of app session tokens and mobile login tickets.

## Run the server

From the project root, with Python 3.12+, FFmpeg/FFprobe (including `libx264`, AAC, `zoompan` and `subtitles` filters) and DejaVu/Noto fonts installed:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
cp backend/.env.example backend/.env
# Edit backend/.env locally, then export its values through your shell or host.
uvicorn backend.app:app --host 0.0.0.0 --port 8000 --workers 1 --no-access-log
```

Uvicorn does not load that file automatically. A local `.env` loader or your host must supply the variables. Use your hosting secret manager in production. Run behind HTTPS with one ASGI worker, a persistent private `FRAMEFORGE_DATA_DIR` volume and sufficient disk space. Do not publicly expose the data directory. `/health` and `/api/capabilities` expose readiness flags, never secrets. Configure a reverse proxy to omit query strings from OAuth callback access logs and preserve `Content-Length` on API requests. The service rejects POST bodies larger than 128 KB.

An unexecuted container configuration is also supplied:

```bash
docker build -f backend/Dockerfile -t frameforge-ai .
docker run --env-file backend/.env -v frameforge-ai-data:/data -p 8000:8000 frameforge-ai
```

Place the container behind your HTTPS proxy. These deployment commands are examples; no container or public service was deployed in the creation workspace.

Default models, all configurable on the server, are `gpt-6.1-sol`, `gpt-image-2.5-sunburst` and `gpt-4o-mini-tts`. Verify access in your API project before enabling generation. Do not substitute a text model without checking structured-output support.

## Connect the mobile app

```bash
bash tool/setup.sh
flutter analyze
flutter test
flutter run --dart-define=FRAMEFORGE_AI_URL=https://ai.yourdomain.com
```

Alternatively open **Create with AI → Settings → Connect AI service** and enter the service's HTTPS origin. A configured release can use the build-time address without asking users to enter it. Internet permission is installed in the main Android manifest, including release builds. Android minSdk is 26; iOS minimum is 15. Use normal iOS signing and check secure-storage persistence on a real device. Android/iOS release builds require HTTPS. Loopback HTTP is allowed by source configuration for development; OS transport restrictions may still require development-only runner settings. Never enable blanket cleartext access in release builds.

Choose **Continue with ChatGPT**, describe an idea, select approximate duration and aspect ratio, then **Make scene plan**. Refine by sending another instruction or editing each scene. **Generate video** starts billable image/speech calls only after the explicit button press. The app discloses synthetic voice and API billing. A job continues on the server after leaving the screen. Return to history to resume it or download the finished result.

**Open in editor** downloads each uncaptioned scene MP4, inspects actual durations and adds editable caption layers. It also downloads the complete captioned MP4 into that project's exports. Open **Export → Recent exports** to share the original generated video immediately, or edit the scene project and export a new version. Narration is baked into each scene's audio track; it can be muted/adjusted with the existing clip audio controls. Regenerating narration after import is not implemented.

## Service operation and boundaries

- Identity is verified against OpenAI's signing keys, issuer, audience, expiry, issued-at time, nonce and stable subject. Browser state is bound to an expiring HttpOnly cookie. PKCE protects both OpenAI's authorization exchange and the one-use server-to-mobile handoff. No OpenAI access/refresh token is retained.
- Sessions last seven days. Sign out removes the local app session and attempts server revocation; it does not sign out the user globally from ChatGPT. Network failures retain a local session; an HTTP 401 removes it. Service switching removes the prior local session.
- The default per-account quotas are 30 planning attempts per rolling hour, ten generation jobs per rolling day and two active jobs. Failed/cancelled attempts count. Configure lower limits in `.env` if needed. Set project-level API budget alerts and spend controls on your OpenAI account; this app does not provide a payment or subscription system.
- Submission keys prevent duplicate jobs for the same account and payload after a network retry. Changing a draft constitutes a new generation. Paid content calls are not automatically retried. Cancellation stops future work and removes partial files; provider requests already started may still incur charges.
- Jobs run inside a single service process with bounded concurrency. Restarting marks unfinished jobs failed rather than silently repeating paid calls. Completed results survive restarts on a persistent volume. There is no distributed queue, background retry, automatic retention expiry or account-deletion endpoint yet.
- Stored plans contain prompts/narration; the server retains completed scene MP4s, captions and full MP4s. Intermediate source images/WAVs are removed after rendering; failed/cancelled job directories are removed. Define retention, privacy terms, user deletion/export and monitoring before public deployment. Database and asset backups must be protected as user data.
- Planning supports approximate 15/30/60-second videos with two to six scenes. Narration can extend actual duration. Images are cropped to the chosen canvas; generated output is 720p at 30 fps. Existing local editor export controls can produce other supported targets after import.
- AI can produce unsuitable or inaccurate content. Review a scene plan and finished video before sharing. Model safety refusals, insufficient credits and inaccessible models are reported as errors. No finished asset is simulated when generation fails.

## Validation

```bash
python3 -m unittest discover -s backend -t . -p 'test_*.py' -v
python3 -m unittest discover -s tool -p 'test_*.py' -v
```

Backend tests use local RSA-signed identity tokens, mocked provider responses and synthetic image/WAV media; FFmpeg actually renders H.264/AAC MP4s in all three canvas ratios. They do not log into a real account or spend API credits. Flutter tests, native callback behavior, release secure storage, live model access, deployment and a real idea-to-video run still require the configured environments listed above.
