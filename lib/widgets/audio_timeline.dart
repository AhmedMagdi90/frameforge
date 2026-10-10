import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme.dart';

class AudioTimeline extends StatelessWidget {
  const AudioTimeline({super.key, required this.project, required this.positionMs,
    required this.onEdit, required this.onMute});
  final VideoProject project;
  final int positionMs;
  final ValueChanged<AudioLayer> onEdit;
  final ValueChanged<String> onMute;

  @override
  Widget build(BuildContext context) {
    final tracks = project.audioTracks;
    if (tracks.isEmpty || project.durationMs <= 0) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
      child: SizedBox(height: math.min(112.0, tracks.length * 28.0),
        child: ListView.builder(itemCount: tracks.length, padding: EdgeInsets.zero, itemExtent: 28,
          itemBuilder: (context, index) {
            final layer = tracks[index], track = layer.track;
            final start = track.timelineStartMs.clamp(0, project.durationMs);
            final end = track.trimmedDurationMs == null ? project.durationMs : track.renderEndMs(project.durationMs);
            final audible = math.max(0, end - start);
            final color = track.muted ? muted : mint;
            return Row(children: [
              SizedBox(width: 25, child: IconButton(padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: track.muted ? 'Unmute ${track.name}' : 'Mute ${track.name}',
                onPressed: () => onMute(layer.id), icon: Icon(track.muted
                  ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 14, color: color))),
              SizedBox(width: 70, child: InkWell(onTap: () => onEdit(layer), child: Text(track.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: color)))),
              const SizedBox(width: 6), Expanded(child: LayoutBuilder(builder: (context, box) =>
                GestureDetector(onTap: () => onEdit(layer), child: SizedBox(height: 20, child: Stack(children: [
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: elevated, borderRadius: BorderRadius.circular(4)))),
                  if (audible > 0) Positioned(left: box.maxWidth * start / project.durationMs,
                    width: box.maxWidth * audible / project.durationMs, top: 2, bottom: 2,
                    child: DecoratedBox(decoration: BoxDecoration(color: color.withOpacity(.28), borderRadius: BorderRadius.circular(3)),
                      child: Center(child: Icon(track.loop ? Icons.repeat_rounded : Icons.play_arrow_rounded, size: 11, color: color))))
                  else const Positioned.fill(child: Center(child: Text('After video end', style: TextStyle(color: muted, fontSize: 8)))),
                  Positioned(left: (box.maxWidth - 1) * positionMs.clamp(0, project.durationMs) / project.durationMs,
                    top: 0, bottom: 0, width: 1, child: const ColoredBox(color: violet)),
                ]))))),
            ]);
          })));
  }
}
