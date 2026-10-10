# FrameForge

A Flutter video editor for Android and iOS, with original branding and a local project library. Version **0.6** adds an AI studio: ChatGPT identity sign-in, conversational scene planning, narrated image videos and editable generated projects. It retains multi-layer audio, motion keyframes, image overlays, captions and native export. This is **source code for build/device validation**, not a compiled or store-ready release.

## What is included

- Import multiple local videos; copy media into the project so picker caches can expire safely.
- Preview playback and scrub across clips, with optional snapping to clip boundaries.
- Enter a millisecond timecode or step on a 24/30/60 fps timeline grid. Save the grid rate as the default export target.
- Trim, split, delete, duplicate, mute and reorder clips.
- Set a clip's speed to 0.25×, 0.5×, 0.75×, 1×, 1.5×, 2×, 3× or 4×. Preview and export use the retimed duration, including original audio. Background music remains at normal speed.
- Apply Original, Mono, Warm, Cool, Sepia or Vivid looks with an intensity control. Filters affect the footage; text is added afterward.
- Set original clip volume separately from mute.
- Add music, trim its source section, place it at a timeline offset, loop it or play it once, adjust volume and fade its overall beginning/end.
- Combine a soundtrack with seven more music, imported voice or sound effect layers. Mute, replace, duplicate at the playhead or remove each additional layer, with undo/redo.
- Add timed text with color, size and vertical position controls.
- Import SRT/WebVTT captions, edit individual cues or write captions manually, replace/remove caption sets with undo, and share an SRT file. Captions can also be rendered into MP4 exports.
- Add motion keyframes for zoom, horizontal/vertical pan and clockwise rotation, with a slow zoom preset. Keyframes stay attached to source timestamps through trimming, splitting and speed changes.
- Fit footage inside the canvas or fill/crop it, and mirror each clip.
- Import up to 20 static image overlays, including transparent logos/stickers. Set timing, position, width, rotation and opacity. Images render above footage and below text.
- Cut or fade through black between clips, up to 300 ms on each side.
- Choose portrait 9:16, landscape 16:9 or square 1:1 framing.
- Undo/redo, rename projects, autosave, reopen drafts and delete projects.
- Native MP4 export with 720p, 1080p and 2160p/4K targets, 24/30/60 fps targets, progress, cancellation and the system share menu. Higher settings require compatible hardware.
- Reopen recent exports from the Export panel.
- Sign in with ChatGPT through a configured service, describe/refine an idea, review/edit a storyboard and generate AI images, narration and a captioned MP4.
- Resume server generation from account video history. Download scene clips into an editable project and retain the finished MP4 in recent exports.

Local editing works without an account or backend. The optional AI studio requires a deployed service, an eligible registered OpenAI sign-in client and server-side API credentials. Generation uses the server's API billing separately from ChatGPT subscriptions. It creates still-image scenes with camera motion. Read [AI setup](docs/AI_SETUP.md) for credentials, deployment and current OpenAI eligibility.

## Create a video from an idea

Open **Create with AI**, connect the configured service and choose **Continue with ChatGPT**. Describe your idea, select framing, voice and approximate duration, then **Make scene plan**. Refine with another instruction or edit a scene's visual description, narration and caption. **Generate video** explicitly starts image/speech requests. Follow progress or return later through video history.

When complete, **Open in editor** imports individual scene clips and editable captions, plus the finished captioned MP4. The original generated MP4 is available under **Export → Recent exports**. Narration remains in each scene's clip audio. Output from the service is 720p/30 fps; existing editing/export controls remain available after import. The source includes a FastAPI/FFmpeg backend, deployment examples, quotas, cancellation and authenticated downloads. No live AI service has been deployed or configured in this workspace.

## Use the pro controls

Open **Audio** after adding video to use the mixer. Add a soundtrack or up to seven additional music, voice or sound effect layers. Voice/effect imports start at the playhead and play once by default; additional music loops. Voice audio imports an existing recording; there is no microphone recorder in this version. Tap a layer to select its source section and video start position, choose looping or a single play, set volume/mute and adjust fades. Use **Set in time**, **Set out time** and **Set start time** for exact millisecond placement. The source section must be at least 100 ms.

Each layer's audible window ends at the video end, or at its section's end for single play. Fades apply across all repetitions and are each capped at half that window. Shortening the video leaves audio placement intact; audio entirely beyond the new end is silent and returns if the video grows or you Undo. Replacing audio keeps placement/loop/volume/mute/fades and resets its source section. Additional layers can be duplicated at the playhead without making another file copy. The timeline lanes show placement and duration; they are not waveform displays. Tap a lane to edit it or its speaker to mute. Scroll the lanes vertically when more than four are present.

