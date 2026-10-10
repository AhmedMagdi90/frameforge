import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/clip_filter.dart';
import '../models/timeline_grid.dart';
import '../services/project_library.dart';

class EditorController extends ChangeNotifier {
  EditorController(this.project, this.library);
  VideoProject project;
  final ProjectLibrary library;
  final List<VideoProject> _undo = [];
  final List<VideoProject> _redo = [];
  Timer? _saveTimer;
  Future<void> _saveQueue = Future.value();
  String? saveError;
  bool saving = false;
  bool _disposed = false;
  int positionMs = 0;
  String? selectedId;
  bool snapEnabled = true;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  VideoClip? get selected {
    for (final clip in project.clips) {
      if (clip.id == selectedId) return clip;
    }
    return null;
  }

  void _apply(VideoProject value) {
    _undo.add(project);
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
    project = _normalize(value);
    _changed();
  }
  VideoProject _normalize(VideoProject value) => value.copyWith(texts: value.texts
    .where((text) => text.startMs < value.durationMs)
    .map((text) => text.copyWith(endMs: text.endMs.clamp(text.startMs + 1, value.durationMs).toInt()))
    .toList(), images: value.images.where((image) => image.startMs < value.durationMs)
      .map((image) => image.copyWith(endMs: image.endMs.clamp(image.startMs + 1, value.durationMs).toInt())).toList());

  void _changed() {
    saving = true;
    positionMs = positionMs.clamp(0, project.durationMs).toInt();
    if (!project.clips.any((clip) => clip.id == selectedId)) {
      selectedId = project.clips.isEmpty ? null : project.clips.first.id;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () { unawaited(flush()); });
    notifyListeners();
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    final snapshot = project;
    _saveQueue = _saveQueue.then((_) => library.save(snapshot)).then((_) {
      saveError = null;
      if (identical(project, snapshot)) saving = false;
      if (!_disposed) notifyListeners();
    }).catchError((Object error) {
      saveError = 'Could not save this draft: $error';
      if (!_disposed) notifyListeners();
    });
    return _saveQueue;
  }

