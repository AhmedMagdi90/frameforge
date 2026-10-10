import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/ai_video.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/ai_client.dart';
import 'package:frameforge/services/ai_project_importer.dart';
import 'package:frameforge/services/project_library.dart';
import 'ai_client_test.dart' show MemoryCredentials;
import 'ai_video_test.dart' show fixturePlan;

class TempAiLibrary extends ProjectLibrary {
  TempAiLibrary(this.directoryRoot);
  final Directory directoryRoot;
  @override
  Future<Directory> root() async => directoryRoot;
}

class FixtureDownloadClient extends AiClient {
  FixtureDownloadClient({this.failOn}) : super(credentials: MemoryCredentials());
  final String? failOn;
  final downloads = <String>[];
  @override
  Future<void> download(String jobId, String filename, File destination) async {
    downloads.add(filename);
    await destination.writeAsBytes([1, 2, 3]);
    if (filename == failOn) throw const AiException('Interrupted download');
  }
}

AiJob completedJob() => AiJob(id: 'a' * 32, status: 'completed', progress: 1, message: 'Ready',
  plan: AiVideoPlan.fromJson(fixturePlan()), manifest: AiManifest('Coffee', CanvasRatio.portrait, const [
    AiAssetScene('scene01.mp4', 5000, 'Morning'), AiAssetScene('scene02.mp4', 5000, 'Coffee'),
  ]));

void main() {
  late Directory root;
  setUp(() async { root = await Directory.systemTemp.createTemp('frameforge_ai_'); });
  tearDown(() async { await root.delete(recursive: true); });
  test('completed video becomes a persisted editable project using inspected scene durations', () async {
    final library = TempAiLibrary(root), client = FixtureDownloadClient();
    var count = 0;
    final project = await AiProjectImporter(library, client, inspect: (path, thumbnail) async =>
      {'durationMs': ++count == 1 ? 5020 : 4980}).importVideo(completedJob());
    expect(project.clips.length, 2); expect(project.durationMs, 10000);
    expect(project.texts.first.endMs, 5020); expect(project.texts.last.startMs, 5020);
    expect(project.texts.every((text) => text.isCaption), true);
    expect((await library.list()).single.id, project.id);
    expect((await library.exports(project.id)).length, 1);
    expect(client.downloads, ['scene01.mp4', 'scene02.mp4', 'video.mp4']); client.close();
  });
  test('an interrupted scene download removes the entire partial project', () async {
    final library = TempAiLibrary(root), client = FixtureDownloadClient(failOn: 'scene02.mp4');
    final importer = AiProjectImporter(library, client, inspect: (_, __) async => {'durationMs': 5000});
    await expectLater(importer.importVideo(completedJob()), throwsA(isA<AiException>()));
    expect(await library.list(), isEmpty); expect(await root.list().toList(), isEmpty); client.close();
  });
  test('a corrupt generated scene never creates a saved draft', () async {
    final library = TempAiLibrary(root), client = FixtureDownloadClient();
    final importer = AiProjectImporter(library, client, inspect: (_, __) async => {'durationMs': 0});
    await expectLater(importer.importVideo(completedJob()), throwsA(isA<AiException>()));
    expect(await root.list().toList(), isEmpty); client.close();
  });
}
