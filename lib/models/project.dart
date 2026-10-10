import 'dart:math' as math;
import 'clip_filter.dart';
import 'motion.dart';
import 'image_layer.dart';
import 'music_track.dart';
import 'audio_layer.dart';
export 'motion.dart';
export 'image_layer.dart';
export 'music_track.dart';
export 'audio_layer.dart';

const supportedClipSpeeds = <double>[.25, .5, .75, 1, 1.5, 2, 3, 4];

String newId() => '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}';

enum ClipTransition { none, fade }
enum ClipFit { fit, fill }

enum CanvasRatio {
  portrait(9, 16, '9:16'),
  landscape(16, 9, '16:9'),
  square(1, 1, '1:1');

  const CanvasRatio(this.width, this.height, this.label);
  final int width;
  final int height;
  final String label;
  double get aspect => width / height;
  (int, int) dimensions(int shortEdge) => switch (this) {
    CanvasRatio.portrait => (shortEdge, (shortEdge * 16 / 9).round()),
    CanvasRatio.landscape => ((shortEdge * 16 / 9).round(), shortEdge),
    CanvasRatio.square => (shortEdge, shortEdge),
  };
}

class VideoClip {
  const VideoClip({
    required this.id,
    required this.path,
    required this.name,
    required this.sourceDurationMs,
    required this.endMs,
    this.startMs = 0,
    this.thumbnailPath,
    this.muted = false,
    this.volume = 1,
    this.transition = ClipTransition.none,
    this.speed = 1,
    this.filter = ClipFilter.none,
    this.filterIntensity = 1,
    this.fit = ClipFit.fit,
    this.flipX = false,
    this.keyframes = const [],
  });

  final String id;
  final String path;
  final String name;
  final String? thumbnailPath;
  final int sourceDurationMs;
  final int startMs;
  final int endMs;
  final bool muted;
  final double volume;
  /// Fade through black at the boundary AFTER this clip.
  final ClipTransition transition;
  final double speed;
  final ClipFilter filter;
  final double filterIntensity;
  final ClipFit fit;
  final bool flipX;
  final List<MotionKeyframe> keyframes;
  MotionKeyframe motionAtTimeline(int timelineMs) => motionAt(keyframes, sourcePositionAt(timelineMs));
  int get trimmedDurationMs => endMs - startMs;
  int get durationMs => (trimmedDurationMs / speed).round();
  // Account for the millisecond rounding in the timeline and native exporters.
  double get playbackSpeed => trimmedDurationMs / durationMs;
  int sourcePositionAt(int timelineMs) => startMs +
    (timelineMs.clamp(0, durationMs) * playbackSpeed).round();
  int timelinePositionAt(int sourceMs) =>
    ((sourceMs - startMs).clamp(0, trimmedDurationMs) / playbackSpeed).round();

