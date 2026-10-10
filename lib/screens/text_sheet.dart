import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme.dart';

class TextSheet extends StatefulWidget {
  const TextSheet({super.key, required this.project, required this.positionMs,
    required this.onSave, required this.onDelete, this.existing, this.caption = false});
  final VideoProject project;
  final int positionMs;
  final TextLayer? existing;
  final bool caption;
  final ValueChanged<TextLayer> onSave;
  final ValueChanged<String> onDelete;
  @override
  State<TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<TextSheet> {
  late final TextEditingController _text;
  late RangeValues _timing;
  late double _y;
  late double _size;
  late int _color;
  @override
  void initState() {
    super.initState();
    final layer = widget.existing;
    final start = math.min(widget.positionMs, math.max(0, widget.project.durationMs - 100));
    _text = TextEditingController(text: layer?.text ?? 'Your story, your words');
    _timing = RangeValues((layer?.startMs ?? start).toDouble(),
      (layer?.endMs ?? math.min(widget.project.durationMs, start + 3000)).toDouble());
    _y = layer?.y ?? .78; _size = layer?.size ?? .055; _color = layer?.color ?? 0xFFFFFFFF;
  }
  @override
  Widget build(BuildContext context) => SafeArea(child: SingleChildScrollView(
    padding: EdgeInsets.only(left: 22, right: 22, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.caption || widget.existing?.isCaption == true ? 'Edit caption' : 'Put it into words',
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      const SizedBox(height: 18), TextField(controller: _text, maxLength: widget.caption || widget.existing?.isCaption == true ? 300 : 120,
        minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'Type your text'),
        onChanged: (_) => setState(() {})),
      const SizedBox(height: 6), Wrap(spacing: 12, children: [0xFFFFFFFF, 0xFFA99AFF, 0xFF9FE7CF, 0xFFFFDB91, 0xFFFFA9AB]
        .map((color) => GestureDetector(onTap: () => setState(() => _color = color),
          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle,
            border: Border.all(color: color == _color ? Colors.white : Colors.transparent, width: 3)),
            child: color == _color ? const Icon(Icons.check_rounded, color: ink, size: 17) : null))).toList()),
      const SizedBox(height: 24), const Text('Position', style: TextStyle(fontSize: 12, color: muted)),
      Slider(value: _y, min: .1, max: .9, onChanged: (value) => setState(() => _y = value)),
      const Text('Text size', style: TextStyle(fontSize: 12, color: muted)),
      Slider(value: _size, min: .025, max: .09, onChanged: (value) => setState(() => _size = value)),
      Text('Visible  ${formatTime(_timing.start.round(), tenths: true)} – ${formatTime(_timing.end.round(), tenths: true)}',
        style: const TextStyle(fontSize: 12, color: muted)),
      RangeSlider(values: _timing, max: widget.project.durationMs.toDouble(),
        onChanged: (value) { if (value.end - value.start >= 100) setState(() => _timing = value); }),
      const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _text.text.trim().isEmpty ? null : () {
          widget.onSave(TextLayer(id: widget.existing?.id ?? newId(), text: _text.text.trim(),
            startMs: _timing.start.round(), endMs: _timing.end.round(), y: _y, size: _size, color: _color,
            isCaption: widget.caption || widget.existing?.isCaption == true));
          Navigator.pop(context);
        }, child: const Text('Apply text'))),
      if (widget.existing != null) Center(child: TextButton(onPressed: () {
        widget.onDelete(widget.existing!.id); Navigator.pop(context);
      }, child: const Text('Remove text'))),
    ])));
  @override
  void dispose() { _text.dispose(); super.dispose(); }
}
