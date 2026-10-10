import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme.dart';

class MotionSheet extends StatefulWidget {
  const MotionSheet({super.key, required this.clip, required this.ratio,
    required this.localMs, required this.onApply});
  final VideoClip clip;
  final CanvasRatio ratio;
  final int localMs;
  final void Function(ClipFit, bool, List<MotionKeyframe>) onApply;
  @override
  State<MotionSheet> createState() => _MotionSheetState();
}

class _MotionSheetState extends State<MotionSheet> {
  late List<MotionKeyframe> _frames;
  late ClipFit _fit;
  late bool _flip;
  late int _local;
  int? _selectedSource;
  int get _source => _selectedSource ?? widget.clip.sourcePositionAt(_local);
  MotionKeyframe get _value => motionAt(_frames, _source);
  @override
  void initState() {
    super.initState(); _frames = [...widget.clip.keyframes];
    _fit = widget.clip.fit; _flip = widget.clip.flipX;
    _local = widget.localMs.clamp(0, widget.clip.durationMs).toInt();
  }
  void _put(MotionKeyframe value) => setState(() {
    _frames.removeWhere((frame) => frame.sourceMs == value.sourceMs);
    _frames.add(value); _frames.sort((a, b) => a.sourceMs.compareTo(b.sourceMs));
  });
  Widget _slider(String label, double value, double min, double max, ValueChanged<double> changed) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: changed),
    ]);
  @override
  Widget build(BuildContext context) {
    final value = _value;
    final hasKey = _frames.any((frame) => frame.sourceMs == _source);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Frame & motion', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10), const Text('Scrub to a moment and adjust it to set a keyframe. Motion blends between points.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
      const SizedBox(height: 16), Center(child: SizedBox(height: 160, child: AspectRatio(
        aspectRatio: widget.ratio.aspect, child: ClipRect(child: ColoredBox(color: Colors.black,
          child: LayoutBuilder(builder: (_, box) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..translate(value.x * box.maxWidth, value.y * box.maxHeight)
              ..rotateZ(value.rotation * math.pi / 180)..scale(value.zoom * (_flip ? -1 : 1), value.zoom),
            child: SizedBox.expand(child: widget.clip.thumbnailPath == null ? const Icon(Icons.movie_outlined, color: muted)
              : Image.file(File(widget.clip.thumbnailPath!), fit: _fit == ClipFit.fill ? BoxFit.cover : BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie_outlined, color: muted))),
          ))))))),
      const SizedBox(height: 8), const Text('Thumbnail framing preview', style: TextStyle(color: muted, fontSize: 10)),
      const SizedBox(height: 14), Wrap(spacing: 8, children: [
        for (final fit in ClipFit.values) ChoiceChip(label: Text(fit == ClipFit.fill ? 'Fill / crop' : 'Fit'),
          selected: _fit == fit, onSelected: (_) => setState(() => _fit = fit)),
        FilterChip(label: const Text('Mirror'), selected: _flip, onSelected: (v) => setState(() => _flip = v)),
      ]),
      const SizedBox(height: 16), Text('Clip time  ${formatTime(_local, tenths: true)}', style: const TextStyle(color: mint, fontSize: 12)),
      Slider(value: _local.toDouble(), max: widget.clip.durationMs.toDouble(),
        onChanged: (v) => setState(() { _selectedSource = null; _local = v.round(); })),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final frame in _frames.where((f) => f.sourceMs >= widget.clip.startMs && f.sourceMs <= widget.clip.endMs))
          ActionChip(avatar: const Icon(Icons.diamond_outlined, size: 12),
            label: Text(formatTime(widget.clip.timelinePositionAt(frame.sourceMs), tenths: true)),
            onPressed: () => setState(() { _selectedSource = frame.sourceMs; _local = widget.clip.timelinePositionAt(frame.sourceMs); })),
      ]),
      Row(children: [TextButton.icon(onPressed: () => _put(value), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Set point')),
        if (hasKey) TextButton(onPressed: () => setState(() => _frames.removeWhere((f) => f.sourceMs == _source)), child: const Text('Remove point'))]),
      _slider('Zoom  ${value.zoom.toStringAsFixed(2)}×', value.zoom, .25, 4, (v) => _put(value.copyWith(zoom: v))),
      _slider('Horizontal pan  ${(value.x * 100).round()}%', value.x, -1, 1, (v) => _put(value.copyWith(x: v))),
      _slider('Vertical pan  ${(value.y * 100).round()}%', value.y, -1, 1, (v) => _put(value.copyWith(y: v))),
      _slider('Rotation  ${value.rotation.round()}°', value.rotation, -180, 180, (v) => _put(value.copyWith(rotation: v))),
      Wrap(spacing: 8, children: [
        OutlinedButton(onPressed: () => setState(() => _frames = [
          MotionKeyframe(sourceMs: widget.clip.startMs),
          MotionKeyframe(sourceMs: widget.clip.endMs, zoom: 1.3),
        ]), child: const Text('Slow zoom preset')),
        TextButton(onPressed: () => setState(() { _frames = []; _fit = ClipFit.fit; _flip = false; }), child: const Text('Reset')),
      ]),
      const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
        widget.onApply(_fit, _flip, _frames); Navigator.pop(context);
      }, child: const Text('Apply motion'))),
    ]);
  }
}
