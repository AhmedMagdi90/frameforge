# Version 0.6 validation report

Date: 2026-10-10. Environment: Linux with Python 3.12 and FFmpeg/FFprobe, without Flutter, Dart, Android SDK or Xcode. No OpenAI credentials or eligible client registration were present.

| Check | Result |
| --- | --- |
| Backend unittest suite | 26 passed; no external API calls or charges |
| Real FFmpeg pipeline | Passed for portrait, landscape and square using local test PNG/WAV inputs; H.264/AAC, 30 fps, durations, captions and disclosure metadata verified |
| API-to-MP4 workflow | Passed: app-session exchange, scene plan, job submission, real render, status and authenticated MP4 download with fake provider inputs |
| Identity verification | Local RSA-signed token tests passed for signature, issuer, audience, expiry, issued-at, nonce and authorized party |
| OAuth/session boundaries | Mocked provider flow, browser state/cookie, one-use handoff, device PKCE, token hashing, expiry/logout and replay tests passed |
| Account/job boundaries | Ownership, quotas, idempotency, cancellation, interrupted-job cleanup, asset whitelist and response-header tests passed |
| Provider request contract | Mocked Responses/Images/Speech requests, structured plans, binary validation and safe errors passed |
| Python runner installer tests | 2 passed; repeatability, retained settings, Internet permission and mobile OAuth registration checked |
| Python compilation | Passed |
| Bash setup syntax | Passed |
| YAML parsing | Passed for pubspec, analysis options and CI workflow |
| Relative Dart imports/exports | All local targets present |
| Lexical delimiter checks | Passed across 51 Dart/Kotlin/Swift source files |
| Flutter analyzer | Not run: SDK unavailable |
| Dart regression tests | 100 authored cases; not run: SDK unavailable |
| Real ChatGPT identity login | Not run: registered OAuth client unavailable |
| Live text/image/speech generation | Not run: API credentials unavailable |
| Public deployment / container build | Not performed |
| Android/iOS/backend CI | Defined; not executed |
| APK/IPA/native compilation | Not run |
| UI/device/native exports | Not run |

Backend pipeline tests render at reduced dimensions to keep regression runs quick. They establish the tested rendering contracts with synthetic local media, not model quality, full-resolution performance or live provider compatibility. Captions are written to SRT and rendered through FFmpeg's subtitles filter; text rasterization and supported languages still require visual/device review.

Structural checks do not establish Dart/Kotlin/Swift language/API correctness, mobile callback behavior, render fidelity or runtime behavior. This report does not certify a production release.

Run `bash tool/setup.sh`, `flutter analyze`, `flutter test` and platform builds in a Flutter environment. Complete `DEVICE_CHECKLIST.md`. Configure `AI_SETUP.md` credentials and deployment, then test actual ChatGPT sign-in, secure storage, paid model access, generation, resuming jobs and importing outputs on both mobile platforms.
