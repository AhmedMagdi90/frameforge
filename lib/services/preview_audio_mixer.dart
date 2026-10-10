import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/project.dart';

/// A small player interface keeps synchronization testable without a device.
abstract class AudioPlayback {
  int get positionMs;
  bool get playing;
  Future<int?> open(String path);
  Future<void> setClip(int startMs, int endMs);
  Future<void> setLoop(bool loop);
  Future<void> setVolume(double volume);
  Future<void> seek(int positionMs);
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

class JustAudioPlayback implements AudioPlayback {
  final _player = AudioPlayer();
  @override int get positionMs => _player.position.inMilliseconds;
  @override bool get playing => _player.playing;
  @override Future<int?> open(String path) async => (await _player.setFilePath(path))?.inMilliseconds;
  @override Future<void> setClip(int startMs, int endMs) async {
    await _player.setClip(start: Duration(milliseconds: startMs), end: Duration(milliseconds: endMs));
  }
  @override Future<void> setLoop(bool loop) => _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
  @override Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override Future<void> seek(int positionMs) => _player.seek(Duration(milliseconds: positionMs));
  @override Future<void> play() => _player.play();
  @override Future<void> pause() => _player.pause();
  @override Future<void> dispose() => _player.dispose();
}

class _AudioSlot {
  _AudioSlot(this.player);
  final AudioPlayback player;
  String? path, failedPath;
  int? sourceDurationMs, clipStartMs, clipEndMs;
  bool? loop;
}

class _PreviewRequest {
  const _PreviewRequest(this.project, this.positionMs, this.playing);
  final VideoProject project;
  final int positionMs;
  final bool playing;
}

class PreviewAudioMixer {
  PreviewAudioMixer({required this.onError, AudioPlayback Function()? createPlayer})
    : _createPlayer = createPlayer ?? JustAudioPlayback.new;
  final void Function(String?) onError;
  final AudioPlayback Function() _createPlayer;
  final _slots = <String, _AudioSlot>{};
  final _errors = <String, String>{};
  _PreviewRequest? _latest;
  Future<void> _task = Future.value();
  Future<void>? _disposeTask;
  bool _pending = false, _running = false, _disposed = false;
  String? _lastError;

  /// Updates coalesce while files load; different layers load concurrently.
  void update(VideoProject project, int positionMs, bool playing) {
    if (_disposed) return;
    _latest = _PreviewRequest(project, positionMs, playing);
    _pending = true;
    if (!_running) {
      _running = true;
      _task = _drain();
    }
  }
  Future<void> get idle => _task;

  Future<void> _drain() async {
    try {
      while (!_disposed && _pending) {
        _pending = false;
        final request = _latest!;
        final tracks = request.project.audioTracks;
        final ids = tracks.map((layer) => layer.id).toSet();
        for (final id in _slots.keys.where((id) => !ids.contains(id)).toList()) {
          final slot = _slots.remove(id)!;
          _errors.remove(id);
          await _release(slot.player);
        }
        if (_disposed) break;
        await Future.wait(tracks.map(_syncLayer));
        _publishErrors();
      }
    } catch (_) {
      if (!_disposed) onError('Audio preview could not be updated. Reopen the project to retry.');
    } finally { _running = false; }
  }

  AudioLayer? _currentLayer(String id) {
    final project = _latest?.project;
    if (project == null) return null;
    for (final layer in project.audioTracks) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  Future<void> _syncLayer(AudioLayer layer) async {
    if (_disposed || !identical(_currentLayer(layer.id)?.track, layer.track)) return;
    final track = layer.track;
    final latest = _latest!;
    if (track.muted || track.timelineStartMs >= latest.project.durationMs) {
      _errors.remove(layer.id);
      try { await _slots[layer.id]?.player.pause(); } catch (_) { /* This layer is already silent. */ }
      return;
    }
    final slot = _slots.putIfAbsent(layer.id, () => _AudioSlot(_createPlayer()));
    if (slot.failedPath == track.path) { _errors[layer.id] = track.name; return; }
    try {
      if (slot.path != track.path) {
        await slot.player.pause();
        slot.sourceDurationMs = await slot.player.open(track.path);
        slot.path = track.path; slot.failedPath = null;
        slot.clipStartMs = null; slot.clipEndMs = null; slot.loop = null;
        _errors.remove(layer.id);
      }
      final resolved = track.sourceDurationMs == null ? track.copyWith(sourceDurationMs: slot.sourceDurationMs) : track;
      if (!resolved.isValid || resolved.trimmedDurationMs == null) throw StateError('Unreadable audio duration');
      final end = resolved.effectiveEndMs!;
      if (slot.clipStartMs != resolved.sourceStartMs || slot.clipEndMs != end) {
        await slot.player.pause();
        await slot.player.setClip(resolved.sourceStartMs, end);
        slot.clipStartMs = resolved.sourceStartMs; slot.clipEndMs = end;
      }
      if (slot.loop != resolved.loop) { await slot.player.setLoop(resolved.loop); slot.loop = resolved.loop; }
      if (_disposed) return;
      if (!identical(_currentLayer(layer.id)?.track, track)) { await slot.player.pause(); return; }
      final request = _latest!;
      final source = resolved.sourcePositionAt(request.positionMs, request.project.durationMs);
      if (source == null) { await slot.player.pause(); return; }
      final target = source - resolved.sourceStartMs;
      await slot.player.setVolume(resolved.gainAt(request.positionMs, request.project.durationMs));
      if (!request.playing || (slot.player.positionMs - target).abs() > 150) await slot.player.seek(target);
      if (_disposed) return;
      final current = _latest!;
      if (current.playing && identical(_currentLayer(layer.id)?.track, track) &&
          resolved.sourcePositionAt(current.positionMs, current.project.durationMs) != null) {
        if (!slot.player.playing) unawaited(slot.player.play().catchError((Object error) {
          _failed(layer, slot); _publishErrors();
        }));
      } else { await slot.player.pause(); }
    } catch (_) { _failed(layer, slot); }
  }

  void _failed(AudioLayer layer, _AudioSlot slot) {
    final current = _currentLayer(layer.id);
    if (_disposed || current == null || current.track.path != layer.track.path || current.track.muted ||
        current.track.timelineStartMs >= _latest!.project.durationMs) return;
    slot.failedPath = layer.track.path;
    _errors[layer.id] = layer.track.name;
    unawaited(slot.player.pause().catchError((Object error) { /* Keep other layers playing. */ }));
  }
  void _publishErrors() {
    if (_disposed) return;
    final message = _errors.isEmpty ? null : 'Audio unavailable: ${_errors.values.toSet().join(', ')}. Replace these layers in Audio.';
    if (message != _lastError) { _lastError = message; onError(message); }
  }
  Future<void> pause() async {
    final request = _latest;
    if (request != null) _latest = _PreviewRequest(request.project, request.positionMs, false);
    await Future.wait(_slots.values.map((slot) async {
      try { await slot.player.pause(); } catch (_) { /* A failed player is already silent. */ }
    }));
  }
  Future<void> _release(AudioPlayback player) async {
    try { await player.dispose(); } catch (_) { /* Release all remaining players if one fails. */ }
  }
  Future<void> dispose() => _disposeTask ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true; _pending = false;
    await _task;
    await Future.wait(_slots.values.map((slot) => _release(slot.player)));
    _slots.clear(); _errors.clear();
  }
}
