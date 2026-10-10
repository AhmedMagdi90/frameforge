import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/project_library.dart';
import 'package:frameforge/state/editor_controller.dart';

class MemoryLibrary extends ProjectLibrary {
  @override Future<void> save(VideoProject project) async {}
}

void main() {
  const sound = MusicTrack(path: '/voice.m4a', name: 'Voice', sourceDurationMs: 6000,
    sourceStartMs: 500, sourceEndMs: 3500, timelineStartMs: 1000, loop: false, volume: .8);
  const layer = AudioLayer(id: 'voice', kind: AudioKind.voice, track: sound);
  late EditorController editor;
  setUp(() {
    editor = EditorController(VideoProject(id: 'p', name: 'Audio', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 6000, endMs: 6000)]), MemoryLibrary());
  });
  tearDown(() async { await editor.flush(); editor.dispose(); });

  test('audio layers preserve kind, mute, timing and fades through JSON', () {
    editor.setMusic(sound.copyWith(loop: true));
    editor.putAudioLayer(layer.copyWith(track: sound.copyWith(muted: true, fadeInMs: 200, fadeOutMs: 300)));
    final restored = VideoProject.fromJson(editor.project.toJson());
    expect(restored.toJson(), editor.project.toJson());
    expect(restored.audioTracks.map((track) => track.id), [soundtrackId, 'voice']);
    expect(restored.audioLayers.single.kind, AudioKind.voice);
    expect(restored.audioLayers.single.track.gainAt(1500, 6000), 0);
    expect(restored.audioLayers.single.track.fadeOutMs, 300);
  });

  test('schemas one through four load with an empty additional audio list', () {
    for (final schema in [1, 2, 3, 4]) {
      final json = editor.project.toJson()..remove('audioLayers');
      json['schemaVersion'] = schema;
      final restored = VideoProject.fromJson(json);
      expect(restored.audioLayers, isEmpty);
      expect(restored.toJson()['schemaVersion'], 5);
    }
  });

  test('adding, editing and removing audio are undoable and keep stable identities', () {
    expect(editor.putAudioLayer(layer), isTrue);
    editor.putAudioLayer(layer.copyWith(track: sound.copyWith(timelineStartMs: 2000)));
    expect(editor.project.audioLayers.single.track.timelineStartMs, 2000);
    editor.removeAudioLayer('voice'); expect(editor.project.audioLayers, isEmpty);
    editor.undo(); expect(editor.project.audioLayers.single.id, 'voice');
    editor.undo(); expect(editor.project.audioLayers.single.track.timelineStartMs, 1000);
    editor.undo(); expect(editor.project.audioLayers, isEmpty);
    editor.redo(); expect(editor.project.audioLayers.single.id, 'voice');
  });

  test('duplicate shares its asset but has independent timing, volume and mute', () {
    editor.putAudioLayer(layer);
    expect(editor.duplicateAudioLayer('voice', timelineStartMs: 4000), isTrue);
    final duplicate = editor.project.audioLayers.last;
    expect(duplicate.id, isNot('voice')); expect(duplicate.track.path, sound.path);
    expect(duplicate.track.timelineStartMs, 4000);
    editor.putAudioLayer(duplicate.copyWith(track: duplicate.track.copyWith(volume: .2, muted: true)));
    expect(editor.project.audioLayers.first.track.volume, .8);
    expect(editor.project.audioLayers.first.track.muted, isFalse);
    expect(editor.project.audioLayers.last.track.volume, .2);
  });

  test('seven-layer limit allows updates but rejects additions without changing history', () {
    for (var i = 0; i < maxAdditionalAudioLayers; i++) {
      expect(editor.putAudioLayer(layer.copyWith(id: 'layer$i')), isTrue);
    }
    expect(editor.putAudioLayer(layer), isFalse);
    expect(editor.duplicateAudioLayer('layer0'), isFalse);
    expect(editor.putAudioLayer(layer.copyWith(id: 'layer0', track: sound.copyWith(volume: .2))), isTrue);
    editor.undo(); expect(editor.project.audioLayers.first.track.volume, .8);
    editor.undo(); expect(editor.project.audioLayers.length, maxAdditionalAudioLayers - 1);
  });

  test('invalid IDs, settings and unknown removals do not create history', () {
    expect(editor.putAudioLayer(layer.copyWith(id: soundtrackId)), isFalse);
    expect(editor.putAudioLayer(layer.copyWith(id: '')), isFalse);
    expect(editor.putAudioLayer(layer.copyWith(track: sound.copyWith(volume: 2))), isFalse);
    editor.removeAudioLayer('missing'); editor.toggleAudioMute('missing');
    expect(editor.duplicateAudioLayer('missing'), isFalse);
    expect(editor.canUndo, isFalse);
  });

  test('mute keeps gain and placement, applies to soundtrack, and can be undone', () {
    editor.setMusic(sound); editor.putAudioLayer(layer);
    editor.toggleAudioMute('voice'); editor.toggleAudioMute(soundtrackId);
    expect(editor.project.music!.muted, isTrue);
    expect(editor.project.audioLayers.single.track.volume, .8);
    expect(editor.project.audioLayers.single.track.gainAt(1500, 6000), 0);
    editor.undo(); expect(editor.project.music!.muted, isFalse);
    editor.undo(); expect(editor.project.audioLayers.single.track.muted, isFalse);
  });

  test('video shortening retains all audio timing and restoring length makes it audible', () {
    editor.putAudioLayer(layer.copyWith(track: sound.copyWith(timelineStartMs: 5000)));
    editor.trim('c', 0, 2000);
    expect(editor.project.audioLayers.single.track.timelineStartMs, 5000);
    expect(editor.project.audioLayers.single.track.gainAt(1999, 2000), 0);
    editor.undo(); expect(editor.project.audioLayers.single.track.gainAt(5500, 6000), .8);
  });

  test('persisted duplicate, reserved and excessive layer identities are rejected', () {
    final json = editor.project.toJson();
    json['audioLayers'] = [layer.toJson(), layer.toJson()];
    expect(() => VideoProject.fromJson(json), throwsFormatException);
    json['audioLayers'] = [layer.copyWith(id: soundtrackId).toJson()];
    expect(() => VideoProject.fromJson(json), throwsFormatException);
    json['audioLayers'] = [for (var i = 0; i < 8; i++) layer.copyWith(id: 'layer$i').toJson()];
    expect(() => VideoProject.fromJson(json), throwsFormatException);
  });
}
