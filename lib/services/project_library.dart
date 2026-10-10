import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';
import 'native_engine.dart';
import 'subtitles.dart';

class ProjectLibrary {
  Future<Directory> root() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/frameforge').create(recursive: true);
  }

  Future<Directory> directory(String id) async =>
    Directory('${(await root()).path}/$id').create(recursive: true);

  Future<void> save(VideoProject project) async {
    final dir = await directory(project.id);
    final temporary = File('${dir.path}/project.pending');
    final json = project.toJson();
    // Store relative asset names: iOS may move an app's document container.
    for (final clip in json['clips'] as List) {
      final asset = clip as Map<String, dynamic>;
      asset['path'] = (asset['path'] as String).split('/').last;
      if (asset['thumbnailPath'] != null) asset['thumbnailPath'] = (asset['thumbnailPath'] as String).split('/').last;
    }
    if (json['music'] != null) {
      final music = json['music'] as Map<String, dynamic>;
      music['path'] = (music['path'] as String).split('/').last;
    }
    for (final layer in json['audioLayers'] as List) {
      final track = (layer as Map<String, dynamic>)['track'] as Map<String, dynamic>;
      track['path'] = (track['path'] as String).split('/').last;
    }
    for (final image in json['images'] as List) {
      final asset = image as Map<String, dynamic>;
      asset['path'] = (asset['path'] as String).split('/').last;
    }
    await temporary.writeAsString(jsonEncode(json), flush: true);
    await temporary.rename('${dir.path}/project.json');
  }

  Future<List<VideoProject>> list() async {
    final projects = <VideoProject>[];
    await for (final entity in (await root()).list()) {
      if (entity is! Directory) continue;
      final file = File('${entity.path}/project.json');
      if (!await file.exists()) continue;
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final clip in json['clips'] as List) {
          final asset = clip as Map<String, dynamic>;
          asset['path'] = '${entity.path}/${(asset['path'] as String).split('/').last}';
          if (asset['thumbnailPath'] != null) asset['thumbnailPath'] = '${entity.path}/${(asset['thumbnailPath'] as String).split('/').last}';
        }
        if (json['music'] != null) {
          final music = json['music'] as Map<String, dynamic>;
          music['path'] = '${entity.path}/${(music['path'] as String).split('/').last}';
        }
        for (final layer in (json['audioLayers'] as List?) ?? []) {
          final track = (layer as Map<String, dynamic>)['track'] as Map<String, dynamic>;
          track['path'] = '${entity.path}/${(track['path'] as String).split('/').last}';
        }
        for (final image in (json['images'] as List?) ?? []) {
          final asset = image as Map<String, dynamic>;
          asset['path'] = '${entity.path}/${(asset['path'] as String).split('/').last}';
        }
        projects.add(VideoProject.fromJson(json));
      } on FormatException {
        // A corrupt draft is retained on disk so it can be recovered manually.
      } on TypeError {
        // Ignore invalid drafts without deleting user media.
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<VideoProject> create() async {
    final now = DateTime.now();
    final project = VideoProject(id: newId(), name: 'Untitled ${now.month}/${now.day}', updatedAt: now);
    await save(project);
    return project;
  }
  Future<void> delete(String id) async {
    final dir = Directory('${(await root()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<List<VideoClip>> importVideos(String projectId) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.video,
      allowMultiple: true, withData: false);
    if (picked == null) return [];
    final dir = await directory(projectId);
    final imported = <VideoClip>[];
    try {
      for (final file in picked.files) {
        if (file.path == null) throw StateError('The selected video has no local file.');
        final id = newId();
        final extension = file.extension?.toLowerCase() ?? 'mp4';
        final path = '${dir.path}/$id.$extension';
        final thumbnail = '${dir.path}/$id.jpg';
        await File(file.path!).copy(path);
        try {
          final metadata = await NativeEngine().inspect(path, thumbnail);
          final duration = (metadata['durationMs'] as num).toInt();
          imported.add(VideoClip(id: id, path: path, name: file.name,
            sourceDurationMs: duration, endMs: duration,
            thumbnailPath: metadata['thumbnailPath'] as String?));
        } catch (_) {
          await File(path).delete();
          if (await File(thumbnail).exists()) await File(thumbnail).delete();
          rethrow;
        }
      }
      return imported;
    } catch (_) {
      // An import batch is atomic: do not leave copied, unreferenced media.
      for (final clip in imported) {
        if (await File(clip.path).exists()) await File(clip.path).delete();
        if (clip.thumbnailPath != null && await File(clip.thumbnailPath!).exists()) {
          await File(clip.thumbnailPath!).delete();
        }
      }
      rethrow;
    }
  }

  Future<MusicTrack?> importMusic(String projectId) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: false);
    if (picked == null) return null;
    final file = picked.files.single;
    if (file.path == null) throw StateError('The selected audio has no local file.');
    final dir = await directory(projectId);
    final path = '${dir.path}/${newId()}.${file.extension ?? 'm4a'}';
    try {
      await File(file.path!).copy(path);
      return await NativeEngine().resolveMusic(MusicTrack(path: path, name: file.name));
    } catch (_) {
      if (await File(path).exists()) await File(path).delete();
      rethrow;
    }
  }

  Future<MusicTrack> resolveMusic(MusicTrack track) => NativeEngine().resolveMusic(track);

  Future<String> exportPath(String projectId) async {
    final dir = await directory(projectId);
    final exports = await Directory('${dir.path}/exports').create(recursive: true);
    return '${exports.path}/FrameForge_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  Future<ImageLayer?> importImage(String projectId, int startMs, int endMs) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'], withData: false);
    if (picked == null) return null;
    final file = picked.files.single;
    if (file.path == null) throw StateError('The selected image has no local file.');
    final input = File(file.path!);
    if (await input.length() > 20 * 1024 * 1024) throw const FormatException('Choose an image under 20 MB.');
    final buffer = await ui.ImmutableBuffer.fromUint8List(await input.readAsBytes());
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0 || descriptor.width * descriptor.height > 64000000) {
        throw const FormatException('Choose an image with at most 64 megapixels.');
      }
      final longest = descriptor.width > descriptor.height ? descriptor.width : descriptor.height;
      final scale = longest > 2048 ? 2048 / longest : 1.0;
      codec = await descriptor.instantiateCodec(targetWidth: (descriptor.width * scale).round().clamp(1, 2048).toInt(),
        targetHeight: (descriptor.height * scale).round().clamp(1, 2048).toInt());
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('Could not decode the image.');
        final id = newId();
        final path = '${(await directory(projectId)).path}/$id.png';
        await File(path).writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
        return ImageLayer(id: id, path: path, name: file.name, startMs: startMs,
          endMs: endMs, aspect: frame.image.width / frame.image.height);
      } finally { frame.image.dispose(); }
    } finally { codec?.dispose(); descriptor?.dispose(); buffer.dispose(); }
  }

  Future<List<TextLayer>?> importCaptions(int durationMs) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: ['srt', 'vtt'], withData: false);
    if (picked == null) return null;
    final path = picked.files.single.path;
    if (path == null) throw StateError('The selected subtitle file has no local path.');
    final file = File(path);
    if (await file.length() > 2 * 1024 * 1024) throw const FormatException('Choose a subtitle file under 2 MB.');
    return Subtitles.parse(await file.readAsString(), durationMs);
  }

  Future<String> exportCaptions(VideoProject project) async {
    final content = Subtitles.encodeSrt(project.texts);
    if (content.isEmpty) throw StateError('Add captions before exporting subtitles.');
    final dir = await Directory('${(await directory(project.id)).path}/exports').create(recursive: true);
    final path = '${dir.path}/FrameForge_${DateTime.now().millisecondsSinceEpoch}.srt';
    await File(path).writeAsString(content, flush: true);
    return path;
  }

  Future<List<String>> exports(String projectId) async {
    final dir = Directory('${(await directory(projectId)).path}/exports');
    if (!await dir.exists()) return [];
    final files = await dir.list().where((entry) => entry is File && entry.path.endsWith('.mp4')).toList();
    // Filenames contain a millisecond timestamp, so descending order is newest first.
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.map((file) => file.path).toList();
  }
}
