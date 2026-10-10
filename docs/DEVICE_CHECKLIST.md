# Device validation before release

The native source has not been compiled or exercised in the creation environment. Complete this checklist on an Android device and an iPhone after running `tool/setup.sh`, `flutter analyze` and `flutter test`. Record OS versions, model, Flutter version and source codec for failures.

## Version 0.6 AI studio checks

- Configure an eligible registered ChatGPT client, exact HTTPS backend callback and API credentials using `AI_SETUP.md`. Verify readiness flags without exposing keys. Local editing must remain available without an account/service.
- Complete real browser sign-in on Android/iOS, including consent cancellation, cookie/state expiry, app switching and returning through the custom callback. Sign out, restart and sign in again. Confirm secure storage survives normal app restarts and clears on session expiry/service switching.
- Generate plans from an original idea and refinements in supported languages. Review ratio, approximate duration, scene edits and short narration. Verify billing and synthetic-voice disclosure is visible before generation.
- Generate a real two-scene video, leave the screen/app, reconnect and resume via history. Verify progress, cancellation and safe errors for invalid credentials, unavailable models, limits, provider refusal and service restarts. Confirm retries with the same submission key create one job.
- Import the result, verify scene/caption alignment, clip audio and project persistence, then edit and export locally. Share the original MP4 from recent exports. Interrupt a download and confirm no partial draft remains; retry from history.
- Check account isolation, HTTPS transport, private volume permissions and sanitized logs in staging. Inspect real 720p/30 fps H.264/AAC output for all ratios, image cropping, caption legibility, Unicode fonts, narration and disclosure metadata. Measure CPU/memory/disk and establish retention/user deletion before public release.

1. Import two H.264 SDR clips of different orientations and frame rates, including one with no audio. Deny/cancel the picker once. Confirm the app remains usable and cancelled imports add no clips.
2. Trim a clip with a nonzero source start, then split it at 1.5 seconds into its trimmed range. Confirm the cut uses the trimmed source offset, total duration is unchanged and undo restores the clip.
3. Reorder, duplicate, mute and delete clips. Undo and redo. Close the editor and reopen the draft; verify the same order, trims, audio and canvas ratio.
4. Add short music. Play beyond its first loop, seek backwards, change volume and replace/remove it. Verify original clip audio and music can play together.
5. Add two timed text layers with different colors and positions. Check text start/end boundaries, wrapping and all three canvas ratios. Reduce project length and undo; text timing should clamp and restore.
6. Add fade through black at a boundary. Test a normal clip and a clip shorter than 600 ms. Confirm the last clip cannot add a transition to a nonexistent next clip.
7. Export each canvas at 720p and 1080p. Inspect dimensions, duration, frame rate, audio, orientation, black padding, text timing and the fade in an independent player. Verify native output matches the edit settings.
8. Cancel export early and midway. Confirm the export sheet unlocks, partial files are removed and the draft remains available. Repeat an export after cancellation and an encoder error.
9. Share the exported MP4, close/reopen the editor and select the previous export in the Export panel. Check the iPad share popover if targeting iPad.
10. Background and resume playback; playback should pause and draft saving should finish. Keep the app foregrounded during export. Test a missing/corrupt source, a corrupt JSON draft and insufficient storage.
11. Test a HEVC/HDR video on supported hardware, a 60 fps source, non-ASCII filenames, multiline text and long projects. Record preview buffering, export memory usage and export time.
12. Build release binaries with your own signing configuration. Test those binaries on physical devices before any store submission.

## Version 0.2 checks

13. Set a trimmed 4-second clip to 2× and confirm its output duration is 2 seconds. Seek halfway, then change its speed; the displayed source frame should stay the same. Change an earlier clip's speed while the playhead is in a later clip and verify that later frame stays selected.
14. Split at 0.25×, 0.75×, 2× and 4×. Check source in/out positions, preserve speed and filter settings on both halves, and confirm boundary fades follow the right half. Small fragments below the minimum source length should be refused.
15. Export a sequence containing normal, slow and fast clips with original audio and looping music. Listen for speech pitch, alignment, silent gaps and duration drift. Music should remain at normal speed; subtitles/text should retain their output-timeline timing.
16. Compare all six looks at 0%, 50% and 100% intensity on saturated, neutral and dark footage. Check both preview and exported files. Text and the canvas padding should retain their colors. Compare fade brightness with and without a filter.
17. Export portrait footage with 90°/270° rotation metadata, landscape footage and a mixture of both. Verify orientation, padding and text position with the iOS Core Image compositor. Cancel while it is processing frames and then export again.
18. Reopen version 1 and 2 drafts and confirm default motion/overlay settings. Save and reopen them in schema 3. Duplicate, undo and redo clips with speed/filter settings.

## Version 0.3 pro feature checks

