import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/clip_filter.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/native_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.frameforge/video');

  test('native export receives retimed duration and the same filter matrix as preview', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      received = call; return '/export.mp4';
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    final project = VideoProject(id: 'project', name: 'Story', updatedAt: DateTime(2026), clips: const [
      VideoClip(id: 'clip', path: '/clip.mp4', name: 'Clip', sourceDurationMs: 5000,
        startMs: 1000, endMs: 5000, speed: 2, filter: ClipFilter.cool, filterIntensity: .4),
    ]);
    expect(await NativeEngine().export(project, '/export.mp4', 1080), '/export.mp4');
    expect(received!.method, 'export');
    final args = received!.arguments as Map;
    final clip = (args['clips'] as List).single as Map;
    expect(clip['startMs'], 1000);
    expect(clip['endMs'], 5000);
    expect(clip['outputDurationMs'], 2000);
    expect(clip['renderSpeed'], 2);
    expect(clip['filterMatrix'], ClipFilter.cool.matrix(.4));
    expect(args['width'], 1080);
    expect(args['height'], 1920);
  });

  test('4K export transports source-keyed motion, overlays, captions and target frame rate', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      received = call; return '/pro.mp4';
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    final project = VideoProject(id: 'p', name: 'Pro', updatedAt: DateTime(2026), ratio: CanvasRatio.landscape,
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000,
        endMs: 5000, fit: ClipFit.fill, flipX: true,
        keyframes: [MotionKeyframe(sourceMs: 0), MotionKeyframe(sourceMs: 5000, zoom: 2)])],
      texts: const [TextLayer(id: 't', text: 'Caption', startMs: 500, endMs: 2000, isCaption: true)],
      images: const [ImageLayer(id: 'i', path: '/logo.png', name: 'Logo', startMs: 0, endMs: 5000, aspect: 2, opacity: .7)]);
    await NativeEngine().export(project, '/pro.mp4', 2160, fps: 60);
    final args = received!.arguments as Map;
    expect(args['width'], 3840); expect(args['height'], 2160); expect(args['fps'], 60);
    final clip = (args['clips'] as List).single as Map;
    expect(clip['fit'], 'fill'); expect(clip['flipX'], isTrue);
    expect((clip['keyframes'] as List).last['sourceMs'], 5000);
    expect((args['images'] as List).single['opacity'], .7);
    expect((args['texts'] as List).single['isCaption'], isTrue);
    await expectLater(NativeEngine().export(project, '/bad.mp4', 1440), throwsArgumentError);
    await expectLater(NativeEngine().export(project, '/bad.mp4', 1080, fps: 120), throwsArgumentError);
  });

  test('export transports clip gain, music placement and its trimmed fade intervals', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      received = call; return '/audio.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Sound', updatedAt: DateTime(2026), frameRate: 24,
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000, endMs: 5000, volume: .25)],
      music: const MusicTrack(path: '/song.m4a', name: 'Song', sourceDurationMs: 6000,
        sourceStartMs: 1000, sourceEndMs: 3000, timelineStartMs: 500, fadeInMs: 1000, fadeOutMs: 500));
    await NativeEngine().export(project, '/audio.mp4', 1080);
    expect(received!.method, 'export');
    final args = received!.arguments as Map;
    expect(args['fps'], 24); expect((args['clips'] as List).single['volume'], .25);
    final music = args['music'] as Map;
    expect(music['renderStartMs'], 500); expect(music['renderEndMs'], 5000);
    expect(music['renderFadeInMs'], 1000); expect(music['renderFadeOutMs'], 500);
    expect((music['segments'] as List).length, 3);
    expect((music['segments'] as List).last['sourceEndMs'], 1500);
  });

  test('legacy music is inspected before planning without mutating the draft', () async {
    final calls = <String>[];
    Map? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'inspectAudio') return {'durationMs': 3000};
      arguments = call.arguments as Map; return '/legacy.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Legacy', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000, endMs: 5000)],
      music: const MusicTrack(path: '/old.mp3', name: 'Old'));
    await NativeEngine().export(project, '/legacy.mp4', 720);
    expect(calls, ['inspectAudio', 'export']);
    expect(project.music!.sourceDurationMs, isNull);
    expect(((arguments!['music'] as Map)['segments'] as List).length, 2);
  });

  test('cancelling during metadata inspection prevents a delayed native export', () async {
    final inspecting = Completer<void>(), release = Completer<void>();
    var exports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'inspectAudio') {
        inspecting.complete(); await release.future; return {'durationMs': 3000};
      }
      if (call.method == 'export') { exports++; return '/unexpected.mp4'; }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Cancel', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000, endMs: 5000)],
      music: const MusicTrack(path: '/old.mp3', name: 'Old'));
    final engine = NativeEngine();
    final pending = engine.export(project, '/cancel.mp4', 720);
    await inspecting.future; await engine.cancel();
    final observed = expectLater(pending, throwsStateError);
    release.complete(); await observed;
    expect(exports, 0);
  });

  test('inaudible music after the video does not require inspecting its source', () async {
    final calls = <String>[];
    Map? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method); arguments = call.arguments as Map; return '/silent.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Shortened', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 1000, endMs: 1000)],
      music: const MusicTrack(path: '/missing.mp3', name: 'Later', timelineStartMs: 5000));
    await NativeEngine().export(project, '/silent.mp4', 720);
    expect(calls, ['export']); expect(arguments!['music'], isNull);
    expect(project.music!.timelineStartMs, 5000);
  });

  test('export sends independent soundtrack, voice and effect intervals exactly once', () async {
    Map? arguments;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method); arguments = call.arguments as Map; return '/mix.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Mix', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000, endMs: 5000)],
      music: const MusicTrack(path: '/music.m4a', name: 'Music', sourceDurationMs: 2000),
      audioLayers: const [
        AudioLayer(id: 'voice', kind: AudioKind.voice, track: MusicTrack(path: '/voice.m4a', name: 'Voice',
          sourceDurationMs: 3000, sourceStartMs: 500, sourceEndMs: 1500, timelineStartMs: 2000, loop: false, volume: .8)),
        AudioLayer(id: 'effect', track: MusicTrack(path: '/hit.wav', name: 'Hit', sourceDurationMs: 1000,
          timelineStartMs: 4750, loop: false, fadeInMs: 100, fadeOutMs: 100)),
      ]);
    await NativeEngine().export(project, '/mix.mp4', 1080);
    expect(calls, ['export']);
    final tracks = arguments!['audioTracks'] as List;
    expect(tracks.map((track) => track['id']), [soundtrackId, 'voice', 'effect']);
    expect(arguments!['music'], tracks.first);
    final voice = tracks[1] as Map; expect(voice['kind'], 'voice'); expect(voice['volume'], .8);
    expect(voice['renderStartMs'], 2000); expect(voice['renderEndMs'], 3000);
    expect((voice['segments'] as List).single['sourceStartMs'], 500);
    expect((tracks.last['segments'] as List).single['sourceEndMs'], 250);
  });

  test('muted or out-of-project layers skip missing source inspection', () async {
    Map? arguments;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method); arguments = call.arguments as Map; return '/silent.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Silent', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 1000, endMs: 1000)],
      music: const MusicTrack(path: '/missing1', name: 'Muted music', muted: true),
      audioLayers: const [
        AudioLayer(id: 'muted', track: MusicTrack(path: '/missing2', name: 'Muted', muted: true)),
        AudioLayer(id: 'late', track: MusicTrack(path: '/missing3', name: 'Later', timelineStartMs: 1000)),
      ]);
    await NativeEngine().export(project, '/silent.mp4', 720);
    expect(calls, ['export']); expect(arguments!['audioTracks'], isEmpty); expect(arguments!['music'], isNull);
  });

  test('cancelling inspection of an additional layer prevents the composed export', () async {
    final inspecting = Completer<void>(), release = Completer<void>();
    var exports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'inspectAudio') {
        inspecting.complete(); await release.future; return {'durationMs': 3000};
      }
      if (call.method == 'export') { exports++; return '/unexpected.mp4'; }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final project = VideoProject(id: 'p', name: 'Cancel mix', updatedAt: DateTime(2026),
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000, endMs: 5000)],
      music: const MusicTrack(path: '/music.m4a', name: 'Music', sourceDurationMs: 3000),
      audioLayers: const [AudioLayer(id: 'voice', track: MusicTrack(path: '/old.mp3', name: 'Voice'))]);
    final engine = NativeEngine(); final pending = engine.export(project, '/cancel.mp4', 720);
    await inspecting.future; await engine.cancel();
    final observed = expectLater(pending, throwsStateError); release.complete(); await observed;
    expect(exports, 0);
  });

  test('total interval budget accepts four thousand and rejects larger combined loops', () async {
    var exports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      exports++; return '/bounded.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    const short = MusicTrack(path: '/short.wav', name: 'Short', sourceDurationMs: 100);
    final project = VideoProject(id: 'p', name: 'Bounded', updatedAt: DateTime(2026), music: short,
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 50001, endMs: 50000)],
      audioLayers: [for (var i = 0; i < 7; i++) AudioLayer(id: 'layer$i', track: short)]);
    await NativeEngine().export(project, '/bounded.mp4', 720); expect(exports, 1);
    final extended = project.copyWith(clips: [project.clips.single.copyWith(endMs: 50001)]);
    await expectLater(NativeEngine().export(extended, '/too-many.mp4', 720), throwsFormatException);
    expect(exports, 1);
  });

  test('invalid audio identities are rejected before calling native code', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls++; return '/unexpected.mp4';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    const layer = AudioLayer(id: 'same', track: MusicTrack(path: '/x.wav', name: 'X', sourceDurationMs: 1000));
    final project = VideoProject(id: 'p', name: 'Invalid', updatedAt: DateTime(2026), audioLayers: const [layer, layer],
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 1000, endMs: 1000)]);
    await expectLater(NativeEngine().export(project, '/invalid.mp4', 720), throwsFormatException);
    expect(calls, 0);
  });
}
