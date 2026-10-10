import 'package:flutter/services.dart';
import '../models/project.dart';
import '../models/export_settings.dart';
import 'audio_render_plan.dart';

class NativeEngine {
  static const _methods = MethodChannel('dev.frameforge/video');
  static const _events = EventChannel('dev.frameforge/export');
  bool _cancelRequested = false;
  Stream<double> get progress => _events.receiveBroadcastStream().map(
    (event) => (event as num).toDouble().clamp(0, 1).toDouble());

  Future<Map<String, dynamic>> inspect(String path, String thumbnailPath) async {
    final result = await _methods.invokeMapMethod<String, dynamic>('inspect', {
      'path': path, 'thumbnailPath': thumbnailPath,
    });
    if (result == null || (result['durationMs'] as num).toInt() < 100) {
      throw const FormatException('This video is too short or unreadable.');
    }
    return result;
  }

  Future<String> export(VideoProject project, String outputPath, int shortEdge, {int? fps}) async {
    _cancelRequested = false;
    final frameRate = fps ?? project.frameRate;
    if (!ExportSettings(shortEdge: shortEdge, fps: frameRate).isValid) throw ArgumentError('Unsupported export settings');
    final (width, height) = project.ratio.dimensions(shortEdge);
    if (project.music != null && !project.music!.isValid) throw const FormatException('Invalid soundtrack settings');
    if (project.audioLayers.length > maxAdditionalAudioLayers ||
        project.audioLayers.any((layer) => !layer.isValid) ||
        project.audioLayers.map((layer) => layer.id).toSet().length != project.audioLayers.length) {
      throw const FormatException('Invalid audio layers');
    }
    final audioPlans = <Map<String, dynamic>>[];
    var intervalCount = 0;
    for (final layer in project.audioTracks) {
      if (_cancelRequested) throw StateError('Export cancelled');
      if (layer.track.muted || layer.track.timelineStartMs >= project.durationMs) continue;
      final resolved = await resolveMusic(layer.track);
      if (_cancelRequested) throw StateError('Export cancelled');
      final plan = musicRenderPlan(resolved, project.durationMs);
      intervalCount += (plan['segments'] as List).length;
      if (intervalCount > 4000) throw const FormatException('Choose longer audio sections or turn off some loops.');
      audioPlans.add({...plan, 'id': layer.id, 'kind': layer.kind.name});
    }
    final soundtracks = audioPlans.where((plan) => plan['id'] == soundtrackId);
    final musicPlan = soundtracks.isEmpty ? null : soundtracks.first;
    if (_cancelRequested) throw StateError('Export cancelled');
    final result = await _methods.invokeMethod<String>('export', {
      ...project.toJson(), 'outputPath': outputPath,
      'music': musicPlan,
      'audioTracks': audioPlans,
      'clips': project.clips.map((clip) => {
        ...clip.toJson(), 'outputDurationMs': clip.durationMs,
        'renderSpeed': clip.playbackSpeed,
        'filterMatrix': clip.filter.matrix(clip.filterIntensity),
      }).toList(),
      'width': width, 'height': height, 'fps': frameRate,
    });
    if (result == null) throw StateError('The exporter returned no output.');
    return result;
  }
  Future<MusicTrack> resolveMusic(MusicTrack track) async {
    if (!track.isValid) throw const FormatException('Invalid music settings');
    if (track.sourceDurationMs != null) return track;
    final metadata = await _methods.invokeMapMethod<String, dynamic>('inspectAudio', {'path': track.path});
    final duration = (metadata?['durationMs'] as num?)?.toInt() ?? 0;
    if (duration < 100) throw const FormatException('This audio is too short or unreadable.');
    final resolved = track.copyWith(sourceDurationMs: duration);
    if (!resolved.isValid) throw const FormatException('The saved music trim is outside this audio.');
    return resolved;
  }
  Future<void> cancel() {
    _cancelRequested = true;
    return _methods.invokeMethod<void>('cancelExport');
  }
}
