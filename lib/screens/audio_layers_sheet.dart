import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/timeline_grid.dart';
import '../state/editor_controller.dart';
import '../theme.dart';

class AudioLayersSheet extends StatelessWidget {
  const AudioLayersSheet({super.key, required this.editor, required this.onSoundtrack,
    required this.onAdd, required this.onEdit});
  final EditorController editor;
  final VoidCallback onSoundtrack;
  final ValueChanged<AudioKind> onAdd;
  final ValueChanged<AudioLayer> onEdit;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: editor, builder: (context, _) {
    final project = editor.project;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Audio mixer', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), const Text('Combine a soundtrack with up to seven music, voice or sound effect layers.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
      const SizedBox(height: 18),
      if (project.music == null) OutlinedButton.icon(onPressed: () { Navigator.pop(context); onSoundtrack(); },
        icon: const Icon(Icons.music_note_rounded, size: 18), label: const Text('Add soundtrack'))
      else _row(context, AudioLayer(id: soundtrackId, track: project.music!, kind: AudioKind.music),
        title: 'Soundtrack', onEdit: () { Navigator.pop(context); onSoundtrack(); }),
      for (final layer in project.audioLayers) _row(context, layer,
        title: layer.kind.label, onEdit: () { Navigator.pop(context); onEdit(layer); }),
      const SizedBox(height: 18), Text('${project.audioLayers.length} / $maxAdditionalAudioLayers additional layers',
        style: const TextStyle(color: muted, fontSize: 11)),
      const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: [
        for (final kind in AudioKind.values) OutlinedButton.icon(
          onPressed: project.audioLayers.length >= maxAdditionalAudioLayers ? null : () {
            Navigator.pop(context); onAdd(kind);
          }, icon: Icon(_icon(kind), size: 16), label: Text('Add ${kind.label.toLowerCase()}')),
      ]),
      const SizedBox(height: 16), const Text('Voice audio imports a recording from your device. Lower combined volumes if the mix distorts.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
      const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton(
        onPressed: () => Navigator.pop(context), child: const Text('Done'))),
    ]);
  });

  Widget _row(BuildContext context, AudioLayer layer, {required String title, required VoidCallback onEdit}) =>
    Padding(padding: const EdgeInsets.only(bottom: 6), child: DecoratedBox(
      decoration: BoxDecoration(color: elevated, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: ListTile(dense: true, onTap: onEdit, contentPadding: const EdgeInsets.only(left: 12),
          leading: Icon(_icon(layer.kind), color: layer.track.muted ? muted : mint, size: 21),
          title: Text(layer.track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          subtitle: Text('$title · ${formatPreciseTime(layer.track.timelineStartMs)} · ${(layer.track.volume * 100).round()}%',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 10)))),
        IconButton(tooltip: layer.track.muted ? 'Unmute layer' : 'Mute layer', visualDensity: VisualDensity.compact,
          onPressed: () => editor.toggleAudioMute(layer.id), icon: Icon(layer.track.muted
            ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: layer.track.muted ? muted : mint, size: 18)),
        PopupMenuButton<String>(tooltip: 'Layer actions', onSelected: (action) {
          if (action == 'edit') { onEdit(); }
          else if (action == 'duplicate') {
            if (!editor.duplicateAudioLayer(layer.id, timelineStartMs: editor.positionMs)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seven additional audio layers are already in use.')));
            }
          } else if (layer.id == soundtrackId) { editor.setMusic(null); }
          else { editor.removeAudioLayer(layer.id); }
        }, itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit timing and sound')),
          if (layer.id != soundtrackId) const PopupMenuItem(value: 'duplicate', child: Text('Duplicate at playhead')),
          const PopupMenuItem(value: 'remove', child: Text('Remove layer')),
        ]),
      ])));

  IconData _icon(AudioKind kind) => switch (kind) {
    AudioKind.music => Icons.music_note_rounded,
    AudioKind.voice => Icons.mic_none_rounded,
    AudioKind.effect => Icons.graphic_eq_rounded,
  };
}
