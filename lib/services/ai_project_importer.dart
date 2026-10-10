import 'dart:io';
import '../models/ai_video.dart';
import '../models/project.dart';
import 'ai_client.dart';
import 'native_engine.dart';
import 'project_library.dart';

typedef AiMediaInspector = Future<Map<String, dynamic>> Function(String path, String thumbnail);

class AiProjectImporter {
  AiProjectImporter(this.library, this.client, {AiMediaInspector? inspect}) : _inspect = inspect ?? NativeEngine().inspect;
  final ProjectLibrary library;
  final AiClient client;
  final AiMediaInspector _inspect;
  Future<VideoProject> importVideo(AiJob job) async {
    final manifest = job.manifest;
    if (job.status != 'completed' || manifest == null) throw const AiException('This video is not ready to edit.');
    final id = newId(), directory = await library.directory(id);
    try {
      final clips = <VideoClip>[], captions = <TextLayer>[];
      var position = 0;
      for (final scene in manifest.scenes) {
        final clipId = newId(), path = '${directory.path}/${newId()}.mp4';
        final thumbnail = '${directory.path}/$clipId.jpg';
        await client.download(job.id, scene.filename, File(path));
        final info = await _inspect(path, thumbnail);
        final duration = (info['durationMs'] as num).toInt();
        if (duration < 100 || duration > 31000) throw const AiException('A generated scene has invalid timing.');
        clips.add(VideoClip(id: clipId, path: path, name: 'AI scene ${clips.length + 1}',
          sourceDurationMs: duration, endMs: duration, thumbnailPath: info['thumbnailPath'] as String?));
        captions.add(TextLayer(id: newId(), text: scene.caption, startMs: position, endMs: position + duration, isCaption: true));
        position += duration;
      }
      final export = await library.exportPath(id);
      await client.download(job.id, 'video.mp4', File(export));
      final project = VideoProject(id: id, name: manifest.title, updatedAt: DateTime.now(),
        clips: clips, texts: captions, ratio: manifest.ratio);
      await library.save(project);
      return project;
    } catch (_) {
      await library.delete(id);
      rethrow;
    }
  }
}