**Volume** changes a selected clip's original sound; the clip **Mute** tool preserves that level for unmuting later. Audio layer mute works independently. An unreadable preview layer displays an audio warning while other layers and video can continue; replace/remove/mute it or reopen the project to retry. Export reports missing audible assets as an error.

Tap the displayed playhead time to enter seconds, `M:SS.mmm` or `H:MM:SS.mmm`. The arrows beside Play step through the chosen timeline frame grid without snapping. Choose 24/30/60 fps in the timeline header; Export starts with that target. The snapping control attracts scrubbing within 80 ms of clip cuts. The grid describes output time; displayed decoded frames depend on source rate, playback speed and the platform player, so it does not guarantee one distinct source frame per step.

Select a timeline clip and open **Motion**. Scrub the clip time, adjust zoom/pan/rotation to create a point, then move to another moment and adjust again. Motion interpolates linearly between points and holds its first/last values outside the keyed range. A single point sets a static transform. Fit/fill and mirror apply to the complete clip. The panel shows a thumbnail; the main editor previews the video after Apply.

Open **Overlay** to import a PNG, JPEG or WebP. The importer decodes the first image frame, preserves its aspect/transparency and writes a project PNG with a maximum 2048-pixel edge. Inputs are limited to 20 MB and 64 megapixels. Overlay order follows insertion order; text/captions stay above all images. Tap an image chip in the timeline to edit it.

Open **Captions** to import `.srt` or `.vtt`, write a cue, edit existing cues or share SRT. A valid import replaces only caption layers, preserving titles; Undo restores the previous set. Import accepts UTF-8 text, up to 500 in-range cues and 300 characters per cue, including emoji. Cues beyond the video are skipped/clamped. WebVTT cue settings and style markup are accepted but rendered as plain text with the app's position/style controls. This studio does not transcribe speech.

## Run the app

