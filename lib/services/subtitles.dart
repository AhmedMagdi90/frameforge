import 'package:characters/characters.dart';
import '../models/project.dart';

/// Offline subtitle interchange. Import never guesses speech or cue timing.
class Subtitles {
  static List<TextLayer> parse(String source, int durationMs) {
    if (durationMs <= 0) throw const FormatException('Add video before importing captions.');
    final normalized = source.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cues = <TextLayer>[];
    for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
      final lines = block.trim().split('\n');
      if (lines.first.trim().isEmpty || lines.first.startsWith('NOTE') ||
          lines.first == 'STYLE' || lines.first == 'REGION') continue;
      final index = lines.indexWhere((line) => line.contains('-->'));
      if (index < 0) {
        if (lines.first.startsWith('WEBVTT')) continue;
        throw const FormatException('A subtitle cue is missing its timing line.');
      }
      final parts = lines[index].split('-->');
      if (parts.length != 2) throw const FormatException('Invalid subtitle timing.');
      final start = _time(parts[0].trim());
      final end = _time(parts[1].trim().split(RegExp(r'\s+')).first);
      if (end <= start) throw const FormatException('A caption must end after it starts.');
      final text = lines.skip(index + 1).join('\n').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (text.isEmpty) continue;
      if (text.characters.length > 300) throw const FormatException('Captions must be 300 characters or fewer.');
      if (start >= durationMs) continue;
      cues.add(TextLayer(id: newId(), text: text, startMs: start,
        endMs: end.clamp(start + 1, durationMs).toInt(), isCaption: true));
      if (cues.length > 500) throw const FormatException('Import up to 500 captions at a time.');
    }
    if (cues.isEmpty) throw const FormatException('No captions fall inside this video.');
    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static int _time(String value) {
    final match = RegExp(r'^(?:(\d+):)?(\d{2}):(\d{2})[,.](\d{3})$').firstMatch(value);
    if (match == null) throw const FormatException('Use HH:MM:SS,mmm or MM:SS.mmm subtitle times.');
    final hours = int.parse(match[1] ?? '0');
    final minutes = int.parse(match[2]!);
    final seconds = int.parse(match[3]!);
    if (minutes > 59 || seconds > 59) throw const FormatException('Invalid subtitle timestamp.');
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + int.parse(match[4]!);
  }

  static String encodeSrt(Iterable<TextLayer> layers) {
    final cues = layers.where((layer) => layer.isCaption).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return [for (var i = 0; i < cues.length; i++)
      '${i + 1}\n${_stamp(cues[i].startMs)} --> ${_stamp(cues[i].endMs)}\n${cues[i].text}\n'].join('\n');
  }

  static String _stamp(int ms) {
    String pad(int v, int width) => v.toString().padLeft(width, '0');
    return '${pad(ms ~/ 3600000, 2)}:${pad(ms ~/ 60000 % 60, 2)}:${pad(ms ~/ 1000 % 60, 2)},${pad(ms % 1000, 3)}';
  }
}
