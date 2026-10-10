import 'dart:math' as math;

class MusicTrack {
  const MusicTrack({required this.path, required this.name, this.volume = .6,
    this.sourceDurationMs, this.sourceStartMs = 0, this.sourceEndMs,
    this.timelineStartMs = 0, this.loop = true, this.fadeInMs = 0, this.fadeOutMs = 0,
    this.muted = false});
  final String path, name;
  final double volume;
  /// Null for legacy drafts until the source is inspected on the device.
  final int? sourceDurationMs, sourceEndMs;
  final int sourceStartMs, timelineStartMs, fadeInMs, fadeOutMs;
  final bool loop, muted;
  int? get effectiveEndMs => sourceEndMs ?? sourceDurationMs;
  int? get trimmedDurationMs => effectiveEndMs == null ? null : effectiveEndMs! - sourceStartMs;
  bool get isValid => volume.isFinite && volume >= 0 && volume <= 1 &&
    sourceStartMs >= 0 && timelineStartMs >= 0 &&
    fadeInMs >= 0 && fadeInMs <= 10000 && fadeOutMs >= 0 && fadeOutMs <= 10000 &&
    (sourceDurationMs == null || sourceDurationMs! >= 100) &&
    (effectiveEndMs == null || effectiveEndMs! - sourceStartMs >= 100) &&
    (sourceDurationMs == null || effectiveEndMs! <= sourceDurationMs!);

  int renderEndMs(int projectDurationMs) {
    final length = trimmedDurationMs;
    if (length == null) throw StateError('Inspect music before using its timing.');
    return loop ? projectDurationMs : math.min(projectDurationMs, timelineStartMs + length);
  }
  int activeDurationMs(int projectDurationMs) => math.max(0, renderEndMs(projectDurationMs) - timelineStartMs);
  int renderFadeInMs(int projectDurationMs) => math.min(fadeInMs, activeDurationMs(projectDurationMs) ~/ 2);
  int renderFadeOutMs(int projectDurationMs) => math.min(fadeOutMs, activeDurationMs(projectDurationMs) ~/ 2);
  int? sourcePositionAt(int timelineMs, int projectDurationMs) {
    final length = trimmedDurationMs;
    if (length == null) throw StateError('Inspect music before seeking it.');
    if (timelineMs < timelineStartMs || timelineMs >= renderEndMs(projectDurationMs)) return null;
    final local = timelineMs - timelineStartMs;
    return sourceStartMs + (loop ? local % length : local);
  }
  double gainAt(int timelineMs, int projectDurationMs) {
    if (muted) return 0;
    if (sourcePositionAt(timelineMs, projectDurationMs) == null) return 0;
    final fadeIn = renderFadeInMs(projectDurationMs), fadeOut = renderFadeOutMs(projectDurationMs);
    var gain = 1.0;
    if (fadeIn > 0) gain = math.min(gain, (timelineMs - timelineStartMs) / fadeIn);
    if (fadeOut > 0) gain = math.min(gain, (renderEndMs(projectDurationMs) - timelineMs) / fadeOut);
    return volume * gain.clamp(0, 1);
  }

  MusicTrack copyWith({double? volume, int? sourceDurationMs, int? sourceStartMs,
    int? sourceEndMs, int? timelineStartMs, bool? loop, int? fadeInMs, int? fadeOutMs,
    bool? muted}) => MusicTrack(
    path: path, name: name, volume: volume ?? this.volume,
    sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
    sourceStartMs: sourceStartMs ?? this.sourceStartMs, sourceEndMs: sourceEndMs ?? this.sourceEndMs,
    timelineStartMs: timelineStartMs ?? this.timelineStartMs, loop: loop ?? this.loop,
    fadeInMs: fadeInMs ?? this.fadeInMs, fadeOutMs: fadeOutMs ?? this.fadeOutMs,
    muted: muted ?? this.muted);
  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'volume': volume,
    'sourceDurationMs': sourceDurationMs, 'sourceStartMs': sourceStartMs, 'sourceEndMs': sourceEndMs,
    'timelineStartMs': timelineStartMs, 'loop': loop, 'fadeInMs': fadeInMs, 'fadeOutMs': fadeOutMs,
    'muted': muted};
  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final track = MusicTrack(path: json['path'] as String, name: json['name'] as String,
      volume: (json['volume'] as num).toDouble(),
      sourceDurationMs: (json['sourceDurationMs'] as num?)?.toInt(),
      sourceStartMs: (json['sourceStartMs'] as num?)?.toInt() ?? 0,
      sourceEndMs: (json['sourceEndMs'] as num?)?.toInt(),
      timelineStartMs: (json['timelineStartMs'] as num?)?.toInt() ?? 0,
      loop: json['loop'] as bool? ?? true,
      fadeInMs: (json['fadeInMs'] as num?)?.toInt() ?? 0,
      fadeOutMs: (json['fadeOutMs'] as num?)?.toInt() ?? 0,
      muted: json['muted'] as bool? ?? false);
    if (!track.isValid) throw const FormatException('Invalid music timing or volume');
    return track;
  }
}
