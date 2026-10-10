import 'dart:math' as math;
import '../models/music_track.dart';

/// A shared output-time plan keeps both native exporters aligned with preview.
Map<String, dynamic> musicRenderPlan(MusicTrack track, int projectDurationMs) {
  if (!track.isValid || track.trimmedDurationMs == null) throw const FormatException('Invalid or uninspected music');
  final length = track.trimmedDurationMs!;
  final end = track.renderEndMs(projectDurationMs);
  final active = math.max(0, end - track.timelineStartMs);
  final count = active == 0 ? 0 : (active + length - 1) ~/ length;
  if (count > 2000) {
    throw const FormatException('For this video, choose a longer music section or turn off looping.');
  }
  final segments = <Map<String, dynamic>>[];
  var cursor = track.timelineStartMs;
  while (cursor < end) {
    final duration = math.min(length, end - cursor);
    segments.add({'sourceStartMs': track.sourceStartMs, 'sourceEndMs': track.sourceStartMs + duration,
      'timelineStartMs': cursor, 'timelineEndMs': cursor + duration});
    cursor += duration;
  }
  return {...track.toJson(), 'renderStartMs': track.timelineStartMs, 'renderEndMs': end,
    'renderFadeInMs': track.renderFadeInMs(projectDurationMs),
    'renderFadeOutMs': track.renderFadeOutMs(projectDurationMs), 'segments': segments};
}
