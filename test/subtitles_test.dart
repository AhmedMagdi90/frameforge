import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/subtitles.dart';

void main() {
  test('SRT import preserves multiline captions and clamps cues at project end', () {
    final cues = Subtitles.parse('\uFEFF1\r\n00:00:01,250 --> 00:00:03,500\r\nHello\r\nworld\r\n\r\n'
      '2\r\n00:00:04,000 --> 00:00:09,000\r\nThe end\r\n\r\n'
      '3\r\n00:00:10,000 --> 00:00:11,000\r\nOutside', 5000);
    expect(cues.length, 2); expect(cues.first.text, 'Hello\nworld');
    expect(cues.first.startMs, 1250); expect(cues.last.endMs, 5000);
    expect(cues.every((cue) => cue.isCaption), isTrue);
  });

  test('WebVTT identifiers and positioning are accepted with plain text rendering', () {
    final cues = Subtitles.parse('WEBVTT\n\nNOTE Transcript\nIgnored comment\n\n'
      'intro\n00:01.000 --> 00:02.500 align:start\n<b>Hello</b> <i>there</i>\n\n'
      '00:03.000 --> 00:04.000\nNext', 5000);
    expect(cues.first.text, 'Hello there'); expect(cues.last.startMs, 3000);
  });

  test('invalid timing, reversed ranges and empty imports report a format error', () {
    for (final source in ['1\n00:00:61,000 --> 00:01:05,000\nBad',
      '1\n00:00:02,000 --> 00:00:01,000\nReverse', 'Not subtitles',
      'WEBVTT\n\n00:06.000 --> 00:07.000\nOutside']) {
      expect(() => Subtitles.parse(source, 5000), throwsFormatException);
    }
    expect(() => Subtitles.parse('WEBVTT', 0), throwsFormatException);
  });

  test('SRT export orders captions, excludes titles and preserves millisecond precision', () {
    final encoded = Subtitles.encodeSrt(const [
      TextLayer(id: 'title', text: 'Title', startMs: 0, endMs: 1000),
      TextLayer(id: 'later', text: 'Later', startMs: 3600001, endMs: 3601205, isCaption: true),
      TextLayer(id: 'earlier', text: 'First\nline', startMs: 10, endMs: 1123, isCaption: true),
    ]);
    expect(encoded, startsWith('1\n00:00:00,010 --> 00:00:01,123\nFirst\nline'));
    expect(encoded, contains('01:00:00,001 --> 01:00:01,205'));
    expect(encoded, isNot(contains('Title')));
    final restored = Subtitles.parse(encoded, 4000000);
    expect(restored.map((cue) => cue.text), ['First\nline', 'Later']);
  });

  test('import caps cue counts to keep caption editing bounded', () {
    final source = List.generate(501, (i) => '$i\n00:00:00,000 --> 00:00:01,000\nCue $i').join('\n\n');
    expect(() => Subtitles.parse(source, 2000), throwsFormatException);
  });

  test('caption length counts emoji as displayed characters', () {
    final text = List.filled(300, '👩‍💻').join();
    final cues = Subtitles.parse('1\n00:00:00,000 --> 00:00:01,000\n$text', 2000);
    expect(cues.single.text, text);
    expect(() => Subtitles.parse('1\n00:00:00,000 --> 00:00:01,000\n${text}a', 2000), throwsFormatException);
  });
}
