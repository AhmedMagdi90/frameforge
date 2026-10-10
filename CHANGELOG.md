# 0.6.0 — ChatGPT sign-in and AI video studio

- Added an AI studio entry, external-browser ChatGPT identity login, secure app sessions, idea refinement, editable scene plans and voice/aspect/duration controls.
- Added a server-only OpenAI integration for structured storyboards, images and AI speech, with FFmpeg camera motion, timed captions and H.264/AAC MP4 assembly.
- Added persistent account-owned generation jobs, progress, cancellation, history, quotas, idempotent submission and authenticated streaming downloads.
- Added completed-video import as narrated scene clips plus editable caption layers. The complete MP4 is retained in exports; incomplete imports are removed atomically.
- Added verified OIDC signatures/issuer/audience/expiry/nonce, browser state binding and PKCE for both provider authorization and the one-use mobile handoff. OpenAI secrets stay on the server.
- Added Android release Internet permission and OAuth callback setup, iOS URL scheme registration, deployment examples and backend CI checks.
- Documented current OpenAI sign-in eligibility, separate API billing, the retired Sora API and remaining deployment/device requirements.

Backend and installer tests passed with local test media and mocked provider calls. Live OpenAI login/generation, Flutter tests and mobile builds remain unverified. This source milestone does not provide a deployed AI service or imply ChatGPT subscription coverage.

# 0.5.0 — Multiple audio layers

- Added a soundtrack plus seven additional music, imported voice or sound effect layers. Each has independent source trim, timeline placement, looping, volume, mute and overall fades.
- Added an audio mixer with editing, replacement, duplicate-at-playhead and removal. Replacing audio preserves placement, loop, gain, mute and fades while resetting the source section.
- Added proportional audio timeline lanes with mute/edit controls and exact millisecond source in/out/start entry.
- Added coalesced multi-player preview, concurrent source loading, stale-source guards, disposal and isolation of unreadable layers.
- Composed separate audio sequences/tracks in Android and iOS export. Muted/inactive assets are excluded; composition is bounded to 2,000 intervals per source and 4,000 total.
- Added schema 5 with relative paths for additional audio assets and compatibility with schemas 1–4. Layer edits, mute and duplicates support undo/redo.
- Added model, persistence, preview synchronization, widget input and export contract regression cases.

Source milestone only. Flutter tests, native compilation and device exports remain unverified in this environment.

# 0.4.0 — Audio editing and timeline precision

- Added original clip volume from 0–100%, independently of mute, retained across split/duplicate/undo.
- Added soundtrack source trimming, timeline placement, loop/single-play controls and up to 10-second fade settings. Fades span the overall audible window and shorten to half that window as needed.
- Added native audio inspection at import and lazy inspection for legacy music assets.
- Added a common music interval plan used by Android and iOS exports. Android uses audio gaps and per-frame PCM gain; iOS inserts the same source intervals and applies audio mix ramps.
- Updated preview for clipped music, normal-speed music looping, placement, fades and original clip volume. Audio synchronization coalesces pending updates.
- Added millisecond time entry, drift-free steps on a 24/30/60 fps grid, optional clipping-boundary snapping and a saved default export frame rate.
- Fixed paused seeks being skipped by the old playback drift threshold and prevented a cancelled metadata inspection from starting export afterward.
- Added schema 4 with schema 1–3 loading compatibility and new audio/timeline/export regression cases.

Installer/structural checks passed. Dart tests, native compilation, playback and exports remain unverified without a Flutter/mobile build environment.

# 0.3.0 — Pro editing foundation

- Added source-timed motion keyframes with linear interpolation, zoom, pan, rotation, mirror and fit/fill framing. Splits, trims and speed changes retain their motion.
- Added a slow zoom motion preset and a keyframe editor with a framing thumbnail.
- Added up to 20 timed PNG/JPEG/WebP image overlays with position, width, rotation and opacity, including preview and native export rendering. Imported assets are normalized to PNG with a maximum 2048-pixel edge.
- Added an offline caption studio: SRT/WebVTT import, manual caption editing, individual timing and SRT sharing. Import replaces caption layers in a single undoable operation and preserves ordinary titles.
- Added 2160p/4K and 24/30/60 fps export targets. Hardware support and source frame rate constrain actual output.
- Added schema 3 persistence with schema 1/2 compatibility and relative overlay asset paths.
- Added motion/caption/persistence/export regression coverage and Android/iOS CI build definitions.

This is a pro-feature source milestone. CI has not run here, and compilation, export fidelity, device performance and store readiness remain unverified.

# 0.2.0

- Added eight per-clip playback speeds from 0.25× to 4×.
- Added six linear-RGB filter presets with adjustable intensity.
- Updated source/timeline mapping, splitting, duration display and playhead anchoring for speed changes.
- Added speed/filter persistence with backward-compatible loading of version 1 drafts.
- Added speed and color processing to Android Media3 exports.
- Added an iOS Core Image compositor for frame orientation, filters, fades and timed text, plus retimed AVFoundation audio/video tracks.
- Added regression tests for the new editing rules and native export arguments.

Flutter analysis, Dart tests and device exports still require a Flutter installation and mobile build tools. Source and installer checks are recorded in the README.

# 0.1.0

- Added the project library, local media import, core timeline editing, preview, music, text, fades and native export source.