  VideoClip copyWith({String? id, int? startMs, int? endMs, bool? muted,
    double? volume,
    ClipTransition? transition, double? speed, ClipFilter? filter,
    double? filterIntensity, ClipFit? fit, bool? flipX,
    List<MotionKeyframe>? keyframes}) => VideoClip(
    id: id ?? this.id, path: path, name: name,
    thumbnailPath: thumbnailPath, sourceDurationMs: sourceDurationMs,
    startMs: startMs ?? this.startMs, endMs: endMs ?? this.endMs,
    muted: muted ?? this.muted, transition: transition ?? this.transition,
    volume: volume ?? this.volume,
    speed: speed ?? this.speed, filter: filter ?? this.filter,
    filterIntensity: filterIntensity ?? this.filterIntensity,
    fit: fit ?? this.fit, flipX: flipX ?? this.flipX,
    keyframes: keyframes == null ? this.keyframes : List.unmodifiable(keyframes),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'path': path, 'name': name, 'thumbnailPath': thumbnailPath,
    'sourceDurationMs': sourceDurationMs, 'startMs': startMs,
    'endMs': endMs, 'muted': muted, 'transition': transition.name,
    'volume': volume,
    'speed': speed, 'filter': filter.name, 'filterIntensity': filterIntensity,
    'fit': fit.name, 'flipX': flipX, 'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };
  factory VideoClip.fromJson(Map<String, dynamic> json) {
    final duration = (json['sourceDurationMs'] as num).toInt();
    final start = (json['startMs'] as num).toInt();
    final end = (json['endMs'] as num).toInt();
    final speed = (json['speed'] as num?)?.toDouble() ?? 1;
    final intensity = (json['filterIntensity'] as num?)?.toDouble() ?? 1;
    final volume = (json['volume'] as num?)?.toDouble() ?? 1;
    if (!volume.isFinite || volume < 0 || volume > 1) throw const FormatException('Invalid clip volume');
    final frames = ((json['keyframes'] as List?) ?? []).map((v) =>
      MotionKeyframe.fromJson(Map<String, dynamic>.from(v as Map))).toList();
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].sourceMs > duration || (i > 0 && frames[i].sourceMs <= frames[i - 1].sourceMs)) {
        throw const FormatException('Unsorted or duplicate keyframe timing');
      }
    }
    if (duration < 100 || start < 0 || end > duration || end - start < 100) {
      throw const FormatException('Invalid clip timing');
    }
    if (!supportedClipSpeeds.contains(speed) || !intensity.isFinite || intensity < 0 || intensity > 1) {
      throw const FormatException('Invalid speed or filter intensity');
    }
    return VideoClip(
      id: json['id'] as String, path: json['path'] as String,
      name: json['name'] as String, thumbnailPath: json['thumbnailPath'] as String?,
      sourceDurationMs: duration, startMs: start, endMs: end,
      muted: json['muted'] as bool? ?? false,
      volume: volume,
      transition: json['transition'] == 'fade' ? ClipTransition.fade : ClipTransition.none,
      speed: speed, filterIntensity: intensity,
      fit: json['fit'] == 'fill' ? ClipFit.fill : ClipFit.fit,
      flipX: json['flipX'] as bool? ?? false, keyframes: List.unmodifiable(frames),
      filter: ClipFilter.values.firstWhere((filter) => filter.name == json['filter'], orElse: () => ClipFilter.none),
    );
  }
}

class TextLayer {
  const TextLayer({required this.id, required this.text, required this.startMs,
    required this.endMs, this.y = 0.78, this.size = 0.055, this.color = 0xFFFFFFFF,
    this.isCaption = false});
  final String id;
  final String text;
  final int startMs;
  final int endMs;
  /// Center position and font size relative to the canvas height.
  final double y;
  final double size;
  final int color;
  final bool isCaption;
  TextLayer copyWith({String? text, int? startMs, int? endMs, double? y,
    double? size, int? color, bool? isCaption}) => TextLayer(
    id: id, text: text ?? this.text, startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs, y: y ?? this.y, size: size ?? this.size,
    color: color ?? this.color,
    isCaption: isCaption ?? this.isCaption,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'text': text, 'startMs': startMs, 'endMs': endMs,
    'y': y, 'size': size, 'color': color, 'isCaption': isCaption,
  };
  factory TextLayer.fromJson(Map<String, dynamic> json) {
    final start = (json['startMs'] as num).toInt(), end = (json['endMs'] as num).toInt();
    final y = (json['y'] as num).toDouble(), size = (json['size'] as num).toDouble();
    final text = json['text'] as String;
    if (start < 0 || end <= start || !y.isFinite || !size.isFinite || text.trim().isEmpty) {
      throw const FormatException('Invalid text layer');
    }
    return TextLayer(id: json['id'] as String, text: text, startMs: start, endMs: end,
      y: y.clamp(.1, .9).toDouble(), size: size.clamp(.025, .09).toDouble(),
      color: (json['color'] as num).toInt(), isCaption: json['isCaption'] as bool? ?? false);
  }
}