Install [Flutter](https://docs.flutter.dev/install) **3.35 or newer** with Dart 3.9+, Python 3, and the platform tools listed below. Flutter 3.35 is the baseline targeted by these runner templates.

```bash
cd frameforge
bash tool/setup.sh
flutter analyze
flutter test
flutter run
```

The setup script generates fresh Android/iOS runners in a temporary directory with `flutter create`, copies only the mobile platform directories, installs the native engines and fetches Dart packages. It preserves `lib/`, `test/` and `pubspec.yaml`. Run it again after changing native sources in `platform/`.

The included [CI workflow](.github/workflows/verify.yml) targets Flutter 3.35.7, analyzes/tests Dart, builds an Android debug APK, builds an iOS simulator app and runs backend tests with FFmpeg. Put this project at a repository's root to use it. The workflow has been added as source and has not been executed in this workspace.

Android requires Android Studio/SDK, a compatible JDK and an Android 8.0+ device (API 26). iOS requires macOS, Xcode, CocoaPods and iOS 15+. In Xcode, open `ios/Runner.xcworkspace`, choose a signing team and a unique bundle identifier. Physical devices are recommended for export testing.

On Windows, use Git Bash or WSL for the setup script and an Android SDK accessible to the Flutter installation. Build iOS on macOS.

Android release signing is deliberately left for your own key configuration. After validation and signing setup:

```bash
flutter build appbundle --release
# On macOS, after setting up iOS signing:
flutter build ipa --release
```

## Native implementation

Flutter owns the project, timeline and preview. `video_player` previews retimed footage; separate `just_audio` players preview the audio layers. Android export uses Media3 Transformer 1.5.1. iOS export uses AVFoundation composition and audio mixing with a custom Core Image video compositor. Export renders source assets and project settings independently of the preview.

The `dev.frameforge/video` method channel supports `inspect`, `inspectAudio`, `export` and `cancelExport`. The `dev.frameforge/export` event channel reports progress from 0 to 1. Each exported clip includes output duration, effective playback rate, volume, filter matrix, framing/mirror settings and source-timed motion points. Images/text carry output-timeline intervals. The `audioTracks` payload contains the soundtrack and additional audible layers exactly once. The `music` field remains as a legacy fallback, ignored by native engines when `audioTracks` is supplied. A shared Dart plan expands each audio layer into trimmed source intervals at fixed output timestamps, including a final partial loop. Android uses separate sequences with audio gaps and per-frame PCM volume envelopes; iOS inserts intervals into separate composition tracks with audio mix volume ramps. Export does not retime imported audio with clip speed.

Android retimes footage with `SpeedChangeEffect` and original audio with a pitch-preserving Sonic processor, then applies global-timeline motion/fades and bitmap overlays. iOS scales both composition tracks and requests spectral pitch correction; its compositor orients/fits the source, crops and transforms the canvas, applies fading, then renders images and text.

Flutter wraps its filter matrix between gamma conversion filters; Android uses Media3 RGB matrices with Media3's SDR processing defaults; iOS uses a linear Core Image working color space. These working spaces and native decoder transfer functions require a color-reference comparison on devices. Do not assume exact color matching before calibration. Font rasterizers can also cause visual differences.

The playback adapter and all Android Media3 modules are pinned together because the export APIs are marked unstable. Upgrade them together and run the device checklist. The iOS installer appends the engine to `AppDelegate.swift`, which is already registered in the generated Xcode project. Registration uses the classic Flutter app delegate lifecycle; review UIScene migration when updating the runner templates.

Projects are atomic JSON saves under application documents, with relative media, audio and overlay paths so drafts survive document-container relocation. Schema version 5 adds additional audio layers, their kinds and mute; schema 4 introduced audio timing/fades/clip volume and a project frame grid. Versions 1–4 still load with defaults; legacy audio duration is inspected when needed. Imported media is retained through undo and redo; deleting a project removes its copies and exports. Originals selected in the device picker remain untouched. Uninstalling the app removes local projects, so share finished exports to another location.

## Validation status

In the creation workspace, Flutter/Dart, the Android SDK and Xcode were unavailable. **Flutter analysis, Dart tests, APK/IPA builds, UI rendering, CI and native exports have not been run.**

Checks completed here:

- Two Python installer tests passed, including repeated installation and preservation of existing configuration.
- Twenty-six backend tests passed with mocked OpenAI responses and locally signed identity tokens. FFmpeg rendered actual H.264/AAC MP4s for all three canvas ratios using synthetic local test media. No real account login or paid generation was performed.
- Setup shell syntax passed; the missing-SDK path reports the required setup correctly.
- YAML parsing, source delimiter checks and relative import checks passed. These are structural checks, not language analysis or compilation.

The 100 supplied Dart regression cases cover editing, persistence, subtitles, motion, audio, native export contracts, AI models, mobile sign-in state/PKCE, session handling, asset-path safety, import rollback and AI studio widgets. These Dart tests remain unrun. Run `flutter test` once the SDK is installed, then complete [the device checklist](docs/DEVICE_CHECKLIST.md). [The validation report](docs/VALIDATION_REPORT.md) records the available checks.

## Current limits and next stages

This is a pro-feature milestone of a broader CapCut-style product. Automatic speech captions, moving AI footage, background removal, variable speed ramps, a template/catalog system, masks, chroma key, multiple video tracks, collaboration and background export remain future stages. [The pro roadmap](docs/PRO_ROADMAP.md) records the remaining capabilities and release gates.

Preview switches player instances at clip boundaries and can briefly buffer. Native exports compose continuously; verify audio alignment on devices, especially at 0.25× and 4×. Speed is constant within each clip and slow motion repeats existing frames rather than creating optical-flow frames. A split requires at least 100 ms of source and timeline footage on each side. Changing speed keeps the playhead on the same source frame and leaves text/captions/images at their output-timeline positions, clamping or removing layers beyond the new end; undo restores them.

Typography can vary between Flutter, Android and iOS font renderers. Android drops frames toward the selected frame-rate target and does not raise low source frame rates. iOS renders at the target using available source frames. Android encodes H.264/AAC; iOS uses the highest-quality SDR MP4 preset, whose output codec needs device verification. HDR inputs require device-specific validation and Android HDR tone mapping needs API 29+. Unsupported codecs, 4K or encoder settings return an error; retry at 720p/30 fps.

Local export runs while the app is open. AI generation runs independently on the configured server. There is no background local export service, cloud backup or bundled music catalog. Sharing uses the system share menu; available save destinations depend on the OS and installed apps.

Audio supports one soundtrack plus seven additional layers, alongside original clip sound. To bound native composition size, export supports up to 2,000 intervals per source and 4,000 total; very short looping sections over long videos require a longer selection or single play. Preview uses separate players; synchronization, audio focus, memory and eight-source device limits still need testing. Fade levels update with playback ticks; native export uses PCM sample timing or AVFoundation ramps. Decoder priming and compressed-source loop boundaries need device testing. Repetitions have no crossfades; source waveform cuts can produce audible discontinuities. Combined audio can clip at high levels; there is no limiter, automatic ducking, loudness normalization, waveform editor or microphone recorder.

## Files

```text
lib/models/          Project, motion, overlay, text, music and export data
lib/state/           Editing operations, history and queued autosave
lib/services/        Local project storage and native channel contract
lib/screens/         Library, editor, text and export interfaces
lib/widgets/         Media preview and timeline
backend/            ChatGPT identity, AI planning, generation jobs and FFmpeg rendering
platform/android/   Kotlin Media3 export and inspection engine
platform/ios/       Swift AVFoundation export and inspection engine
tool/               Mobile runner setup and installer checks
test/               Editing and persistence regression tests
docs/AI_SETUP.md    Required AI credentials, billing, deployment and operation
```
