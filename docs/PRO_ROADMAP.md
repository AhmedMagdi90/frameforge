# Pro release scope and remaining work

Version 0.6 adds ChatGPT identity sign-in, conversational scene plans and AI image/narration videos on top of the pro editing foundation. It does not claim feature parity with CapCut Pro or production readiness.

## Implemented source

Core clip editing, speed, filters, original clip volume, a soundtrack plus seven independently timed audio layers with trim/loop/fades/mute, imported voice/effects, audio duplication, timed text/captions, source-timed motion keyframes, framing/mirror/rotation, image overlays, frame-grid stepping, millisecond video/audio time entry, clip-cut snapping, undo/redo, local drafts and native export. Voice audio imports an existing recording; microphone recording is not implemented. The caption studio imports subtitles or accepts manual captions; it does not transcribe speech. The motion preset applies a slow zoom; it is not a template marketplace. Image overlays are static raster assets; additional video tracks are not implemented.

## Release gates

AI studio source is included: supported registered ChatGPT identity sign-in, structured idea refinement, editable storyboards, AI image/speech generation, server-rendered MP4s, authenticated account history and editable project import. It needs server credentials and eligible OAuth registration; outputs use still images with camera motion. See `AI_SETUP.md`.

1. Compile both native engines and pass `flutter analyze` and `flutter test` using the pinned baseline.
2. Complete the Android/iPhone matrix in `DEVICE_CHECKLIST.md`, including motion orientation, audio alignment, exported caption timing, memory and cancellation.
3. Measure real encoder capabilities and replace generic 4K/60 fps options with device-aware availability if needed. Verify SDR color matching across Flutter, Media3 and Core Image with reference footage.
4. Add UI/accessibility tests, screen-reader labels, localization, storage management and a project backup/restore format before wider use.
5. Configure release signing, unique application IDs, icons, privacy/store metadata and distribution. No store submission or publication is performed by this source package.
6. Obtain eligible OpenAI OAuth registration, deploy the HTTPS AI backend, configure model access/budgets and verify a real account login and full generation on Android/iOS. Define privacy/retention/deletion, monitor costs and add a durable distributed queue if scaling beyond one service process.

## Additional CapCut-style development

| Area | Remaining capabilities |
| --- | --- |
| Timeline | Multiple video tracks, waveform and thumbnail strips, drag editing of audio lanes, layer snapping, frame ruler, grouped edits |
| Effects | Masks, chroma key, blend modes, stabilization, denoise, adjustment curves and LUT import |
| Motion | Variable speed ramps, reverse playback, easing curves, object tracking and optical flow |
| Captions and AI | Transcription, translation, background removal, enhancement, moving AI footage, regenerated scene narration and provider selection |
| Creative library | Licensed fonts/music/stickers, reusable templates, searchable asset catalog |
| Audio | Microphone recording, crossfades, ducking, sound effect catalog, equalizer and loudness tools |
| Export and reliability | Capability detection, background export, bitrate/codec controls, crash recovery, project backups |
| Product | Localization, accessibility, onboarding, subscriptions, entitlements and collaboration/cloud sync |

AI studio source is included, with external credentials/deployment still required. Licensed catalogs need permitted assets. Subscriptions need a business model and store configuration. These are future product decisions.
