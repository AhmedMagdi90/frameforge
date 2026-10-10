import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/models/timeline_grid.dart';
import 'package:frameforge/services/audio_render_plan.dart';
import 'package:frameforge/services/project_library.dart';
import 'package:frameforge/state/editor_controller.dart';

class MemoryLibrary extends ProjectLibrary {
  @override
  Future<void> save(VideoProject project) async {}
}

void main() {
  const song = MusicTrack(path: '/song.m4a', name: 'Song', sourceDurationMs: 6000,
    sourceStartMs: 1000, sourceEndMs: 3000, timelineStartMs: 500);
  late EditorController editor;
  setUp(() {
    editor = EditorController(VideoProject(id: 'p', name: 'Sound', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'a', path: '/a.mp4', name: 'A', sourceDurationMs: 6000, endMs: 2000),
        VideoClip(id: 'b', path: '/b.mp4', name: 'B', sourceDurationMs: 6000, endMs: 2000)]), MemoryLibrary());
    editor.select('a');
  });
  tearDown(() async { await editor.flush(); editor.dispose(); });

  test('trimmed music maps output positions through loops and silent placement', () {
    expect(song.sourcePositionAt(499, 5000), isNull);
    expect(song.sourcePositionAt(500, 5000), 1000);
    expect(song.sourcePositionAt(2499, 5000), 2999);
    expect(song.sourcePositionAt(2500, 5000), 1000);
    expect(song.sourcePositionAt(4500, 5000), 1000);
    expect(song.sourcePositionAt(5000, 5000), isNull);
  });

  test('single-play music stops after its selected section', () {
    final once = song.copyWith(loop: false);
    expect(once.renderEndMs(5000), 2500);
    expect(once.sourcePositionAt(2499, 5000), 2999);
    expect(once.sourcePositionAt(2500, 5000), isNull);
    expect(once.gainAt(3000, 5000), 0);
  });

  test('fades span the full music window rather than restarting each loop', () {
    final fading = song.copyWith(fadeInMs: 1000, fadeOutMs: 1000);
    expect(fading.gainAt(500, 5000), 0);
    expect(fading.gainAt(1000, 5000), closeTo(.3, 1e-9));
    expect(fading.gainAt(2500, 5000), .6);
    expect(fading.gainAt(4500, 5000), closeTo(.3, 1e-9));
    expect(fading.gainAt(5000, 5000), 0);
  });

  test('short windows clamp each fade to half the audible duration', () {
    final fading = song.copyWith(fadeInMs: 10000, fadeOutMs: 10000);
    expect(fading.renderFadeInMs(1000), 250);
    expect(fading.renderFadeOutMs(1000), 250);
    expect(fading.gainAt(625, 1000), closeTo(.3, 1e-9));
    expect(fading.gainAt(750, 1000), .6);
    expect(fading.gainAt(875, 1000), closeTo(.3, 1e-9));
  });

  test('shared export plan keeps trimmed starts and the final partial loop exact', () {
    final plan = musicRenderPlan(song, 5000);
    expect(plan['segments'], [
      {'sourceStartMs': 1000, 'sourceEndMs': 3000, 'timelineStartMs': 500, 'timelineEndMs': 2500},
      {'sourceStartMs': 1000, 'sourceEndMs': 3000, 'timelineStartMs': 2500, 'timelineEndMs': 4500},
      {'sourceStartMs': 1000, 'sourceEndMs': 1500, 'timelineStartMs': 4500, 'timelineEndMs': 5000},
    ]);
    final once = musicRenderPlan(song.copyWith(loop: false, fadeOutMs: 500), 5000);
    expect((once['segments'] as List).length, 1);
    expect(once['renderEndMs'], 2500); expect(once['renderFadeOutMs'], 500);
  });

  test('music beyond the project end yields no export intervals or gain', () {
    final outside = song.copyWith(timelineStartMs: 6000, fadeInMs: 500);
    expect(musicRenderPlan(outside, 5000)['segments'], isEmpty);
    expect(outside.gainAt(4000, 5000), 0);
    expect(outside.renderFadeInMs(5000), 0);
  });

  test('legacy drafts keep full-file looping defaults until inspected', () {
    final legacy = MusicTrack.fromJson({'path': '/song.m4a', 'name': 'Song', 'volume': .6});
    expect(legacy.sourceDurationMs, isNull); expect(legacy.loop, isTrue);
    expect(legacy.sourceStartMs, 0); expect(legacy.timelineStartMs, 0);
    expect(legacy.fadeInMs, 0); expect(legacy.fadeOutMs, 0);
    final json = editor.project.toJson();
    json['schemaVersion'] = 3;
    json.remove('frameRate');
    json['music'] = legacy.toJson();
    json['clips'] = [editor.selected!.toJson()..remove('volume')];
    final restored = VideoProject.fromJson(json);
    expect(restored.frameRate, 30); expect(restored.clips.single.volume, 1);
  });

  test('invalid audio ranges, gain and fade settings are rejected', () {
    for (final invalid in [song.copyWith(volume: double.nan), song.copyWith(volume: 2),
      song.copyWith(sourceStartMs: 2950), song.copyWith(sourceEndMs: 7000),
      song.copyWith(timelineStartMs: -1), song.copyWith(fadeInMs: 10001), song.copyWith(fadeOutMs: -1)]) {
      expect(() => MusicTrack.fromJson(invalid.toJson()), throwsFormatException);
    }
    expect(() => musicRenderPlan(const MusicTrack(path: '/x', name: 'Unknown'), 5000), throwsFormatException);
  });

  test('extreme loop counts fail before constructing a huge native composition', () {
    const short = MusicTrack(path: '/short.wav', name: 'Short', sourceDurationMs: 100);
    expect(() => musicRenderPlan(short, 200100), throwsFormatException);
    expect((musicRenderPlan(short.copyWith(loop: false), 200100)['segments'] as List).length, 1);
  });

  test('clip volume survives splitting and mute toggles and can be undone', () {
    editor.setClipVolume(.35); editor.setMuted(true); editor.setMuted(false);
    expect(editor.selected!.volume, .35);
    editor.seek(1000); expect(editor.split(), isTrue);
    expect(editor.project.clips.take(2).map((c) => c.volume), [.35, .35]);
    editor.undo(); editor.undo(); editor.undo(); editor.undo();
    expect(editor.project.clips.first.volume, 1);
  });

  test('invalid volume and music changes do not create history', () {
    editor.setClipVolume(-1); editor.setClipVolume(double.nan); editor.setClipVolume(2);
    editor.setMusic(song.copyWith(sourceEndMs: 9000));
    expect(editor.canUndo, isFalse); expect(editor.project.music, isNull);
  });

  test('music placement remains fixed on shortening video and returns with undo', () {
    editor.setMusic(song.copyWith(timelineStartMs: 3500));
    editor.trim('a', 0, 1000);
    expect(editor.project.music!.timelineStartMs, 3500);
    expect(editor.project.music!.gainAt(2999, editor.project.durationMs), 0);
    editor.undo(); expect(editor.project.music!.gainAt(3750, editor.project.durationMs), .6);
  });

  test('project audio and frame grid round-trip with undoable defaults', () {
    editor.setMusic(song.copyWith(loop: false, fadeInMs: 500, fadeOutMs: 700));
    editor.setClipVolume(.4); editor.setFrameRate(60);
    final restored = VideoProject.fromJson(editor.project.toJson());
    expect(restored.toJson(), editor.project.toJson());
    expect(restored.music!.sourceStartMs, 1000); expect(restored.frameRate, 60);
    editor.undo(); expect(editor.project.frameRate, 30);
    editor.redo(); expect(editor.project.frameRate, 60);
  });

  test('frame grid stepping avoids accumulated millisecond rounding', () {
    for (final fps in [24, 30, 60]) {
      final grid = TimelineGrid(fps);
      var position = 0;
      for (var i = 0; i < fps * 10; i++) { position = grid.step(position, 1, 60000); }
      expect(position, 10000);
      for (var i = 0; i < fps * 10; i++) { position = grid.step(position, -1, 60000); }
      expect(position, 0);
    }
  });

  test('off-grid stepping moves in the requested direction and stops at endpoints', () {
    const grid = TimelineGrid(30);
    expect(grid.step(47, 1, 5000), 67); expect(grid.step(47, -1, 5000), 33);
    expect(grid.step(0, -1, 5000), 0); expect(grid.step(5000, 1, 5000), 5000);
    expect(grid.step(4999, 1, 4999), 4999);
  });

  test('boundary snapping can be disabled and frame steps bypass it', () {
    editor.seekWithSnap(2050); expect(editor.positionMs, 2000);
    editor.stepFrame(1); expect(editor.positionMs, 2033);
    editor.seekWithSnap(1900); expect(editor.positionMs, 1900);
    editor.toggleSnap(); editor.seekWithSnap(2050); expect(editor.positionMs, 2050);
    expect(editor.canUndo, isFalse);
  });

  test('time entry accepts hours, seconds and precise fractions without float drift', () {
    expect(TimelineGrid.parseTime('1:02.003'), 62003);
    expect(TimelineGrid.parseTime('01:02:03.1'), 3723100);
    expect(TimelineGrid.parseTime('12.25'), 12250);
    expect(TimelineGrid.parseTime(formatPreciseTime(3723123)), 3723123);
  });

  test('invalid timecodes and frame rates fail cleanly', () {
    for (final input in ['-1', '1:60', '1:60:00', '1.0001', 'hello']) {
      expect(() => TimelineGrid.parseTime(input), throwsFormatException);
    }
    expect(() => const TimelineGrid(120).step(0, 1, 1000), throwsArgumentError);
    editor.setFrameRate(120); expect(editor.canUndo, isFalse);
  });
}
