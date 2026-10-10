import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project.dart';
import '../models/export_settings.dart';
import '../services/native_engine.dart';
import '../services/project_library.dart';
import '../theme.dart';

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.project, required this.library});
  final VideoProject project;
  final ProjectLibrary library;
  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  final _engine = NativeEngine();
  StreamSubscription<double>? _subscription;
  int _resolution = 1080;
  int _fps = 30;
  double _progress = 0;
  bool _exporting = false;
  bool _cancelling = false;
  String? _output;
  String? _error;
  List<String> _previous = [];
  @override
  void initState() { super.initState(); _fps = widget.project.frameRate; unawaited(_loadPrevious()); }
  Future<void> _loadPrevious() async {
    try {
      final values = await widget.library.exports(widget.project.id);
      if (mounted) setState(() => _previous = values);
    } catch (error) { if (mounted) setState(() => _error = 'Could not read previous exports: $error'); }
  }
  Future<void> _export() async {
    setState(() { _exporting = true; _progress = 0; _error = null; });
    String? path;
    try {
      path = await widget.library.exportPath(widget.project.id);
      if (_cancelling) throw StateError('Export cancelled');
      _subscription = _engine.progress.listen((value) {
        if (mounted) setState(() => _progress = value);
      }, onError: (Object error) { /* The method result reports export errors. */ });
      final result = await _engine.export(widget.project, path, _resolution, fps: _fps);
      if (!await File(result).exists() || await File(result).length() == 0) {
        throw StateError('The video was not written. Please try again.');
      }
      if (mounted) setState(() => _output = result);
    } catch (error) {
      if (path != null) {
        try { if (await File(path).exists()) await File(path).delete(); }
        on FileSystemException { /* Native cancellation also removes partial output. */ }
      }
      if (mounted) setState(() => _error = _cancelling ? 'Export cancelled. Your draft is saved.' : 'Export failed: $error');
    } finally {
      await _subscription?.cancel(); _subscription = null;
      if (mounted) setState(() { _exporting = false; _cancelling = false; });
    }
  }
  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try { await _engine.cancel(); }
    catch (error) { if (mounted) setState(() { _cancelling = false; _error = 'Could not cancel: $error'; }); }
  }
  Future<void> _share() async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(files: [XFile(_output!)],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
    } catch (error) { if (mounted) setState(() => _error = 'Could not share this video: $error'); }
  }
  @override
  Widget build(BuildContext context) {
    final (width, height) = widget.project.ratio.dimensions(_resolution);
    return WillPopScope(onWillPop: () async => !_exporting, child: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(_output != null ? 'Your story is ready.' : 'Ready for the world?',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -.5))),
            IconButton(tooltip: 'Close', onPressed: _exporting ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))]),
          const SizedBox(height: 10),
          if (_output != null) ...[
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Icon(Icons.check_circle_outline_rounded, color: mint, size: 64))),
            const Text('Export saved in your project. Share it or save it to your gallery using the share menu.', style: TextStyle(color: muted, height: 1.5)),
            const SizedBox(height: 24), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _share,
              icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Share video'))),
          ] else ...[
            const Text('Your clips, text and soundtrack. One finished video.', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 26), const Text('RESOLUTION', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5)),
            const SizedBox(height: 12), Row(children: [for (final resolution in ExportSettings.resolutions) Expanded(child: Padding(
              padding: const EdgeInsets.only(right: 8), child: ChoiceChip(selected: _resolution == resolution,
                label: Text(resolution == 2160 ? '4K' : '${resolution}p'), onSelected: _exporting ? null : (_) => setState(() => _resolution = resolution))))]),
            const SizedBox(height: 16), const Text('FRAME RATE', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5)),
            const SizedBox(height: 8), Wrap(spacing: 8, children: [for (final fps in ExportSettings.frameRates)
              ChoiceChip(label: Text('$fps fps'), selected: _fps == fps,
                onSelected: _exporting ? null : (_) => setState(() => _fps = fps))]),
            const SizedBox(height: 18), Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: elevated, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [const Icon(Icons.movie_outlined, color: violet, size: 24), const SizedBox(width: 12),
                Flexible(child: Text('$width × $height  ·  $_fps fps target\nMP4 · SDR · ${formatTime(widget.project.durationMs)}', style: const TextStyle(fontSize: 12, height: 1.8)))])),
            const SizedBox(height: 10), const Text('4K and 60 fps depend on your device. Higher settings do not add detail or motion missing from the source.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
            const SizedBox(height: 24),
            if (_exporting) ...[
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 6)),
              const SizedBox(height: 12), Text(_cancelling ? 'Cancelling…' : 'Creating your video… ${(_progress * 100).round()}%', style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 8), const Text('Keep the app open until your export finishes.', style: TextStyle(color: muted, fontSize: 11)),
              Center(child: TextButton(onPressed: _cancelling ? null : _cancel, child: const Text('Cancel export'))),
            ] else SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _export,
              icon: const Icon(Icons.north_east_rounded, size: 18), label: const Text('Export video'))),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          if (!_exporting && _output == null && _previous.isNotEmpty) ...[
            const SizedBox(height: 24), const Text('Recent exports', style: TextStyle(color: muted, fontSize: 12)),
            for (final path in _previous.take(5)) ListTile(contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.movie_outlined, size: 19, color: mint),
              title: Text(_exportDate(path), style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.ios_share_rounded, size: 17),
              onTap: () => setState(() { _output = path; _error = null; })),
          ],
        ]))));
  }
  String _exportDate(String path) {
    final filename = path.split('/').last;
    final stamp = int.tryParse(filename.replaceFirst('FrameForge_', '').replaceFirst('.mp4', ''));
    if (stamp == null) return filename;
    final date = DateTime.fromMillisecondsSinceEpoch(stamp);
    return '${date.month}/${date.day}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  @override
  void dispose() { unawaited(_subscription?.cancel()); super.dispose(); }
}
