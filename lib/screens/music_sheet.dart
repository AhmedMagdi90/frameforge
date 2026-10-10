import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/timeline_grid.dart';
import '../theme.dart';

class MusicSheet extends StatefulWidget {
  const MusicSheet({super.key, required this.track, required this.durationMs,
    required this.onSave, required this.onReplace, required this.onRemove,
    this.title = 'Soundtrack studio'});
  final String title;
  final MusicTrack track;
  final int durationMs;
  final ValueChanged<MusicTrack> onSave;
  final VoidCallback onReplace, onRemove;
  @override
  State<MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<MusicSheet> {
  late MusicTrack _track;
  @override
  void initState() { super.initState(); _track = widget.track; }
  Future<void> _enterTime(String title, int initial, int minimum, int maximum, ValueChanged<int> apply) async {
    final input = TextEditingController(text: formatPreciseTime(initial));
    String? error;
    final value = await showDialog<int>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: Text(title),
        content: TextField(controller: input, autofocus: true, keyboardType: TextInputType.datetime,
          decoration: InputDecoration(hintText: 'M:SS.mmm or seconds', errorText: error,
            helperText: '${formatPreciseTime(minimum)} – ${formatPreciseTime(maximum)}')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            try {
              final position = TimelineGrid.parseTime(input.text);
              if (position < minimum || position > maximum) throw const FormatException('Choose a time in the displayed range.');
              Navigator.pop(dialogContext, position);
            } on FormatException catch (e) { update(() => error = e.message); }
          }, child: const Text('Set time'))])));
    if (mounted && value != null) setState(() => apply(value));
    await Future<void>.delayed(const Duration(milliseconds: 300)); input.dispose();
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(widget.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8), Text(_track.name, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: mint, fontSize: 13)),
    const SizedBox(height: 22), Text('Source section  ${formatPreciseTime(_track.sourceStartMs)} – ${formatPreciseTime(_track.effectiveEndMs!)}',
      style: const TextStyle(color: muted, fontSize: 12)),
    RangeSlider(values: RangeValues(_track.sourceStartMs.toDouble(), _track.effectiveEndMs!.toDouble()),
      max: _track.sourceDurationMs!.toDouble(), onChanged: (range) {
        if (range.end - range.start >= 100) setState(() => _track = _track.copyWith(
          sourceStartMs: range.start.round(), sourceEndMs: range.end.round()));
      }),
    Wrap(spacing: 8, children: [
      TextButton(onPressed: () => _enterTime('Source in', _track.sourceStartMs, 0, _track.effectiveEndMs! - 100,
        (value) => _track = _track.copyWith(sourceStartMs: value)), child: const Text('Set in time')),
      TextButton(onPressed: () => _enterTime('Source out', _track.effectiveEndMs!, _track.sourceStartMs + 100, _track.sourceDurationMs!,
        (value) => _track = _track.copyWith(sourceEndMs: value)), child: const Text('Set out time')),
    ]),
    Text('Starts in video at  ${formatPreciseTime(_track.timelineStartMs)}', style: const TextStyle(color: muted, fontSize: 12)),
    Slider(value: _track.timelineStartMs.clamp(0, widget.durationMs - 1).toDouble(),
      max: (widget.durationMs - 1).toDouble(),
      onChanged: (value) => setState(() => _track = _track.copyWith(timelineStartMs: value.round()))),
    TextButton(onPressed: () => _enterTime('Start in video', _track.timelineStartMs, 0, widget.durationMs - 1,
      (value) => _track = _track.copyWith(timelineStartMs: value)), child: const Text('Set start time')),
    if (_track.timelineStartMs >= widget.durationMs) const Text('This audio starts after the video. Move its start to hear it.',
      style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _track.loop,
      title: const Text('Loop selected section', style: TextStyle(fontSize: 13)),
      subtitle: const Text('Turn off to play this section once.', style: TextStyle(color: muted, fontSize: 11)),
      onChanged: (value) => setState(() => _track = _track.copyWith(loop: value))),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _track.muted,
      title: const Text('Mute this layer', style: TextStyle(fontSize: 13)),
      subtitle: const Text('Keep its timing and volume for later.', style: TextStyle(color: muted, fontSize: 11)),
      onChanged: (value) => setState(() => _track = _track.copyWith(muted: value))),
    Text('Volume  ${(_track.volume * 100).round()}%', style: const TextStyle(color: muted, fontSize: 12)),
    Slider(value: _track.volume, onChanged: (v) => setState(() => _track = _track.copyWith(volume: v))),
    Text('Fade in  ${(_track.fadeInMs / 1000).toStringAsFixed(1)}s', style: const TextStyle(color: muted, fontSize: 12)),
    Slider(value: _track.fadeInMs.toDouble(), max: 10000, divisions: 100,
      onChanged: (v) => setState(() => _track = _track.copyWith(fadeInMs: v.round()))),
    Text('Fade out  ${(_track.fadeOutMs / 1000).toStringAsFixed(1)}s', style: const TextStyle(color: muted, fontSize: 12)),
    Slider(value: _track.fadeOutMs.toDouble(), max: 10000, divisions: 100,
      onChanged: (v) => setState(() => _track = _track.copyWith(fadeOutMs: v.round()))),
    const Text('Fades apply at the overall start/end of the music, across loop boundaries. Each fade is shortened to half the audible window when needed.',
      style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
    const SizedBox(height: 20), Row(children: [
      Expanded(child: OutlinedButton(onPressed: () { Navigator.pop(context); widget.onReplace(); }, child: const Text('Replace'))),
      const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: () {
        widget.onSave(_track); Navigator.pop(context);
      }, child: const Text('Apply audio'))),
    ]),
    Center(child: TextButton(onPressed: () { widget.onRemove(); Navigator.pop(context); }, child: const Text('Remove layer'))),
  ]);
}
