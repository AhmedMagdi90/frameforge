import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project.dart';
import '../models/timeline_grid.dart';
import '../services/project_library.dart';
import '../state/editor_controller.dart';
import '../theme.dart';
import '../widgets/timeline.dart';
import '../widgets/video_preview.dart';
import 'export_sheet.dart';
import 'text_sheet.dart';
import 'filter_sheet.dart';
import 'motion_sheet.dart';
import 'image_sheet.dart';
import 'music_sheet.dart';
import 'audio_layers_sheet.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project, required this.library});
  final VideoProject project;
  final ProjectLibrary library;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late final EditorController _editor;
  bool _playing = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState(); _editor = EditorController(widget.project, widget.library);
    WidgetsBinding.instance.addObserver(this);
    _editor.addListener(_refresh);
    if (widget.project.clips.isNotEmpty) _editor.select(widget.project.clips.first.id);
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _pause(); unawaited(_editor.flush()); }
  }
  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  void _pause() { if (_playing) setState(() => _playing = false); }
  void _seek(int value) { _pause(); _editor.seekWithSnap(value); }
  Future<bool> _saveAndLeave() async {
    if (_busy) return false;
    _pause(); await _editor.flush();
    if (_editor.saveError != null) { _message(_editor.saveError!); return false; }
    return true;
  }
  Future<void> _importVideos() async {
    if (_busy) return;
    _pause(); setState(() => _busy = true);
    try {
      final clips = await widget.library.importVideos(_editor.project.id);
      if (mounted) _editor.addClips(clips);
    } catch (error) { _message('Could not import videos: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _importMusic() async {
    if (_busy) return;
    final previous = _editor.project.music;
    _pause(); setState(() => _busy = true);
    try {
      final music = await widget.library.importMusic(_editor.project.id);
      if (mounted && music != null) _editor.setMusic(previous == null ? music : music.copyWith(
        timelineStartMs: previous.timelineStartMs, volume: previous.volume, loop: previous.loop,
        muted: previous.muted, fadeInMs: previous.fadeInMs, fadeOutMs: previous.fadeOutMs));
    } catch (error) { _message('Could not import audio: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _rename() async {
    final controller = TextEditingController(text: _editor.project.name);
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Name your story'), content: TextField(controller: controller, autofocus: true,
        maxLength: 60, decoration: const InputDecoration(hintText: 'Project name')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save'))]));
    // The dialog route may still animate with its TextField after it is popped.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (name != null && mounted) _editor.rename(name);
  }
  Future<void> _panel(Widget child) async {
    _pause();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: surface, showDragHandle: true,
      builder: (_) => SafeArea(child: SingleChildScrollView(padding: EdgeInsets.only(
        left: 22, right: 22, bottom: MediaQuery.of(context).viewInsets.bottom + 24), child: child)));
  }
  Future<void> _trim() async {
    final clip = _editor.selected;
    if (clip == null) { _message('Select a clip first.'); return; }
    var values = RangeValues(clip.startMs.toDouble(), clip.endMs.toDouble());
    await _panel(StatefulBuilder(builder: (context, setPanelState) => Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Keep the best part', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), Text(clip.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
        const SizedBox(height: 26), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('IN  ${formatTime(values.start.round(), tenths: true)}', style: const TextStyle(color: mint, fontSize: 12)),
          Text('OUT  ${formatTime(values.end.round(), tenths: true)}', style: const TextStyle(color: mint, fontSize: 12))]),
        RangeSlider(values: values, max: clip.sourceDurationMs.toDouble(),
          onChanged: (v) { if (v.end - v.start >= 100) setPanelState(() => values = v); }),
        Text('${((values.end - values.start) / clip.speed / 1000).toStringAsFixed(2)} seconds at ${clip.speed}×',
          style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 22), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          _editor.trim(clip.id, values.start.round(), values.end.round());
          final index = _editor.project.clips.indexWhere((c) => c.id == clip.id);
          _editor.seek(_editor.project.clipOffset(index)); Navigator.pop(context);
        }, child: const Text('Apply trim'))),
      ])));
  }
  Future<void> _audio() async {
    if (_editor.project.clips.isEmpty) { _message('Add a video before adding audio layers.'); return; }
    await _panel(AudioLayersSheet(editor: _editor, onSoundtrack: _soundtrack,
      onAdd: _addAudioLayer, onEdit: _editAudioLayer));
  }
  Future<void> _soundtrack() async {
    if (_editor.project.clips.isEmpty) { _message('Add a video before adding a soundtrack.'); return; }
    _pause();
    if (_editor.project.music == null) await _importMusic();
    if (!mounted || _editor.project.music == null) return;
    var music = _editor.project.music!;
    if (music.sourceDurationMs == null) {
      setState(() => _busy = true);
      try {
        music = await widget.library.resolveMusic(music);
        if (mounted) _editor.setMusic(music);
      } catch (error) { _message('Could not read this music: $error'); return; }
      finally { if (mounted) setState(() => _busy = false); }
    }
    if (!mounted) return;
    await _panel(MusicSheet(track: music, durationMs: _editor.project.durationMs,
      onSave: _editor.setMusic, onReplace: () async { await _importMusic(); if (mounted) await _soundtrack(); },
      onRemove: () => _editor.setMusic(null)));
  }
  Future<void> _addAudioLayer(AudioKind kind) async {
    if (_busy || _editor.project.audioLayers.length >= maxAdditionalAudioLayers) return;
    final start = _editor.positionMs.clamp(0, _editor.project.durationMs - 1).toInt();
    _pause(); setState(() => _busy = true);
    AudioLayer? layer;
    try {
      final imported = await widget.library.importMusic(_editor.project.id);
      if (!mounted || imported == null) return;
      layer = AudioLayer(id: newId(), kind: kind, track: imported.copyWith(timelineStartMs: start,
        loop: kind == AudioKind.music, volume: kind == AudioKind.music ? .6 : 1));
      _editor.putAudioLayer(layer);
    } catch (error) { _message('Could not import audio: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
    if (mounted && layer != null) await _editAudioLayer(layer);
  }
  Future<void> _editAudioLayer(AudioLayer requested) async {
    if (requested.id == soundtrackId) { await _soundtrack(); return; }
    final matches = _editor.project.audioLayers.where((layer) => layer.id == requested.id);
    if (matches.isEmpty) return;
    _pause();
    var layer = matches.first;
    if (layer.track.sourceDurationMs == null) {
      setState(() => _busy = true);
      try {
        layer = layer.copyWith(track: await widget.library.resolveMusic(layer.track));
        if (mounted) _editor.putAudioLayer(layer);
      } catch (error) { _message('Could not read this audio: $error'); return; }
      finally { if (mounted) setState(() => _busy = false); }
    }
    if (!mounted) return;
    await _panel(MusicSheet(track: layer.track, durationMs: _editor.project.durationMs,
      title: '${layer.kind.label} studio', onSave: (track) => _editor.putAudioLayer(layer.copyWith(track: track)),
      onReplace: () => _replaceAudioLayer(layer), onRemove: () => _editor.removeAudioLayer(layer.id)));
  }
  Future<void> _replaceAudioLayer(AudioLayer layer) async {
    if (_busy) return;
    _pause(); setState(() => _busy = true);
    AudioLayer? replacement;
    try {
      final imported = await widget.library.importMusic(_editor.project.id);
      if (!mounted || imported == null) return;
      replacement = layer.copyWith(track: imported.copyWith(timelineStartMs: layer.track.timelineStartMs,
        volume: layer.track.volume, loop: layer.track.loop, muted: layer.track.muted,
        fadeInMs: layer.track.fadeInMs, fadeOutMs: layer.track.fadeOutMs));
      _editor.putAudioLayer(replacement);
    } catch (error) { _message('Could not replace audio: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
    if (mounted && replacement != null) await _editAudioLayer(replacement);
  }
  Future<void> _volume() async {
    final clip = _editor.selected;
    if (clip == null) { _message('Select a clip first.'); return; }
    var volume = clip.volume;
    await _panel(StatefulBuilder(builder: (context, setPanelState) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Clip volume', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), Text(clip.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mint)),
        if (clip.muted) const Padding(padding: EdgeInsets.only(top: 12), child: Text('This clip is muted. Unmute it to hear this level.',
          style: TextStyle(color: muted, fontSize: 12))),
        const SizedBox(height: 18), Text('Volume  ${(volume * 100).round()}%'),
        Slider(value: volume, onChanged: (value) => setPanelState(() => volume = value)),
        const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          _editor.setClipVolume(volume); Navigator.pop(context);
        }, child: const Text('Apply volume'))),
      ])));
  }
  Future<void> _goToTime() async {
    _pause();
    final input = TextEditingController(text: formatPreciseTime(_editor.positionMs));
    String? error;
    final position = await showDialog<int>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: const Text('Go to time'),
        content: TextField(controller: input, autofocus: true, keyboardType: TextInputType.datetime,
          decoration: InputDecoration(hintText: 'M:SS.mmm or seconds', errorText: error)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            try {
              final ms = TimelineGrid.parseTime(input.text);
              if (ms > _editor.project.durationMs) throw const FormatException('Choose a time inside the video.');
              Navigator.pop(dialogContext, ms);
            } on FormatException catch (e) { update(() => error = e.message); }
          }, child: const Text('Go'))])));
    if (position != null && mounted) _editor.seek(position);
    await Future<void>.delayed(const Duration(milliseconds: 300)); input.dispose();
  }
  Future<void> _speed() async {
    final clip = _editor.selected;
    if (clip == null) { _message('Select a clip first.'); return; }
    var speed = clip.speed;
    await _panel(StatefulBuilder(builder: (context, setPanelState) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Set the pace', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), Text(clip.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
        const SizedBox(height: 24), Wrap(spacing: 8, runSpacing: 8, children: [
          for (final value in supportedClipSpeeds) ChoiceChip(label: Text('${value}×'), selected: speed == value,
            onSelected: (_) => setPanelState(() => speed = value)),
        ]),
        const SizedBox(height: 22), Text('Clip length: ${(clip.trimmedDurationMs / speed / 1000).toStringAsFixed(2)} seconds',
          style: const TextStyle(color: mint, fontSize: 13)),
        const SizedBox(height: 10), const Text('Music stays at normal speed. Text keeps its timeline position.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 22), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          _editor.setSpeed(speed); Navigator.pop(context);
        }, child: const Text('Apply speed'))),
      ])));
  }
  Future<void> _filter() async {
    final clip = _editor.selected;
    if (clip == null) { _message('Select a clip first.'); return; }
    await _panel(FilterSheet(clip: clip, onApply: _editor.setFilter));
  }
  Future<void> _motion() async {
    final clip = _editor.selected;
    if (clip == null) { _message('Select a clip first.'); return; }
    final index = _editor.project.clips.indexOf(clip);
    await _panel(MotionSheet(clip: clip, ratio: _editor.project.ratio,
      localMs: _editor.positionMs - _editor.project.clipOffset(index), onApply: _editor.setMotion));
  }
  Future<void> _image([ImageLayer? existing]) async {
    if (_editor.project.clips.isEmpty) { _message('Add a video before adding an overlay.'); return; }
    _pause();
    var layer = existing;
    if (layer == null) {
      if (_editor.project.images.length >= 20) { _message('Use up to 20 image overlays per project.'); return; }
      setState(() => _busy = true);
      try {
        final duration = _editor.project.durationMs;
        final start = _editor.positionMs.clamp(0, duration >= 100 ? duration - 100 : 0).toInt();
        layer = await widget.library.importImage(_editor.project.id, start, (start + 3000).clamp(start + 1, duration).toInt());
        if (mounted && layer != null) _editor.putImage(layer);
      } catch (error) { _message('Could not import image: $error'); }
      finally { if (mounted) setState(() => _busy = false); }
    }
    if (mounted && layer != null) await _panel(ImageSheet(layer: layer,
      project: _editor.project, onSave: _editor.putImage, onDelete: _editor.removeImage));
  }
  Future<void> _importCaptions() async {
    setState(() => _busy = true);
    try {
      final captions = await widget.library.importCaptions(_editor.project.durationMs);
      if (mounted && captions != null) {
        _editor.replaceCaptions(captions); _message('${captions.length} captions imported. Undo restores the previous set.');
      }
    } catch (error) { _message('Could not import captions: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _shareCaptions() async {
    try {
      final path = await widget.library.exportCaptions(_editor.project);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(files: [XFile(path)],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
    } catch (error) { _message('Could not share captions: $error'); }
  }
  Future<void> _captions() async {
    if (_editor.project.clips.isEmpty) { _message('Add a video before adding captions.'); return; }
    final captions = _editor.project.texts.where((text) => text.isCaption).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    await _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Caption studio', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10), const Text('Import SRT or WebVTT subtitles, or write captions with your own timing.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
      const SizedBox(height: 16), Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: () { Navigator.pop(context); _importCaptions(); },
          icon: const Icon(Icons.file_open_outlined, size: 16), label: const Text('Import subtitles')),
        OutlinedButton(onPressed: () { Navigator.pop(context); _text(null, true); }, child: const Text('Write caption')),
        if (captions.isNotEmpty) TextButton(onPressed: () { Navigator.pop(context); _shareCaptions(); }, child: const Text('Share SRT')),
      ]),
      if (captions.isNotEmpty) SizedBox(height: 320, child: ListView.builder(
        itemCount: captions.length, itemBuilder: (context, index) {
        final caption = captions[index];
        return ListTile(contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.closed_caption_outlined, color: violet, size: 20),
        title: Text(caption.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text('${formatTime(caption.startMs, tenths: true)} – ${formatTime(caption.endMs, tenths: true)}',
          style: const TextStyle(color: muted, fontSize: 11)),
        onTap: () { Navigator.pop(context); _editor.seek(caption.startMs); _text(caption); });
      })),
      if (captions.isNotEmpty) Center(child: TextButton(onPressed: () {
        _editor.replaceCaptions([]); Navigator.pop(context);
      }, child: const Text('Remove all captions'))),
    ]));
  }
  Future<void> _text([TextLayer? existing, bool caption = false]) async {
    if (_editor.project.clips.isEmpty) { _message('Add a video before adding text.'); return; }
    _pause();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, backgroundColor: surface, builder: (_) => TextSheet(
        project: _editor.project, positionMs: _editor.positionMs, existing: existing,
        caption: caption,
        onSave: _editor.putText, onDelete: _editor.removeText));
  }
  Future<void> _transition() async {
    final clip = _editor.selected;
    if (clip == null) { _message('Select a clip first.'); return; }
    if (_editor.project.clips.last.id == clip.id) {
      _message('Choose a clip with another clip after it to add a transition.'); return;
    }
    await _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('A smoother story', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), const Text('Transition to the next clip. Fade passes through black.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 20),
      for (final type in ClipTransition.values) ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(type == ClipTransition.fade ? Icons.gradient_rounded : Icons.content_cut_rounded, color: violet),
        title: Text(type == ClipTransition.fade ? 'Fade through black' : 'Cut'),
        subtitle: type == ClipTransition.fade ? const Text('Up to 0.3 seconds on each side', style: TextStyle(fontSize: 12, color: muted)) : null,
        trailing: clip.transition == type ? const Icon(Icons.check_circle_rounded, color: mint) : null,
        onTap: () { _editor.setTransition(type); Navigator.pop(context); }),
    ]));
  }
  Future<void> _canvas() async => _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Choose your canvas', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8), const Text('Use Frame & motion to fit or crop each clip.', style: TextStyle(color: muted, fontSize: 12)),
    const SizedBox(height: 18),
    for (final ratio in CanvasRatio.values) ListTile(contentPadding: EdgeInsets.zero,
      leading: Icon(switch (ratio) { CanvasRatio.portrait => Icons.stay_current_portrait_rounded,
        CanvasRatio.landscape => Icons.stay_current_landscape_rounded, CanvasRatio.square => Icons.crop_square_rounded }, color: violet),
      title: Text(ratio.label), subtitle: Text(switch (ratio) { CanvasRatio.portrait => 'Reels & stories',
        CanvasRatio.landscape => 'YouTube & widescreen', CanvasRatio.square => 'Social posts' }, style: const TextStyle(color: muted, fontSize: 12)),
      trailing: ratio == _editor.project.ratio ? const Icon(Icons.check_circle_rounded, color: mint) : null,
      onTap: () { _editor.setRatio(ratio); Navigator.pop(context); }),
  ]));

  @override
  Widget build(BuildContext context) {
    final hasClips = _editor.project.clips.isNotEmpty;
    return WillPopScope(onWillPop: _saveAndLeave, child: Scaffold(
      appBar: AppBar(leading: IconButton(tooltip: 'Save and close', icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _busy ? null : () async { if (await _saveAndLeave() && mounted) Navigator.pop(context); }),
        titleSpacing: 0, title: GestureDetector(onTap: _rename, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_editor.project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2), Text(_editor.saveError != null ? 'Saving needs attention' : _editor.saving ? 'Saving draft…' : 'Saved on your device',
            style: TextStyle(color: _editor.saveError == null ? muted : Colors.redAccent, fontSize: 10))])),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 36)),
          onPressed: hasClips && !_busy ? () async {
            _pause(); await _editor.flush();
            if (!mounted) return;
            await showModalBottomSheet<void>(context: context, isScrollControlled: true, isDismissible: false,
              enableDrag: false, backgroundColor: surface, builder: (_) => ExportSheet(project: _editor.project, library: widget.library));
          } : null, child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Export', style: TextStyle(fontSize: 12)),
            SizedBox(width: 5), Icon(Icons.north_east_rounded, size: 14)])))]),
      body: SafeArea(top: false, child: Stack(children: [Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Row(children: [
          TextButton.icon(onPressed: _canvas, icon: const Icon(Icons.crop_rounded, size: 14),
            label: Text(_editor.project.ratio.label, style: const TextStyle(fontSize: 11))),
          const Spacer(), IconButton(tooltip: 'Undo', onPressed: _editor.canUndo ? () { _pause(); _editor.undo(); } : null,
            icon: const Icon(Icons.undo_rounded, size: 20)),
          IconButton(tooltip: 'Redo', onPressed: _editor.canRedo ? () { _pause(); _editor.redo(); } : null,
            icon: const Icon(Icons.redo_rounded, size: 20)),
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: VideoPreview(
          project: _editor.project, positionMs: _editor.positionMs, playing: _playing,
          onPosition: _editor.seek, onFinished: _pause))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Row(children: [
          Expanded(child: InkWell(onTap: hasClips ? _goToTime : null, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatPreciseTime(_editor.positionMs), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
            Text('/ ${formatTime(_editor.project.durationMs)} · tap to seek', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 9)),
          ]))),
          IconButton(tooltip: 'Previous frame (${_editor.project.frameRate} fps grid)', visualDensity: VisualDensity.compact,
            onPressed: hasClips ? () { _pause(); _editor.stepFrame(-1); } : null, icon: const Icon(Icons.chevron_left_rounded, size: 22)),
          IconButton(tooltip: _playing ? 'Pause' : 'Play', visualDensity: VisualDensity.compact,
            onPressed: !hasClips ? null : () { if (!_playing && _editor.positionMs >= _editor.project.durationMs) _editor.seek(0);
              setState(() => _playing = !_playing); },
            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28)),
          IconButton(tooltip: 'Next frame (${_editor.project.frameRate} fps grid)', visualDensity: VisualDensity.compact,
            onPressed: hasClips ? () { _pause(); _editor.stepFrame(1); } : null, icon: const Icon(Icons.chevron_right_rounded, size: 22)),
          IconButton(tooltip: 'Go to beginning', visualDensity: VisualDensity.compact, onPressed: hasClips ? () => _seek(0) : null,
            icon: const Icon(Icons.skip_previous_rounded, size: 21)),
        ])),
        EditorTimeline(editor: _editor, onSeek: _seek, onAdd: _importVideos, onText: _text,
          onMusic: _soundtrack, onAudioLayer: _editAudioLayer, onImage: _image),
        SizedBox(height: 84, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            _Tool(icon: Icons.add_box_outlined, label: 'Media', onTap: _importVideos),
            _Tool(icon: Icons.content_cut_rounded, label: 'Split', onTap: () { _pause(); if (!_editor.split()) _message('Move the playhead inside a clip to split it.'); }),
            _Tool(icon: Icons.crop_rounded, label: 'Trim', onTap: _trim),
            _Tool(icon: Icons.open_with_rounded, label: 'Motion', onTap: _motion),
            _Tool(icon: Icons.speed_rounded, label: 'Speed', onTap: _speed),
            _Tool(icon: Icons.filter_vintage_outlined, label: 'Filters', onTap: _filter),
            _Tool(icon: Icons.music_note_rounded, label: 'Audio', onTap: _audio),
            _Tool(icon: Icons.tune_rounded, label: 'Volume', onTap: _volume),
            _Tool(icon: Icons.text_fields_rounded, label: 'Text', onTap: () => _text()),
            _Tool(icon: Icons.closed_caption_outlined, label: 'Captions', onTap: _captions),
            _Tool(icon: Icons.add_photo_alternate_outlined, label: 'Overlay', onTap: () => _image()),
            _Tool(icon: Icons.gradient_rounded, label: 'Transition', onTap: _transition),
            _Tool(icon: _editor.selected?.muted == true ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: _editor.selected?.muted == true ? 'Unmute' : 'Mute', onTap: () {
                _pause(); if (_editor.selected != null) _editor.setMuted(!_editor.selected!.muted); }),
            _Tool(icon: Icons.copy_rounded, label: 'Duplicate', onTap: () { _pause(); _editor.duplicateSelected(); }),
            _Tool(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: () { _pause(); _editor.removeSelected(); }),
          ])),
      ]), if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0xAA0C0D12),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(),
          SizedBox(height: 16), Text('Preparing your media…', style: TextStyle(color: muted))])))),
      ])),
    ));
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor.removeListener(_refresh); _editor.dispose(); super.dispose();
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(width: 66, child: InkWell(onTap: onTap,
    borderRadius: BorderRadius.circular(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 23, color: violet), const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 10, color: muted)),
    ])));
}
