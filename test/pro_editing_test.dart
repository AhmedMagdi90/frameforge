import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/project_library.dart';
import 'package:frameforge/state/editor_controller.dart';

class MemoryLibrary extends ProjectLibrary {
  @override
  Future<void> save(VideoProject project) async {}
}

void main() {
  const frames = [MotionKeyframe(sourceMs: 1000),
    MotionKeyframe(sourceMs: 5000, zoom: 2, x: .5, y: -.2, rotation: 90)];
  late EditorController editor;
  setUp(() {
    editor = EditorController(VideoProject(id: 'p', name: 'Pro story', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'a', path: '/a.mp4', name: 'A',
        sourceDurationMs: 6000, startMs: 1000, endMs: 5000)]), MemoryLibrary());
    editor.select('a');
  });
  tearDown(() async { await editor.flush(); editor.dispose(); });

  test('motion interpolates and holds endpoint values outside the keyed range', () {
    final middle = motionAt(frames, 3000);
    expect(middle.zoom, 1.5); expect(middle.x, .25);
    expect(middle.y, -.1); expect(middle.rotation, 45);
    expect(motionAt(frames, 0).zoom, 1);
    expect(motionAt(frames, 6000).rotation, 90);
    expect(motionAt([], 1200).zoom, 1);
  });

  test('split, trim and speed changes preserve motion on the same source frames', () {
    editor.setMotion(ClipFit.fill, true, frames);
    editor.setSpeed(2); editor.seek(1000);
    expect(editor.selected!.motionAtTimeline(1000).zoom, 1.5);
    expect(editor.split(), isTrue);
    final left = editor.project.clips.first, right = editor.project.clips.last;
    expect(left.motionAtTimeline(left.durationMs).zoom, right.motionAtTimeline(0).zoom);
    expect(right.motionAtTimeline(500).zoom, 1.75);
    expect(right.fit, ClipFit.fill); expect(right.flipX, isTrue);
    editor.trim(left.id, 2000, 3000);
    expect(editor.project.clips.first.motionAtTimeline(0).zoom, 1.25);
    editor.undo(); expect(editor.project.clips.first.startMs, 1000);
  });

  test('keyframe updates reject invalid and duplicate source timing without history', () {
    editor.setMotion(ClipFit.fit, false, const [MotionKeyframe(sourceMs: 10, zoom: 0)]);
    editor.setMotion(ClipFit.fit, false, const [MotionKeyframe(sourceMs: 7000)]);
    editor.setMotion(ClipFit.fit, false, const [MotionKeyframe(sourceMs: 10), MotionKeyframe(sourceMs: 10)]);
    expect(editor.canUndo, isFalse);
    editor.setMotion(ClipFit.fit, false, frames.reversed.toList());
    expect(editor.selected!.keyframes.first.sourceMs, 1000);
  });

  test('overlay timing is clamped on trim and restored by undo', () {
    editor.putImage(const ImageLayer(id: 'image', path: '/logo.png', name: 'Logo',
      startMs: 2000, endMs: 4000, aspect: 2, opacity: .5));
    editor.trim('a', 1000, 4000);
    expect(editor.project.images.single.endMs, 3000);
    editor.undo(); expect(editor.project.images.single.endMs, 4000);
    editor.removeSelected(); expect(editor.project.images, isEmpty);
    editor.undo(); expect(editor.project.images.single.path, '/logo.png');
  });

  test('caption replacement preserves titles and undo restores previous captions', () {
    editor.putText(const TextLayer(id: 'title', text: 'Film', startMs: 0, endMs: 4000));
    editor.replaceCaptions(const [TextLayer(id: 'one', text: 'Hello', startMs: 0, endMs: 1000, isCaption: true)]);
    editor.replaceCaptions(const [TextLayer(id: 'two', text: 'World', startMs: 1000, endMs: 2000, isCaption: true)]);
    expect(editor.project.texts.map((t) => t.id), ['title', 'two']);
    editor.undo(); expect(editor.project.texts.map((t) => t.id), ['title', 'one']);
    editor.redo(); expect(editor.project.texts.last.isCaption, isTrue);
  });

  test('current schema round trips pro data and accepts real schema two defaults', () {
    editor.setMotion(ClipFit.fill, true, frames);
    editor.putImage(const ImageLayer(id: 'i', path: '/i.png', name: 'Image',
      startMs: 0, endMs: 4000, aspect: 1.5, rotation: 45));
    final json = editor.project.toJson();
    expect(VideoProject.fromJson(json).toJson(), json);
    final old = {...json, 'schemaVersion': 2}..remove('images');
    old['clips'] = [editor.selected!.toJson()..remove('fit')..remove('flipX')..remove('keyframes')];
    final restored = VideoProject.fromJson(old);
    expect(restored.images, isEmpty); expect(restored.clips.single.fit, ClipFit.fit);
    expect(restored.clips.single.keyframes, isEmpty);
  });
}