  void seek(int value) {
    positionMs = value.clamp(0, project.durationMs).toInt();
    notifyListeners();
  }
  void select(String id) { selectedId = id; notifyListeners(); }
  void seekWithSnap(int value) {
    final boundaries = [for (var i = 0; i < project.clips.length; i++) project.clipOffset(i), project.durationMs];
    seek(snapEnabled ? TimelineGrid.snap(value, boundaries) : value);
  }
  void stepFrame(int direction) => seek(TimelineGrid(project.frameRate).step(positionMs, direction, project.durationMs));
  void toggleSnap() { snapEnabled = !snapEnabled; notifyListeners(); }
  void setFrameRate(int value) {
    if (![24, 30, 60].contains(value) || value == project.frameRate) return;
    _apply(project.copyWith(frameRate: value));
  }
  void rename(String name) { if (name.trim().isNotEmpty) _apply(project.copyWith(name: name.trim())); }
  void setRatio(CanvasRatio value) => _apply(project.copyWith(ratio: value));
  void addClips(List<VideoClip> clips) {
    if (clips.isEmpty) return;
    final offset = project.durationMs;
    selectedId = clips.first.id;
    _apply(project.copyWith(clips: [...project.clips, ...clips]));
    seek(offset);
  }
  void trim(String id, int start, int end) {
    final clip = project.clips.firstWhere((c) => c.id == id);
    if (start < 0 || end > clip.sourceDurationMs || end - start < 100) return;
    _apply(project.copyWith(clips: project.clips.map((c) => c.id == id
      ? c.copyWith(startMs: start, endMs: end) : c).toList()));
  }
  bool split() {
    final index = project.clipAt(positionMs);
    if (index < 0) return false;
    final clip = project.clips[index];
    final local = positionMs - project.clipOffset(index);
    if (local < 100 || clip.durationMs - local < 100) return false;
    final cut = clip.sourcePositionAt(local);
    if (cut - clip.startMs < 100 || clip.endMs - cut < 100) return false;
    final right = clip.copyWith(id: newId(), startMs: cut);
    final clips = [...project.clips];
    clips.replaceRange(index, index + 1, [
      clip.copyWith(endMs: cut, transition: ClipTransition.none), right,
    ]);
    selectedId = right.id;
    _apply(project.copyWith(clips: clips));
    return true;
  }
  void removeSelected() {
    if (selected == null) return;
    _apply(project.copyWith(clips: project.clips.where((c) => c.id != selectedId).toList()));
  }
  void duplicateSelected() {
    if (selected == null) return;
    final index = project.clips.indexOf(selected!);
    final copy = selected!.copyWith(id: newId());
    final clips = [...project.clips]..insert(index + 1, copy);
    selectedId = copy.id;
    _apply(project.copyWith(clips: clips));
  }
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final clips = [...project.clips];
    final moved = clips.removeAt(oldIndex);
    clips.insert(newIndex, moved);
    _apply(project.copyWith(clips: clips));
  }
  void setMuted(bool value) {
    _apply(project.copyWith(clips: project.clips.map((c) => c.id == selectedId
      ? c.copyWith(muted: value) : c).toList()));
  }
  void setTransition(ClipTransition value) {
    _apply(project.copyWith(clips: project.clips.map((c) => c.id == selectedId
      ? c.copyWith(transition: value) : c).toList()));
  }
  void setSpeed(double value) {
    final selectedClip = selected;
    if (selectedClip == null || !supportedClipSpeeds.contains(value) || value == selectedClip.speed) return;
    final anchorIndex = project.clipAt(positionMs);
    final anchor = project.clips[anchorIndex];
    final sourcePosition = anchor.sourcePositionAt(positionMs - project.clipOffset(anchorIndex));
    _apply(project.copyWith(clips: project.clips.map((clip) => clip.id == selectedClip.id
      ? clip.copyWith(speed: value) : clip).toList()));
    final newIndex = project.clips.indexWhere((clip) => clip.id == anchor.id);
    seek(project.clipOffset(newIndex) + project.clips[newIndex].timelinePositionAt(sourcePosition));
  }
  void setFilter(ClipFilter filter, double intensity) {
    if (selected == null || !intensity.isFinite || intensity < 0 || intensity > 1) return;
    if (selected!.filter == filter && selected!.filterIntensity == intensity) return;
    _apply(project.copyWith(clips: project.clips.map((clip) => clip.id == selectedId
      ? clip.copyWith(filter: filter, filterIntensity: intensity) : clip).toList()));
  }
  void setMusic(MusicTrack? track) {
    if (track != null && !track.isValid) return;
    _apply(project.copyWith(music: track, removeMusic: track == null));
  }
  void setClipVolume(double volume) {
    if (selected == null || !volume.isFinite || volume < 0 || volume > 1 || volume == selected!.volume) return;
    _apply(project.copyWith(clips: project.clips.map((clip) => clip.id == selectedId
      ? clip.copyWith(volume: volume) : clip).toList()));
  }
  bool putAudioLayer(AudioLayer layer) {
    if (!layer.isValid) return false;
    final index = project.audioLayers.indexWhere((item) => item.id == layer.id);
    if (index < 0 && project.audioLayers.length >= maxAdditionalAudioLayers) return false;
    final layers = [...project.audioLayers];
    if (index < 0) { layers.add(layer); } else { layers[index] = layer; }
    _apply(project.copyWith(audioLayers: layers));
    return true;
  }
  void removeAudioLayer(String id) {
    if (!project.audioLayers.any((layer) => layer.id == id)) return;
    _apply(project.copyWith(audioLayers: project.audioLayers.where((layer) => layer.id != id).toList()));
  }
  bool duplicateAudioLayer(String id, {int? timelineStartMs}) {
    final layers = project.audioLayers.where((layer) => layer.id == id);
    if (layers.isEmpty) return false;
    final layer = layers.first;
    return putAudioLayer(layer.copyWith(id: newId(), track: timelineStartMs == null
      ? layer.track : layer.track.copyWith(timelineStartMs: timelineStartMs)));
  }
  void toggleAudioMute(String id) {
    if (id == soundtrackId) {
      final music = project.music;
      if (music != null) setMusic(music.copyWith(muted: !music.muted));
      return;
    }
    final layers = project.audioLayers.where((layer) => layer.id == id);
    if (layers.isNotEmpty) {
      final layer = layers.first;
      putAudioLayer(layer.copyWith(track: layer.track.copyWith(muted: !layer.track.muted)));
    }
  }
  void setMotion(ClipFit fit, bool flipX, List<MotionKeyframe> keyframes) {
    final clip = selected;
    if (clip == null || keyframes.any((frame) => !frame.isValid || frame.sourceMs > clip.sourceDurationMs)) return;
    final sorted = [...keyframes]..sort((a, b) => a.sourceMs.compareTo(b.sourceMs));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].sourceMs == sorted[i - 1].sourceMs) return;
    }
    _apply(project.copyWith(clips: project.clips.map((c) => c.id == clip.id
      ? c.copyWith(fit: fit, flipX: flipX, keyframes: sorted) : c).toList()));
  }
  void putImage(ImageLayer layer) {
    if (!layer.isValid || (project.images.length >= 20 && !project.images.any((image) => image.id == layer.id))) return;
    final layers = [...project.images];
    final index = layers.indexWhere((image) => image.id == layer.id);
    if (index < 0) { layers.add(layer); } else { layers[index] = layer; }
    _apply(project.copyWith(images: layers));
  }
  void removeImage(String id) => _apply(project.copyWith(images: project.images.where((image) => image.id != id).toList()));
  void replaceCaptions(List<TextLayer> captions) => _apply(project.copyWith(
    texts: [...project.texts.where((text) => !text.isCaption), ...captions]));
  void putText(TextLayer layer) {
    final layers = [...project.texts];
    final index = layers.indexWhere((t) => t.id == layer.id);
    if (index < 0) { layers.add(layer); } else { layers[index] = layer; }
    _apply(project.copyWith(texts: layers));
  }
  void removeText(String id) => _apply(project.copyWith(texts: project.texts.where((t) => t.id != id).toList()));
  int _positionIn(VideoProject restored) {
    final index = project.clipAt(positionMs);
    if (index < 0) return 0;
    final current = project.clips[index];
    final newIndex = restored.clips.indexWhere((clip) => clip.id == current.id);
    if (newIndex < 0) return positionMs.clamp(0, restored.durationMs).toInt();
    final source = current.sourcePositionAt(positionMs - project.clipOffset(index));
    return restored.clipOffset(newIndex) + restored.clips[newIndex].timelinePositionAt(source);
  }
  void undo() {
    if (!canUndo) return;
    final restored = _undo.removeLast();
    final position = _positionIn(restored);
    _redo.add(project); project = restored.copyWith(); positionMs = position; _changed();
  }
  void redo() {
    if (!canRedo) return;
    final restored = _redo.removeLast();
    final position = _positionIn(restored);
    _undo.add(project); project = restored.copyWith(); positionMs = position; _changed();
  }
  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    super.dispose();
  }
}