class VideoProject {
  VideoProject({required this.id, required this.name, required this.updatedAt,
    List<VideoClip> clips = const [], List<TextLayer> texts = const [],
    List<ImageLayer> images = const [], List<AudioLayer> audioLayers = const [],
    this.frameRate = 30,
    this.music, this.ratio = CanvasRatio.portrait})
      : clips = List.unmodifiable(clips), texts = List.unmodifiable(texts), images = List.unmodifiable(images),
        audioLayers = List.unmodifiable(audioLayers);
  final String id;
  final String name;
  final DateTime updatedAt;
  final List<VideoClip> clips;
  final List<TextLayer> texts;
  final List<ImageLayer> images;
  /// The soundtrack retains its legacy slot; seven more layers can overlap it.
  final List<AudioLayer> audioLayers;
  final MusicTrack? music;
  List<AudioLayer> get audioTracks => [
    if (music != null) AudioLayer(id: soundtrackId, track: music!, kind: AudioKind.music),
    ...audioLayers,
  ];
  final CanvasRatio ratio;
  final int frameRate;
  int get durationMs => clips.fold(0, (sum, clip) => sum + clip.durationMs);
  int clipOffset(int index) => clips.take(index).fold(0, (sum, c) => sum + c.durationMs);
  int clipAt(int positionMs) {
    var offset = 0;
    for (var i = 0; i < clips.length; i++) {
      offset += clips[i].durationMs;
      if (positionMs < offset) return i;
    }
    return clips.isEmpty ? -1 : clips.length - 1;
  }
  VideoProject copyWith({String? name, List<VideoClip>? clips,
    List<TextLayer>? texts, MusicTrack? music, bool removeMusic = false,
    List<ImageLayer>? images, List<AudioLayer>? audioLayers,
    int? frameRate,
    CanvasRatio? ratio}) => VideoProject(
    id: id, name: name ?? this.name, updatedAt: DateTime.now(),
    clips: clips ?? this.clips, texts: texts ?? this.texts,
    images: images ?? this.images,
    audioLayers: audioLayers ?? this.audioLayers,
    frameRate: frameRate ?? this.frameRate,
    music: removeMusic ? null : music ?? this.music, ratio: ratio ?? this.ratio,
  );
  Map<String, dynamic> toJson() => {
    'schemaVersion': 5, 'id': id, 'name': name,
    'updatedAt': updatedAt.toIso8601String(), 'ratio': ratio.name,
    'clips': clips.map((c) => c.toJson()).toList(),
    'texts': texts.map((t) => t.toJson()).toList(), 'music': music?.toJson(),
    'images': images.map((image) => image.toJson()).toList(),
    'frameRate': frameRate,
    'audioLayers': audioLayers.map((layer) => layer.toJson()).toList(),
  };
  factory VideoProject.fromJson(Map<String, dynamic> json) {
    if (![1, 2, 3, 4, 5].contains(json['schemaVersion'])) {
      throw const FormatException('Unsupported project version');
    }
    final frameRate = (json['frameRate'] as num?)?.toInt() ?? 30;
    if (![24, 30, 60].contains(frameRate)) throw const FormatException('Unsupported project frame rate');
    final audioLayers = ((json['audioLayers'] as List?) ?? []).map((value) =>
      AudioLayer.fromJson(Map<String, dynamic>.from(value as Map))).toList();
    if (audioLayers.length > maxAdditionalAudioLayers || audioLayers.map((layer) => layer.id).toSet().length != audioLayers.length) {
      throw const FormatException('Too many or duplicate audio layers');
    }
    return VideoProject(
      id: json['id'] as String, name: json['name'] as String,
      frameRate: frameRate,
      audioLayers: audioLayers,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      clips: (json['clips'] as List).map((v) => VideoClip.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
      texts: (json['texts'] as List).map((v) => TextLayer.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
      images: ((json['images'] as List?) ?? []).map((v) => ImageLayer.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
      music: json['music'] == null ? null : MusicTrack.fromJson(Map<String, dynamic>.from(json['music'] as Map)),
      ratio: CanvasRatio.values.firstWhere((r) => r.name == json['ratio'], orElse: () => CanvasRatio.portrait),
    );
  }
}

String formatTime(int milliseconds, {bool tenths = false}) {
  final seconds = milliseconds ~/ 1000;
  final base = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  return tenths ? '$base.${(milliseconds % 1000) ~/ 100}' : base;
}
