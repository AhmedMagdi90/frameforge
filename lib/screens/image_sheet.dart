import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme.dart';

class ImageSheet extends StatefulWidget {
  const ImageSheet({super.key, required this.layer, required this.project,
    required this.onSave, required this.onDelete});
  final ImageLayer layer;
  final VideoProject project;
  final ValueChanged<ImageLayer> onSave;
  final ValueChanged<String> onDelete;
  @override
  State<ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends State<ImageSheet> {
  late ImageLayer _layer;
  @override
  void initState() { super.initState(); _layer = widget.layer; }
  Widget _slider(String label, double value, double min, double max, ValueChanged<double> changed) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      Slider(value: value, min: min, max: max, onChanged: changed),
    ]);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Image overlay', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8), Text(_layer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 12)),
    const SizedBox(height: 14), Center(child: SizedBox(height: 170, child: AspectRatio(
      aspectRatio: widget.project.ratio.aspect, child: ClipRect(child: ColoredBox(color: Colors.black,
        child: LayoutBuilder(builder: (_, box) => Stack(children: [Positioned(
          left: box.maxWidth * _layer.x, top: box.maxHeight * _layer.y,
          child: FractionalTranslation(translation: const Offset(-.5, -.5),
            child: Transform.rotate(angle: _layer.rotation * math.pi / 180,
              child: Opacity(opacity: _layer.opacity, child: Image.file(File(_layer.path),
                width: box.maxWidth * _layer.width, height: box.maxWidth * _layer.width / _layer.aspect,
                fit: BoxFit.fill, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))))),
        )]))))))),
    const SizedBox(height: 16),
    _slider('Horizontal position', _layer.x, 0, 1, (v) => setState(() => _layer = _layer.copyWith(x: v))),
    _slider('Vertical position', _layer.y, 0, 1, (v) => setState(() => _layer = _layer.copyWith(y: v))),
    _slider('Width  ${(_layer.width * 100).round()}%', _layer.width, .05, 1.5, (v) => setState(() => _layer = _layer.copyWith(width: v))),
    _slider('Rotation  ${_layer.rotation.round()}°', _layer.rotation, -180, 180, (v) => setState(() => _layer = _layer.copyWith(rotation: v))),
    _slider('Opacity  ${(_layer.opacity * 100).round()}%', _layer.opacity, 0, 1, (v) => setState(() => _layer = _layer.copyWith(opacity: v))),
    Text('Visible  ${formatTime(_layer.startMs, tenths: true)} – ${formatTime(_layer.endMs, tenths: true)}', style: const TextStyle(color: muted, fontSize: 12)),
    RangeSlider(values: RangeValues(_layer.startMs.toDouble(), _layer.endMs.toDouble()),
      max: widget.project.durationMs.toDouble(), onChanged: (v) {
        if (v.end - v.start >= 100) setState(() => _layer = _layer.copyWith(startMs: v.start.round(), endMs: v.end.round()));
      }),
    const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
      widget.onSave(_layer); Navigator.pop(context);
    }, child: const Text('Apply overlay'))),
    Center(child: TextButton(onPressed: () { widget.onDelete(_layer.id); Navigator.pop(context); }, child: const Text('Remove overlay'))),
  ]);
}
