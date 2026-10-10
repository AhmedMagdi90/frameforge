import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/project.dart';
import '../services/preview_audio_mixer.dart';
import '../theme.dart';
import 'filtered_video.dart';

class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.project, required this.positionMs,
    required this.playing, required this.onPosition, required this.onFinished});
  final VideoProject project;
  final int positionMs;
  final bool playing;
  final ValueChanged<int> onPosition;
  final VoidCallback onFinished;
  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  late final PreviewAudioMixer _audio;
  String? _clipId;
  String? _error;
  String? _audioError;
  double? _appliedSpeed;
  int _generation = 0;
  int _reported = -1;
  int _lastReport = 0;
  bool _seeking = false;
  bool _changingClip = false;
  bool _syncRequested = false;
  bool _syncing = false;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    _audio = PreviewAudioMixer(onError: (message) {
      if (mounted) setState(() => _audioError = message);
    });
    unawaited(_sync());
  }
  @override
  void didUpdateWidget(VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.project, widget.project)) _reported = -1;
    unawaited(_sync());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && widget.playing) widget.onFinished();
  }

  Future<void> _sync() async {
    _syncRequested = true;
    if (_syncing) return;
    _syncing = true;
    try {
      while (mounted && _syncRequested) {
        _syncRequested = false;
        await _syncOnce();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'This clip could not be played. Try normal speed or another video.');
        widget.onFinished();
      }
    } finally { _syncing = false; }
  }

  Future<void> _syncOnce() async {
    final index = widget.project.clipAt(widget.positionMs);
    if (index < 0) {
      _generation++;
      final old = _video;
      _video = null; _clipId = null;
      _appliedSpeed = null;
      await old?.dispose(); await _audio.pause();
      _audio.update(widget.project, widget.positionMs, false);
      if (mounted) setState(() {});
      return;
    }
    final clip = widget.project.clips[index];
    final sourcePosition = clip.sourcePositionAt(widget.positionMs - widget.project.clipOffset(index));
    if (_clipId != clip.id) {
      final generation = ++_generation;
      _clipId = clip.id; _error = null; _changingClip = true;
      await _audio.pause();
      final old = _video;
      _video = null;
      _appliedSpeed = null;
      await old?.dispose();
      final controller = VideoPlayerController.file(File(clip.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      try {
        await controller.initialize();
        if (!mounted || generation != _generation) { await controller.dispose(); return; }
        _video = controller;
        await controller.seekTo(Duration(milliseconds: sourcePosition.clamp(clip.startMs, clip.endMs).toInt()));
        if (!mounted || generation != _generation) return;
        controller.addListener(_tick);
        _changingClip = false;
        setState(() {});
      } catch (error) {
        await controller.dispose();
        if (mounted && generation == _generation) {
          _changingClip = false; _error = 'This clip could not be previewed. Try another video.';
          setState(() {}); widget.onFinished();
        }
        return;
      }
    } else if (!_changingClip && _video != null && !_seeking &&
        widget.positionMs != _reported &&
        (_video!.value.position.inMilliseconds - sourcePosition).abs() > (widget.playing ? math.max(1, 20 * clip.playbackSpeed) : 0)) {
      _seeking = true;
      try { await _video!.seekTo(Duration(milliseconds: sourcePosition)); }
      finally { _seeking = false; }
    }
    final controller = _video;
    if (!mounted || controller == null || _changingClip) return;
    await controller.setVolume(clip.muted ? 0 : clip.volume);
    if (!mounted || controller != _video) return;
    if (_appliedSpeed == null || (_appliedSpeed! - clip.playbackSpeed).abs() > .00001) {
      await controller.setPlaybackSpeed(clip.playbackSpeed);
      _appliedSpeed = clip.playbackSpeed;
      if (_error != null && mounted) setState(() => _error = null);
    }
    if (widget.playing) { await controller.play(); } else { await controller.pause(); }
    _audio.update(widget.project, widget.positionMs, widget.playing && !_changingClip);
  }

  void _tick() {
    if (!mounted || !widget.playing || _seeking || _changingClip || _video == null) return;
    if (_video!.value.hasError) {
      setState(() => _error = 'Video playback failed. Try another video.');
      widget.onFinished(); return;
    }
    final index = widget.project.clips.indexWhere((c) => c.id == _clipId);
    if (index < 0) return;
    final clip = widget.project.clips[index];
    final source = _video!.value.position.inMilliseconds;
    final offset = widget.project.clipOffset(index);
    if (source >= clip.endMs || _video!.value.isCompleted) {
      _changingClip = true;
      unawaited(_video!.pause());
      if (index == widget.project.clips.length - 1) {
        _reported = widget.project.durationMs;
        widget.onPosition(_reported); widget.onFinished();
        _changingClip = false;
      } else {
        _reported = offset + clip.durationMs;
        widget.onPosition(_reported);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastReport < 60) return;
    _lastReport = now;
    _reported = offset + clip.timelinePositionAt(source);
    widget.onPosition(_reported);
  }

  double _opacity() {
    final index = widget.project.clipAt(widget.positionMs);
    if (index < 0) return 1;
    final clip = widget.project.clips[index];
    final local = widget.positionMs - widget.project.clipOffset(index);
    var opacity = 1.0;
    // 300ms each side, shortened for very small clips. Export uses the same rule.
    if (index > 0 && widget.project.clips[index - 1].transition == ClipTransition.fade) {
      opacity = math.min(opacity, local / math.min(300, clip.durationMs / 2));
    }
    if (index < widget.project.clips.length - 1 && clip.transition == ClipTransition.fade) {
      opacity = math.min(opacity, (clip.durationMs - local) / math.min(300, clip.durationMs / 2));
    }
    return opacity.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final ratio = widget.project.ratio.aspect;
    final height = math.min(box.maxHeight, box.maxWidth / ratio);
    final width = height * ratio;
    final index = widget.project.clipAt(widget.positionMs);
    final activeClip = index < 0 ? null : widget.project.clips[index];
    final motion = activeClip == null ? null : activeClip.motionAtTimeline(widget.positionMs - widget.project.clipOffset(index));
    return Center(child: Container(width: width, height: height,
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Stack(alignment: Alignment.center, children: [
        if (widget.project.clips.isEmpty) const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.movie_creation_outlined, color: muted, size: 38), SizedBox(height: 12),
          Text('Your story goes here', style: TextStyle(color: muted, fontSize: 12)),
        ])
        else if (_error != null) Padding(padding: const EdgeInsets.all(18),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 12)))
        else if (_video?.value.isInitialized == true && activeClip != null && motion != null) Positioned.fill(
          child: Transform(alignment: Alignment.center,
            transform: Matrix4.identity()..translate(motion.x * width, motion.y * height)
              ..rotateZ(motion.rotation * math.pi / 180)..scale(motion.zoom * (activeClip.flipX ? -1 : 1), motion.zoom),
            child: ClipRect(child: FittedBox(fit: activeClip.fit == ClipFit.fill ? BoxFit.cover : BoxFit.contain,
              child: SizedBox(width: _video!.value.size.width, height: _video!.value.size.height,
                child: FilteredVideo(filter: activeClip.filter, intensity: activeClip.filterIntensity,
                  brightness: _opacity(), child: VideoPlayer(_video!)))))))
        else const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        for (final image in widget.project.images)
          if (widget.positionMs >= image.startMs && widget.positionMs < image.endMs)
            Positioned(left: width * image.x, top: height * image.y,
              child: FractionalTranslation(translation: const Offset(-.5, -.5),
                child: Transform.rotate(angle: image.rotation * math.pi / 180,
                  child: Opacity(opacity: image.opacity, child: Image.file(File(image.path),
                    width: width * image.width, height: width * image.width / image.aspect,
                    fit: BoxFit.fill, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: muted)))))),
        for (final text in widget.project.texts)
          if (widget.positionMs >= text.startMs && widget.positionMs < text.endMs)
            Positioned(left: width * .08, right: width * .08, top: height * text.y,
              child: FractionalTranslation(translation: const Offset(0, -.5),
                child: Text(text.text, textAlign: TextAlign.center, style: TextStyle(
                  color: Color(text.color), fontSize: height * text.size, height: 1.15,
                  fontWeight: FontWeight.bold, shadows: const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))])))),
        if (_audioError != null) Positioned(left: 8, right: 8, bottom: 8,
          child: ColoredBox(color: const Color(0xCC000000), child: Padding(padding: const EdgeInsets.all(8),
            child: Text(_audioError!, style: const TextStyle(color: Colors.redAccent, fontSize: 10))))),
      ]),
    ));
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _video?.removeListener(_tick);
    unawaited(_video?.dispose()); unawaited(_audio.dispose());
    super.dispose();
  }
}
