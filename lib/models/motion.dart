/// Values use canvas fractions for pan and clockwise degrees for rotation.
/// Keyframes use source timestamps so trimming, splitting and speed changes
/// preserve the animation at the same source frames.
class MotionKeyframe {
  const MotionKeyframe({required this.sourceMs, this.zoom = 1, this.x = 0,
    this.y = 0, this.rotation = 0});
  final int sourceMs;
  final double zoom;
  final double x;
  final double y;
  final double rotation;
  bool get isValid => sourceMs >= 0 && zoom.isFinite && zoom >= .25 && zoom <= 4 &&
    x.isFinite && x.abs() <= 1 && y.isFinite && y.abs() <= 1 &&
    rotation.isFinite && rotation.abs() <= 180;
  MotionKeyframe copyWith({int? sourceMs, double? zoom, double? x, double? y,
    double? rotation}) => MotionKeyframe(sourceMs: sourceMs ?? this.sourceMs,
    zoom: zoom ?? this.zoom, x: x ?? this.x, y: y ?? this.y,
    rotation: rotation ?? this.rotation);
  Map<String, dynamic> toJson() => {'sourceMs': sourceMs, 'zoom': zoom,
    'x': x, 'y': y, 'rotation': rotation};
  factory MotionKeyframe.fromJson(Map<String, dynamic> json) {
    final value = MotionKeyframe(sourceMs: (json['sourceMs'] as num).toInt(),
      zoom: (json['zoom'] as num).toDouble(), x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(), rotation: (json['rotation'] as num).toDouble());
    if (!value.isValid) throw const FormatException('Invalid motion keyframe');
    return value;
  }
}

MotionKeyframe motionAt(List<MotionKeyframe> frames, int sourceMs) {
  if (frames.isEmpty) return MotionKeyframe(sourceMs: sourceMs);
  if (sourceMs <= frames.first.sourceMs) return frames.first.copyWith(sourceMs: sourceMs);
  if (sourceMs >= frames.last.sourceMs) return frames.last.copyWith(sourceMs: sourceMs);
  for (var i = 1; i < frames.length; i++) {
    final right = frames[i];
    if (sourceMs > right.sourceMs) continue;
    final left = frames[i - 1];
    final t = (sourceMs - left.sourceMs) / (right.sourceMs - left.sourceMs);
    double lerp(double a, double b) => a + (b - a) * t;
    return MotionKeyframe(sourceMs: sourceMs, zoom: lerp(left.zoom, right.zoom),
      x: lerp(left.x, right.x), y: lerp(left.y, right.y),
      rotation: lerp(left.rotation, right.rotation));
  }
  return frames.last.copyWith(sourceMs: sourceMs);
}
