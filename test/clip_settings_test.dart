import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/clip_filter.dart';
import 'package:frameforge/models/project.dart';

void main() {
  const clip = VideoClip(id: 'clip', path: '/clip.mp4', name: 'Clip', sourceDurationMs: 6000,
    startMs: 1000, endMs: 5000);

  test('source and timeline conversions honor trimmed starts at every speed', () {
    for (final speed in supportedClipSpeeds) {
      final value = clip.copyWith(speed: speed);
      expect(value.sourcePositionAt(0), 1000);
      expect(value.sourcePositionAt(value.durationMs), 5000);
      expect(value.timelinePositionAt(1000), 0);
      expect(value.timelinePositionAt(5000), value.durationMs);
      final local = value.durationMs ~/ 3;
      expect((value.timelinePositionAt(value.sourcePositionAt(local)) - local).abs(), lessThanOrEqualTo(2));
    }
  });

  test('older clip data loads at normal speed with the original look', () {
    final json = clip.toJson()..remove('speed')..remove('filter')..remove('filterIntensity');
    final restored = VideoClip.fromJson(json);
    expect(restored.speed, 1);
    expect(restored.filter, ClipFilter.none);
    expect(restored.durationMs, 4000);
    final oldProject = VideoProject(id: 'old', name: 'Old draft', updatedAt: DateTime(2026), clips: [clip]).toJson();
    oldProject['schemaVersion'] = 1;
    oldProject['clips'] = [json];
    expect(VideoProject.fromJson(oldProject).clips.single.speed, 1);
  });

  test('invalid saved speeds and intensities fail cleanly', () {
    for (final speed in [0, -1, 1.1, double.infinity]) {
      expect(() => VideoClip.fromJson({...clip.toJson(), 'speed': speed}), throwsFormatException);
    }
    expect(() => VideoClip.fromJson({...clip.toJson(), 'filterIntensity': double.nan}), throwsFormatException);
  });

  test('all filter presets preserve alpha and fade to identity at zero intensity', () {
    for (final filter in ClipFilter.values) {
      expect(filter.matrix(0), identityColorMatrix);
      final matrix = filter.matrix(1);
      expect(matrix.length, 20);
      expect(matrix.every((value) => value.isFinite), isTrue);
      expect(matrix.sublist(15), [0, 0, 0, 1, 0]);
      expect([matrix[3], matrix[8], matrix[13]], [0, 0, 0]);
    }
  });

  test('monochrome uses linear luminance and intensity blends with the original', () {
    final mono = ClipFilter.mono.matrix(1);
    expect(mono.sublist(0, 3), mono.sublist(5, 8));
    expect(mono.sublist(5, 8), mono.sublist(10, 13));
    expect(mono.take(3).reduce((a, b) => a + b), closeTo(1, 1e-9));
    final half = ClipFilter.mono.matrix(.5);
    expect(half[0], closeTo((1 + .2126) / 2, 1e-9));
    expect(half[1], closeTo(.7152 / 2, 1e-9));
  });
}
