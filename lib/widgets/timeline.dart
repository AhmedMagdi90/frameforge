import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../state/editor_controller.dart';
import '../theme.dart';
import 'audio_timeline.dart';

class EditorTimeline extends StatelessWidget {
  const EditorTimeline({super.key, required this.editor, required this.onSeek,
    required this.onAdd, required this.onText, required this.onMusic, required this.onAudioLayer, required this.onImage});
  final EditorController editor;
  final ValueChanged<int> onSeek;
  final VoidCallback onAdd;
  final ValueChanged<TextLayer> onText;
  final VoidCallback onMusic;
  final ValueChanged<AudioLayer> onAudioLayer;
  final ValueChanged<ImageLayer> onImage;
  @override
  Widget build(BuildContext context) {
    final project = editor.project;
    return Container(padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(color: surface, border: Border(top: BorderSide(color: elevated))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          const Icon(Icons.layers_outlined, size: 14, color: muted), const SizedBox(width: 6),
          const Text('TIMELINE', style: TextStyle(fontSize: 10, letterSpacing: 1.7, color: muted)),
          const Spacer(), PopupMenuButton<int>(tooltip: 'Frame grid and default export rate',
            initialValue: project.frameRate, onSelected: editor.setFrameRate,
            itemBuilder: (_) => [for (final fps in [24, 30, 60]) PopupMenuItem(value: fps, child: Text('$fps fps'))],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text('${project.frameRate} fps', style: const TextStyle(color: mint, fontSize: 11)))),
          IconButton(tooltip: editor.snapEnabled ? 'Turn off snapping to clip boundaries' : 'Snap to clip boundaries',
            visualDensity: VisualDensity.compact, onPressed: editor.toggleSnap,
            icon: Icon(Icons.vertical_align_center_rounded, size: 18, color: editor.snapEnabled ? mint : muted)),
          const SizedBox(width: 6), IconButton(tooltip: 'Add videos', visualDensity: VisualDensity.compact,
            onPressed: onAdd, icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: violet)),
        ])),
        if (project.clips.isEmpty) Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(
          onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add your first video')))
        else ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Slider(
            value: editor.positionMs.toDouble(), max: project.durationMs.toDouble(),
            onChanged: (value) => onSeek(value.round()),
            label: formatTime(editor.positionMs, tenths: true))),
          SizedBox(height: 76, child: ReorderableListView.builder(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: project.clips.length,
            buildDefaultDragHandles: false, onReorder: editor.reorder,
            proxyDecorator: (child, _, animation) => Material(color: Colors.transparent,
              child: ScaleTransition(scale: animation.drive(Tween(begin: 1.0, end: 1.04)), child: child)),
            itemBuilder: (context, index) {
              final clip = project.clips[index];
              final selected = editor.selectedId == clip.id;
              return ReorderableDelayedDragStartListener(key: ValueKey(clip.id), index: index,
                child: Padding(padding: const EdgeInsets.only(right: 5), child: GestureDetector(
                  onTap: () { editor.select(clip.id); onSeek(project.clipOffset(index)); },
                  child: Container(width: math.max(82, math.min(180, clip.durationMs / 1000 * 18)),
                    decoration: BoxDecoration(color: elevated, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? violet : Colors.transparent, width: 2)),
                    clipBehavior: Clip.antiAlias, child: Stack(fit: StackFit.expand, children: [
                      if (clip.thumbnailPath != null) Image.file(File(clip.thumbnailPath!), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie_outlined, color: muted))),
                      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xBB000000)]))),
                      Positioned(left: 7, top: 6, child: Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                      if (clip.speed != 1) Positioned(left: 7, top: 22, child: Text('${clip.speed}×',
                        style: const TextStyle(color: mint, fontSize: 9, fontWeight: FontWeight.w600))),
                      Positioned(left: 7, bottom: 7, child: Text('${(clip.durationMs / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600))),
                      if (clip.muted) const Positioned(right: 6, top: 6, child: Icon(Icons.volume_off_rounded, size: 13)),
                      if (clip.transition == ClipTransition.fade && index < project.clips.length - 1)
                        const Positioned(right: 6, bottom: 6, child: Icon(Icons.gradient_rounded, size: 14, color: mint)),
                    ])))));
            })),
          AudioTimeline(project: project, positionMs: editor.positionMs, onEdit: (layer) {
            if (layer.id == soundtrackId) { onMusic(); } else { onAudioLayer(layer); }
          }, onMute: editor.toggleAudioMute),
          const SizedBox(height: 8),
          SizedBox(height: 28, child: ListView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final image in project.images) _TrackChip(icon: Icons.image_outlined, color: mint,
                label: image.name, onTap: () => onImage(image)),
              for (final text in project.texts.where((t) => !t.isCaption)) _TrackChip(icon: Icons.text_fields_rounded, color: violet,
                label: text.text, onTap: () => onText(text)),
              for (final text in project.texts.where((t) => t.isCaption && editor.positionMs >= t.startMs && editor.positionMs < t.endMs))
                _TrackChip(icon: Icons.closed_caption_outlined, color: violet, label: text.text, onTap: () => onText(text)),
              if (project.texts.any((t) => t.isCaption)) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text('${project.texts.where((t) => t.isCaption).length} captions', style: const TextStyle(color: muted, fontSize: 10))),
              if (project.audioTracks.isEmpty && project.texts.isEmpty && project.images.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 5), child: Text('Add audio and text to build your story',
                  style: TextStyle(color: muted, fontSize: 10))),
            ])),
        ],
      ]));
  }
}

class _TrackChip extends StatelessWidget {
  const _TrackChip({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 6), child: InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(6), child: Container(
      constraints: const BoxConstraints(maxWidth: 170), padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 13),
        const SizedBox(width: 4), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 10)))]))));
}
