import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/ai_video.dart';
import 'package:frameforge/models/project.dart';

Map<String, dynamic> fixturePlan() => {'title': 'Coffee', 'summary': 'A morning story', 'ratio': 'portrait', 'scenes': [
  {'image_prompt': 'Warm light in a small cafe', 'narration': 'A new day', 'caption': 'Morning', 'seconds': 5},
  {'image_prompt': 'A steaming cup on a counter', 'narration': 'A fresh start', 'caption': 'Fresh start', 'seconds': 5},
]};

void main() {
  test('scene plan round-trips the server contract', () {
    final json = fixturePlan(), plan = AiVideoPlan.fromJson(json);
    expect(plan.ratio, CanvasRatio.portrait); expect(plan.toJson(), json);
    expect(() => plan.scenes.clear(), throwsUnsupportedError);
  });
  test('invalid timing, ratio and scene count cannot enter a draft', () {
    final timing = fixturePlan(); ((timing['scenes'] as List).first as Map)['seconds'] = 0;
    expect(() => AiVideoPlan.fromJson(timing), throwsFormatException);
    expect(() => AiVideoPlan.fromJson(fixturePlan()..['ratio'] = 'cinema'), throwsFormatException);
    expect(() => AiVideoPlan.fromJson(fixturePlan()..['scenes'] = []), throwsFormatException);
  });
  test('scene edits preserve the rest of the plan', () {
    final plan = AiVideoPlan.fromJson(fixturePlan());
    final replacement = AiScene.fromJson({'image_prompt': 'A sunrise through the cafe window', 'narration': 'Hello morning', 'caption': 'Hello', 'seconds': 3});
    final edited = plan.replacingScene(0, replacement);
    expect(edited.scenes.first, replacement); expect(edited.scenes.last, plan.scenes.last);
    expect(plan.scenes.first.caption, 'Morning');
  });
  test('manifest rejects path traversal and duplicate assets', () {
    final json = {'title': 'Coffee', 'ratio': 'portrait', 'video': 'video.mp4', 'subtitles': 'captions.srt', 'ai_voice': true,
      'scenes': [{'filename': 'scene01.mp4', 'duration_ms': 5000, 'caption': 'Morning'},
        {'filename': 'scene02.mp4', 'duration_ms': 5000, 'caption': 'Coffee'}]};
    expect(AiManifest.fromJson(json).scenes.length, 2);
    (json['scenes'] as List).first['filename'] = '../private.mp4';
    expect(() => AiManifest.fromJson(json), throwsFormatException);
    (json['scenes'] as List).first['filename'] = 'scene02.mp4';
    expect(() => AiManifest.fromJson(json), throwsFormatException);
  });
}
