import 'dart:io';
import 'package:flutter/material.dart';
import '../models/clip_filter.dart';
import '../models/project.dart';
import '../theme.dart';
import '../widgets/filtered_video.dart';

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.clip, required this.onApply});
  final VideoClip clip;
  final void Function(ClipFilter filter, double intensity) onApply;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late ClipFilter _filter;
  late double _intensity;
  @override
  void initState() { super.initState(); _filter = widget.clip.filter; _intensity = widget.clip.filterIntensity; }

  Widget _thumbnail(ClipFilter filter, double intensity) => FilteredVideo(filter: filter, intensity: intensity,
    child: widget.clip.thumbnailPath == null ? const ColoredBox(color: elevated, child: Icon(Icons.movie_outlined, color: muted))
      : Image.file(File(widget.clip.thumbnailPath!), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: elevated, child: Icon(Icons.movie_outlined, color: muted))));

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Find your look', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8), const Text('Apply a filter to this clip.', style: TextStyle(color: muted, fontSize: 12)),
    const SizedBox(height: 20), ClipRRect(borderRadius: BorderRadius.circular(14),
      child: SizedBox(height: 150, width: double.infinity, child: _thumbnail(_filter, _intensity))),
    const SizedBox(height: 20), SizedBox(height: 102, child: ListView(scrollDirection: Axis.horizontal, children: [
      for (final filter in ClipFilter.values) Padding(padding: const EdgeInsets.only(right: 10),
        child: InkWell(onTap: () => setState(() => _filter = filter), borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 70, child: Column(children: [Container(height: 70, width: 70,
            clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              border: Border.all(color: filter == _filter ? violet : Colors.transparent, width: 2)),
            child: _thumbnail(filter, 1)), const SizedBox(height: 8),
            Text(filter.label, style: TextStyle(color: filter == _filter ? violet : muted, fontSize: 11))])))),
    ])),
    const SizedBox(height: 10), Text('Intensity  ${(_intensity * 100).round()}%', style: const TextStyle(fontSize: 12, color: muted)),
    Slider(value: _intensity, onChanged: _filter == ClipFilter.none ? null : (value) => setState(() => _intensity = value)),
    const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
      widget.onApply(_filter, _intensity); Navigator.pop(context);
    }, child: const Text('Apply filter'))),
  ]);
}
