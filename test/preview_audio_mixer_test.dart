import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/services/preview_audio_mixer.dart';

class FakePlayback implements AudioPlayback {
  String? path;
  int? start, end;
  bool loop = false, disposed = false;
  double volume = 1;
  int plays = 0, opens = 0;
  Completer<int?>? loading;
  String? failingPath;
  @override int positionMs = 0;
  @override bool playing = false;
  @override Future<int?> open(String value) async {
    path = value; opens++;
    if (value == failingPath) throw StateError('Missing audio');
    if (loading != null) return await loading!.future;
    return 6000;
  }
  @override Future<void> setClip(int startMs, int endMs) async { start = startMs; end = endMs; positionMs = 0; }
  @override Future<void> setLoop(bool value) async { loop = value; }
  @override Future<void> setVolume(double value) async { volume = value; }
  @override Future<void> seek(int value) async { positionMs = value; }
  @override Future<void> play() async { playing = true; plays++; }
  @override Future<void> pause() async { playing = false; }
  @override Future<void> dispose() async { disposed = true; playing = false; }
}

void main() {
  const song = MusicTrack(path: '/song.m4a', name: 'Song', sourceDurationMs: 6000,
    sourceStartMs: 1000, sourceEndMs: 3000, timelineStartMs: 500, fadeInMs: 1000);
  const voice = AudioLayer(id: 'voice', kind: AudioKind.voice,
    track: MusicTrack(path: '/voice.m4a', name: 'Voice', sourceDurationMs: 6000,
      sourceStartMs: 500, sourceEndMs: 2000, timelineStartMs: 750, loop: false, volume: .8));
  VideoProject project({MusicTrack? music = song, List<AudioLayer> layers = const [voice]}) =>
    VideoProject(id: 'p', name: 'Preview', updatedAt: DateTime(2026), music: music, audioLayers: layers,
      clips: const [VideoClip(id: 'c', path: '/c.mp4', name: 'Clip', sourceDurationMs: 5000, endMs: 5000)]);
  late List<FakePlayback> players;
  late List<String?> errors;
  late PreviewAudioMixer mixer;
  setUp(() {
    players = []; errors = [];
    mixer = PreviewAudioMixer(onError: errors.add, createPlayer: () {
      final player = FakePlayback(); players.add(player); return player;
    });
  });
  tearDown(() async { await mixer.dispose(); });

  test('overlapping layers use independent clipped source positions and fade gain', () async {
    mixer.update(project(), 1000, true); await mixer.idle;
    expect(players.length, 2);
    final music = players.firstWhere((player) => player.path == song.path);
    final speech = players.firstWhere((player) => player.path == voice.track.path);
    expect(music.start, 1000); expect(music.end, 3000); expect(music.loop, isTrue);
    expect(music.positionMs, 500); expect(music.volume, closeTo(.3, 1e-9));
    expect(speech.positionMs, 250); expect(speech.volume, .8); expect(speech.loop, isFalse);
    expect(players.every((player) => player.playing), isTrue); expect(errors, isEmpty);
    mixer.update(project(), 2600, true); await mixer.idle;
    expect(music.positionMs, 100); expect(speech.playing, isFalse);
  });

  test('muted and out-of-project layers do not open their assets', () async {
    mixer.update(project(music: song.copyWith(muted: true), layers: [
      voice.copyWith(track: voice.track.copyWith(timelineStartMs: 5000)),
    ]), 1000, true); await mixer.idle;
    expect(players, isEmpty); expect(errors, isEmpty);
  });

  test('pausing, muting and removal silence players and removal disposes them', () async {
    final initial = project(); mixer.update(initial, 1000, true); await mixer.idle;
    await mixer.pause(); expect(players.every((player) => !player.playing), isTrue);
    mixer.update(initial.copyWith(music: song.copyWith(muted: true)), 1000, true); await mixer.idle;
    final music = players.firstWhere((player) => player.path == song.path);
    expect(music.playing, isFalse);
    mixer.update(initial.copyWith(audioLayers: []), 1000, false); await mixer.idle;
    expect(players.firstWhere((player) => player.path == voice.track.path).disposed, isTrue);
    expect(music.playing, isFalse);
  });

  test('a slow source load uses the latest seek and paused state', () async {
    final loading = Completer<int?>();
    await mixer.dispose();
    mixer = PreviewAudioMixer(onError: errors.add, createPlayer: () {
      final player = FakePlayback()..loading = loading; players.add(player); return player;
    });
    final initial = project(layers: []);
    mixer.update(initial, 1000, true);
    await Future<void>.delayed(Duration.zero);
    mixer.update(initial, 2700, false); loading.complete(6000); await mixer.idle;
    expect(players.single.positionMs, 200); expect(players.single.playing, isFalse);
    expect(players.single.opens, 1); expect(players.single.plays, 0);
  });

  test('replacement during loading never starts the stale source', () async {
    final loading = Completer<int?>();
    await mixer.dispose();
    mixer = PreviewAudioMixer(onError: errors.add, createPlayer: () {
      final player = FakePlayback()..loading = loading; players.add(player); return player;
    });
    final initial = project(layers: []);
    mixer.update(initial, 1000, true); await Future<void>.delayed(Duration.zero);
    const replacement = MusicTrack(path: '/new.wav', name: 'New', sourceDurationMs: 6000, loop: false);
    mixer.update(initial.copyWith(music: replacement), 1500, true);
    loading.complete(6000); await mixer.idle;
    expect(players.single.path, '/new.wav'); expect(players.single.opens, 2);
    expect(players.single.plays, 1); expect(players.single.positionMs, 1500);
  });

  test('one unreadable layer is isolated, avoids retry storms and clears on mute', () async {
    await mixer.dispose();
    mixer = PreviewAudioMixer(onError: errors.add, createPlayer: () {
      final player = FakePlayback()..failingPath = '/voice.m4a'; players.add(player); return player;
    });
    final initial = project(); mixer.update(initial, 1000, true); await mixer.idle;
    expect(players.firstWhere((player) => player.path == song.path).playing, isTrue);
    expect(errors.last, contains('Voice'));
    mixer.update(initial, 1100, true); await mixer.idle;
    expect(players.firstWhere((player) => player.path == voice.track.path).opens, 1);
    mixer.update(initial.copyWith(audioLayers: [voice.copyWith(track: voice.track.copyWith(muted: true))]), 1200, true);
    await mixer.idle; expect(errors.last, isNull);
  });

  test('disposing during source loading prevents playback and releases the player', () async {
    final loading = Completer<int?>();
    await mixer.dispose();
    mixer = PreviewAudioMixer(onError: errors.add, createPlayer: () {
      final player = FakePlayback()..loading = loading; players.add(player); return player;
    });
    mixer.update(project(layers: []), 1000, true); await Future<void>.delayed(Duration.zero);
    final disposing = mixer.dispose(); loading.complete(6000); await disposing;
    expect(players.single.plays, 0); expect(players.single.disposed, isTrue); expect(errors, isEmpty);
  });

  test('legacy duration resolves in preview without modifying the draft', () async {
    const legacy = MusicTrack(path: '/old.mp3', name: 'Old');
    final initial = project(music: legacy, layers: []);
    mixer.update(initial, 1250, false); await mixer.idle;
    expect(players.single.start, 0); expect(players.single.end, 6000);
    expect(players.single.positionMs, 1250); expect(initial.music!.sourceDurationMs, isNull);
  });

  test('layers sharing a file retain separate players and do not reload on volume changes', () async {
    final duplicate = voice.copyWith(id: 'copy', track: voice.track.copyWith(volume: .2, timelineStartMs: 1000));
    final initial = project(music: null, layers: [voice, duplicate]);
    mixer.update(initial, 1250, false); await mixer.idle;
    expect(players.length, 2); expect(players.map((player) => player.volume), [.8, .2]);
    expect(players.map((player) => player.positionMs), [500, 250]);
    mixer.update(initial.copyWith(audioLayers: [voice.copyWith(track: voice.track.copyWith(volume: .5)), duplicate]), 1400, false);
    await mixer.idle;
    expect(players.length, 2); expect(players.map((player) => player.opens), [1, 1]);
    expect(players.map((player) => player.volume), [.5, .2]);
  });
}
