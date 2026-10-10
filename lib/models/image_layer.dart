class ImageLayer {
  const ImageLayer({required this.id, required this.path, required this.name,
    required this.startMs, required this.endMs, required this.aspect,
    this.x = .5, this.y = .5, this.width = .35, this.rotation = 0, this.opacity = 1});
  final String id;
  final String path;
  final String name;
  final int startMs;
  final int endMs;
  final double aspect;
  /// Center and width relative to the canvas; height preserves image aspect.
  final double x, y, width, rotation, opacity;
  bool get isValid => startMs >= 0 && endMs > startMs && aspect.isFinite && aspect > 0 &&
    x.isFinite && x >= 0 && x <= 1 && y.isFinite && y >= 0 && y <= 1 &&
    width.isFinite && width >= .05 && width <= 1.5 && rotation.isFinite && rotation.abs() <= 180 &&
    opacity.isFinite && opacity >= 0 && opacity <= 1;
  ImageLayer copyWith({int? startMs, int? endMs, double? x, double? y,
    double? width, double? rotation, double? opacity}) => ImageLayer(
    id: id, path: path, name: name, aspect: aspect,
    startMs: startMs ?? this.startMs, endMs: endMs ?? this.endMs,
    x: x ?? this.x, y: y ?? this.y, width: width ?? this.width,
    rotation: rotation ?? this.rotation, opacity: opacity ?? this.opacity);
  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'name': name,
    'startMs': startMs, 'endMs': endMs, 'aspect': aspect, 'x': x, 'y': y,
    'width': width, 'rotation': rotation, 'opacity': opacity};
  factory ImageLayer.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num).toDouble();
    final layer = ImageLayer(id: json['id'] as String, path: json['path'] as String,
      name: json['name'] as String, startMs: (json['startMs'] as num).toInt(),
      endMs: (json['endMs'] as num).toInt(), aspect: number('aspect'),
      x: number('x'), y: number('y'), width: number('width'),
      rotation: number('rotation'), opacity: number('opacity'));
    if (!layer.isValid) {
      throw const FormatException('Invalid image overlay');
    }
    return layer;
  }
}
