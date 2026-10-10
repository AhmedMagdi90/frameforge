import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/project_library.dart';

class DiskLibrary extends ProjectLibrary {
  DiskLibrary(this.location);
  Directory location;
  @override
  Future<Directory> root() async => location.create(recursive: true);
}

void main() {
  late Directory temporary;
  late DiskLibrary library;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('frameforge_test_');
    library = DiskLibrary(Directory('${temporary.path}/original'));
  });
  tearDown(() async { await temporary.delete(recursive: true); });

  test('saved assets remain usable after the document container moves', () async {
    final dir = await library.directory('story');
    await File('${dir.path}/a.mp4').writeAsBytes([1, 2, 3]);
    await File('${dir.path}/voice.m4a').writeAsBytes([4, 5, 6]);
    final value = VideoProject(id: 'story', name: 'My story', updatedAt: DateTime(2026),
      clips: [VideoClip(id: 'a', path: '${dir.path}/a.mp4', name: 'video.mp4', sourceDurationMs: 5000, endMs: 5000)],
      music: MusicTrack(path: '${dir.path}/music.m4a', name: 'Music'),
      audioLayers: [AudioLayer(id: 'voice', kind: AudioKind.voice,
        track: MusicTrack(path: '${dir.path}/voice.m4a', name: 'Voice', sourceDurationMs: 5000,
          timelineStartMs: 1250, fadeInMs: 200, muted: true, loop: false))],
      images: [ImageLayer(id: 'logo', path: '${dir.path}/logo.png', name: 'Logo',
        startMs: 0, endMs: 5000, aspect: 2)]);
    await library.save(value);
    final json = jsonDecode(await File('${dir.path}/project.json').readAsString()) as Map<String, dynamic>;
    expect((json['clips'] as List).first['path'], 'a.mp4');
    expect((json['images'] as List).single['path'], 'logo.png');
    expect(((json['audioLayers'] as List).single['track'] as Map)['path'], 'voice.m4a');
    expect(await File('${dir.path}/project.pending').exists(), isFalse);
    final moved = await library.location.rename('${temporary.path}/relocated');
    library.location = moved;
    final restored = (await library.list()).single;
    expect(restored.clips.single.path, '${moved.path}/story/a.mp4');
    expect(await File(restored.clips.single.path).readAsBytes(), [1, 2, 3]);
    expect(restored.music!.path, '${moved.path}/story/music.m4a');
    expect(restored.images.single.path, '${moved.path}/story/logo.png');
    expect(restored.audioLayers.single.track.path, '${moved.path}/story/voice.m4a');
    expect(await File(restored.audioLayers.single.track.path).readAsBytes(), [4, 5, 6]);
    expect(restored.audioLayers.single.track.timelineStartMs, 1250);
    expect(restored.audioLayers.single.track.muted, isTrue);
  });

  test('corrupt drafts are retained and do not hide valid projects', () async {
    final valid = await library.create();
    final bad = await library.directory('bad');
    final file = File('${bad.path}/project.json');
    await file.writeAsString('{broken');
    expect((await library.list()).single.id, valid.id);
    expect(await file.exists(), isTrue);
    await library.delete(valid.id);
    expect(await Directory('${library.location.path}/${valid.id}').exists(), isFalse);
    expect(await file.exists(), isTrue);
  });
}
