import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/models/clip_filter.dart';
import 'package:frameforge/services/project_library.dart';
import 'package:frameforge/state/editor_controller.dart';

class MemoryLibrary extends ProjectLibrary {
  VideoProject? saved;
  @override
  Future<void> save(VideoProject project) async { saved = project; }
}

VideoClip clip(String id, {int start = 0, int end = 4000, ClipTransition transition = ClipTransition.none}) => VideoClip(
  id: id, path: '/media/$id.mp4', name: '$id.mp4', sourceDurationMs: 10000,
  startMs: start, endMs: end, transition: transition);

VideoProject project(List<VideoClip> clips, {List<TextLayer> texts = const []}) => VideoProject(
  id: 'draft', name: 'Test story', updatedAt: DateTime(2026), clips: clips, texts: texts);

void main() {
  late EditorController editor;
  late MemoryLibrary library;
  setUp(() { library = MemoryLibrary(); editor = EditorController(project([
    clip('a', start: 1000, end: 5000, transition: ClipTransition.fade), clip('b'),
  ]), library); });
  tearDown(() async { await editor.flush(); editor.dispose(); });

  test('split uses source offset, preserves length and moves boundary transition', () {
    editor.seek(1500);
    expect(editor.split(), isTrue);
    expect(editor.project.clips.map((c) => c.durationMs), [1500, 2500, 4000]);
    expect(editor.project.clips[0].startMs, 1000);
    expect(editor.project.clips[1].startMs, 2500);
    expect(editor.project.clips[0].transition, ClipTransition.none);
    expect(editor.project.clips[1].transition, ClipTransition.fade);
    expect(editor.project.durationMs, 8000);
    expect(editor.selectedId, editor.project.clips[1].id);
  });

  test('split refuses zero-length or very short fragments', () {
    for (final position in [0, 50, 3950, 4000, 8000]) {
      editor.seek(position);
      expect(editor.split(), isFalse);
    }
    expect(editor.canUndo, isFalse);
  });

  test('undo and redo restore complete edits without reusing clip IDs', () {
    editor.select('a'); editor.duplicateSelected();
    final duplicateId = editor.selectedId;
    expect(duplicateId, isNot('a'));
    expect(editor.project.durationMs, 12000);
    editor.undo(); expect(editor.project.durationMs, 8000);
    editor.redo(); expect(editor.project.clips[1].id, duplicateId);
    editor.undo(); editor.setRatio(CanvasRatio.square);
    expect(editor.canRedo, isFalse);
  });

  test('reorder adjusts destination and keeps non-destructive source trims', () {
    editor.reorder(0, 2);
    expect(editor.project.clips.map((c) => c.id), ['b', 'a']);
    expect(editor.project.clips.last.startMs, 1000);
    expect(editor.project.durationMs, 8000);
    editor.undo(); expect(editor.project.clips.first.id, 'a');
  });

  test('trim clamps text to new project duration and undo restores it', () {
    editor.putText(const TextLayer(id: 'caption', text: 'Hello', startMs: 3000, endMs: 8000));
    editor.trim('a', 1000, 3000);
    expect(editor.project.texts.single.endMs, 6000);
    editor.undo(); expect(editor.project.texts.single.endMs, 8000);
    editor.select('a'); editor.removeSelected();
    editor.select('b'); editor.removeSelected();
    expect(editor.project.texts, isEmpty);
    expect(editor.positionMs, 0);
  });

  test('project JSON preserves all editing and export parameters', () {
    editor.setMusic(const MusicTrack(path: '/media/music.m4a', name: 'music', volume: .4));
    editor.putText(const TextLayer(id: 't', text: 'A story', startMs: 1000, endMs: 3000, y: .25, size: .07, color: 0xFF9FE7CF));
    editor.select('a'); editor.setMuted(true); editor.setRatio(CanvasRatio.landscape);
    editor.setSpeed(2); editor.setFilter(ClipFilter.sepia, .65);
    final json = jsonDecode(jsonEncode(editor.project.toJson())) as Map<String, dynamic>;
    final restored = VideoProject.fromJson(json);
    expect(restored.toJson(), editor.project.toJson());
    expect(restored.ratio.dimensions(1080), (1920, 1080));
  });

  test('invalid clip timing fails deserialization', () {
    final json = clip('a').toJson(); json['endMs'] = 20000;
    expect(() => VideoClip.fromJson(json), throwsFormatException);
  });

  test('flush persists the latest edit and clears saving status', () async {
    editor.rename('My film'); editor.setRatio(CanvasRatio.square);
    expect(editor.saving, isTrue);
    await editor.flush();
    expect(library.saved!.name, 'My film');
    expect(library.saved!.ratio, CanvasRatio.square);
    expect(editor.saving, isFalse);
  });

  test('speed changes preserve the viewed source frame and move later offsets', () {
    editor.select('a'); editor.seek(1500); editor.setSpeed(2);
    expect(editor.project.clips.first.durationMs, 2000);
    expect(editor.project.clipOffset(1), 2000);
    expect(editor.project.durationMs, 6000);
    expect(editor.positionMs, 750);
    expect(editor.project.clips.first.sourcePositionAt(editor.positionMs), 2500);
    editor.undo(); expect(editor.project.durationMs, 8000); expect(editor.positionMs, 1500);
    editor.redo(); expect(editor.project.clips.first.speed, 2); expect(editor.positionMs, 750);
  });

  test('changing an earlier clip keeps the playhead anchored in a later clip', () {
    editor.select('a'); editor.seek(5500); editor.setSpeed(2);
    expect(editor.positionMs, 3500);
    expect(editor.project.clipAt(editor.positionMs), 1);
    expect(editor.project.clips[1].sourcePositionAt(editor.positionMs - editor.project.clipOffset(1)), 1500);
  });

  test('split after speed change cuts the correct source and preserves filters', () {
    editor.select('a'); editor.setSpeed(2); editor.setFilter(ClipFilter.warm, .7);
    editor.seek(750); expect(editor.split(), isTrue);
    expect(editor.project.clips[0].endMs, 2500);
    expect(editor.project.clips[1].startMs, 2500);
    expect(editor.project.clips.take(2).map((clip) => clip.speed), [2, 2]);
    expect(editor.project.clips.take(2).map((clip) => clip.filter), [ClipFilter.warm, ClipFilter.warm]);
    expect(editor.project.durationMs, 6000);
    expect(editor.project.clips[1].transition, ClipTransition.fade);
  });

  test('slow-motion split refuses a fragment below the minimum source length', () {
    editor.select('a'); editor.setSpeed(.25); editor.seek(100);
    expect(editor.split(), isFalse);
  });

  test('speed change clamps text to the new end without changing its start', () {
    editor.putText(const TextLayer(id: 'late', text: 'End', startMs: 5000, endMs: 8000));
    editor.select('a'); editor.setSpeed(2);
    expect(editor.project.texts.single.startMs, 5000);
    expect(editor.project.texts.single.endMs, 6000);
    editor.undo(); expect(editor.project.texts.single.endMs, 8000);
  });

  test('invalid speed and intensity do not add an undo step', () {
    editor.select('a');
    editor.setSpeed(0); editor.setSpeed(double.nan); editor.setSpeed(10);
    editor.setFilter(ClipFilter.mono, double.nan); editor.setFilter(ClipFilter.warm, -1);
    expect(editor.canUndo, isFalse);
  });
}
