class TimelineGrid {
  const TimelineGrid(this.fps);
  final int fps;
  int step(int positionMs, int direction, int durationMs) {
    if (![24, 30, 60].contains(fps) || (direction != -1 && direction != 1)) {
      throw ArgumentError('Use a supported frame grid and a single step direction.');
    }
    final scaled = positionMs * fps / 1000;
    final nearest = scaled.round();
    final onGrid = positionMs == (nearest * 1000 / fps).round();
    final frame = onGrid ? nearest + direction : direction > 0 ? scaled.floor() + 1 : scaled.ceil() - 1;
    return (frame * 1000 / fps).round().clamp(0, durationMs).toInt();
  }

  static int snap(int positionMs, Iterable<int> boundaries, {int toleranceMs = 80}) {
    var closest = positionMs;
    var distance = toleranceMs + 1;
    for (final boundary in boundaries) {
      final difference = (boundary - positionMs).abs();
      if (difference < distance) { closest = boundary; distance = difference; }
    }
    return closest;
  }

  /// Accept seconds, M:SS.mmm or H:MM:SS.mmm with up to 3 decimal places.
  static int parseTime(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d+(?::\d{1,2}){0,2}(?:\.\d{1,3})?$').hasMatch(value)) {
      throw const FormatException('Use seconds or M:SS.mmm.');
    }
    final pieces = value.split(':');
    final last = pieces.last.split('.');
    final seconds = int.parse(last.first);
    if (pieces.length > 1 && seconds > 59) throw const FormatException('Seconds must be below 60.');
    final fraction = last.length > 1 ? int.parse(last.last.padRight(3, '0')) : 0;
    final minutes = pieces.length > 1 ? int.parse(pieces[pieces.length - 2]) : 0;
    if (pieces.length == 3 && minutes > 59) throw const FormatException('Minutes must be below 60.');
    final hours = pieces.length == 3 ? int.parse(pieces.first) : 0;
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + fraction;
  }
}

String formatPreciseTime(int ms) => '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