19. Set fit/fill framing, mirror, a 90° rotation, zoom and pan on each canvas. Compare preview and exports using a numbered orientation chart; check clockwise rotation, mirror order, black borders and clipping. Use two clips with different motion to verify motion resets at the cut.
20. Add motion points at the start, middle and end of a trimmed clip. Split through an interpolated point, trim again, set 2× and 0.25×, and compare the same source frame before/after each edit. Try the slow zoom preset. Undo/redo and reopen the draft.
21. Import a transparent PNG logo, portrait JPEG and WebP. Check default timing, position, opacity, rotation, width and layer order in preview and export. Verify overlays appear above footage and below text. Reduce project length and undo. Verify image copies survive document-container relocation.
22. Import SRT with CRLF/BOM and multiline cues, WebVTT with identifiers, and a malformed file. Confirm invalid import keeps the previous captions. Replace a valid caption set, undo and redo, edit a cue and its timing, then share SRT and reimport it. Cues beyond project end are skipped or clamped. Style markup is rendered as plain text.
23. Export 24/30/60 fps targets at 720p, 1080p and 4K on capable devices. Inspect real dimensions, codec, frame rate and timing. Android drops frames to the target and does not create additional frames; iOS repeats existing frames if needed. Test a low-end encoder error, cancellation and successful retry at 720p.
24. Stress-test 20 overlays, 500 captions, long music and a 4K export. Measure memory, export time and battery use. Cancel repeatedly and verify image bitmap resources are released. Confirm a 21st overlay and oversized/unreadable images fail with a useful message.
25. Run the supplied CI in a repository with this project at its root. Fix all analyzer, test, Kotlin, Swift, Gradle and CocoaPods failures before distribution. Record the successful build revision and completed device matrix in a release report.

## Version 0.4 audio and timeline checks

26. Import AAC, MP3 and WAV music, including files with codec delay, and cancel/deny the picker. A failed audio inspection should remove the copied asset. Open a legacy draft whose music has no stored duration; confirm it is inspected before editing/export.
27. Trim music from a nonzero source offset and place it at 2 seconds in the video. Test looping and single play, seek before/after its window, and compare native output. Check silence before placement and after single play, the final partial loop and audio alignment at each repetition.
28. Set 1-second and 10-second fades. Compare preview/export amplitudes near start, middle and end. Check that fades do not restart at loops and both clamp to half a short window. Include mono/stereo and PCM float sources where supported. Verify compressed-source priming and sample timing with an independent audio tool.
29. Set different source volume on consecutive clips, then mute/unmute, split, duplicate, set speed and undo/redo. Compare export levels at each boundary. Add a loud soundtrack and test useful combined volume settings.
30. Place music after the video end, shorten video and undo. Confirm export excludes inactive music without changing the saved placement. Cancel export while legacy audio inspection is pending; no native export should begin later.
31. Choose each 24/30/60 fps grid, step repeatedly forward/backward and test off-grid positions, clip cuts and endpoints. Enter milliseconds, minutes and hours; reject invalid/out-of-range entries. Test 60 fps grid steps on paused preview, source rates different from the grid and speed changes. Snapping affects scrubbing only; frame steps/time entry should stay exact in timeline time.
32. Reopen schema 1–3 projects, save/reopen schema 4 and verify old audio defaults plus new settings. Test small screens with the additional timeline/playhead controls, assistive labels, background pause, repeated audio replacement and long exports.

## Version 0.5 multiple audio checks

33. Combine a soundtrack with voice and sound effect files at overlapping offsets. Set independent trims, fades, volume, single play and loops. Enter exact in/out/start times; reject sections shorter than 100 ms. Compare each source's placement and its final partial interval in preview and export.
34. Duplicate a layer at the playhead, adjust only its gain/timing and mute the original. Undo/redo edit, duplicate, mute, replacement and removal. Replacing an asset keeps placement/loop/gain/mute/fades and resets its source range. Verify duplicates share one retained asset and remain independently editable.
35. Add seven extra sources alongside the soundtrack. An eighth extra import/duplicate must be refused while existing layers remain editable. Scroll all audio lanes and compare their widths/offsets. Measure memory, decoder limits, focus, drift and cancellation on low-end Android and iPhone devices. Reduce active sources if a device cannot sustain eight players.
36. Rapidly seek, pause, replace/remove/mute sources while audio is loading. No stale file should start later; removed players should release resources. Missing/corrupt layers should warn without stopping valid preview layers or video. A missing audible export source must fail, while muted/out-of-project assets do not require inspection. Reopen a project to retry transient playback failures.
37. Cancel during inspection of an additional legacy source and export again. Exercise the 2,000-per-source and 4,000-total interval limits; use longer sections or disable loops after the error. Listen for summed clipping and compressed-source boundary artifacts, including at 0.25×/4× video speed; imported audio remains at normal speed.
38. Reopen schema 1–4 drafts, save as schema 5, relocate the documents directory and verify all audio paths, kinds, mute and timing. Test small screens, lifecycle/background pause and both native platforms before treating the mixer as device-verified.
