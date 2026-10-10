import 'project.dart';

Map<String, dynamic> aiMap(Object? value) {
  if (value is! Map) throw const FormatException('Invalid AI service response');
  return Map<String, dynamic>.from(value);
}

String _text(Object? value, int maximum, {int minimum = 1}) {
  if (value is! String || value.trim().length < minimum || value.length > maximum) {
    throw const FormatException('Invalid AI text');
  }
  return value.trim();
}

CanvasRatio _ratio(Object? value) => CanvasRatio.values.firstWhere(
  (ratio) => ratio.name == value, orElse: () => throw const FormatException('Invalid video ratio'));

class AiScene {
  const AiScene({required this.imagePrompt, required this.narration, required this.caption, required this.seconds});
  final String imagePrompt, narration, caption;
  final int seconds;
  Map<String, dynamic> toJson() => {'image_prompt': imagePrompt, 'narration': narration, 'caption': caption, 'seconds': seconds};
  factory AiScene.fromJson(Map<String, dynamic> json) {
    final seconds = json['seconds'];
    if (seconds is! int || seconds < 2 || seconds > 20) throw const FormatException('Invalid scene timing');
    return AiScene(imagePrompt: _text(json['image_prompt'], 2500, minimum: 10),
      narration: _text(json['narration'], 500), caption: _text(json['caption'], 250), seconds: seconds);
  }
}

class AiVideoPlan {
  AiVideoPlan({required this.title, required this.summary, required this.ratio, required List<AiScene> scenes})
      : scenes = List.unmodifiable(scenes);
  final String title, summary;
  final CanvasRatio ratio;
  final List<AiScene> scenes;
  Map<String, dynamic> toJson() => {'title': title, 'summary': summary, 'ratio': ratio.name,
    'scenes': scenes.map((scene) => scene.toJson()).toList()};
  AiVideoPlan replacingScene(int index, AiScene scene) => AiVideoPlan(title: title, summary: summary, ratio: ratio,
    scenes: [...scenes.take(index), scene, ...scenes.skip(index + 1)]);
  factory AiVideoPlan.fromJson(Map<String, dynamic> json) {
    final scenes = json['scenes'];
    if (scenes is! List || scenes.length < 2 || scenes.length > 6) throw const FormatException('Invalid scene count');
    return AiVideoPlan(title: _text(json['title'], 80), summary: _text(json['summary'], 600), ratio: _ratio(json['ratio']),
      scenes: scenes.map((scene) => AiScene.fromJson(aiMap(scene))).toList());
  }
}

class AiAccount {
  const AiAccount(this.id, this.name, this.email);
  final String id, name;
  final String? email;
  factory AiAccount.fromJson(Map<String, dynamic> json) => AiAccount(_text(json['id'], 100),
    _text(json['name'], 100), json['email'] == null ? null : _text(json['email'], 200));
}

class AiAssetScene {
  const AiAssetScene(this.filename, this.durationMs, this.caption);
  final String filename, caption;
  final int durationMs;
  factory AiAssetScene.fromJson(Map<String, dynamic> json) {
    final name = json['filename'], duration = json['duration_ms'];
    if (name is! String || !RegExp(r'^scene0[1-6]\.mp4$').hasMatch(name) ||
        duration is! int || duration < 100 || duration > 31000) {
      throw const FormatException('Invalid generated scene');
    }
    return AiAssetScene(name, duration, _text(json['caption'], 250));
  }
}

class AiManifest {
  AiManifest(this.title, this.ratio, List<AiAssetScene> scenes) : scenes = List.unmodifiable(scenes);
  final String title;
  final CanvasRatio ratio;
  final List<AiAssetScene> scenes;
  factory AiManifest.fromJson(Map<String, dynamic> json) {
    final values = json['scenes'];
    if (json['video'] != 'video.mp4' || json['subtitles'] != 'captions.srt' || json['ai_voice'] != true ||
        values is! List || values.length < 2 || values.length > 6) {
      throw const FormatException('Invalid generated video');
    }
    final scenes = values.map((value) => AiAssetScene.fromJson(aiMap(value))).toList();
    if (scenes.map((scene) => scene.filename).toSet().length != scenes.length) {
      throw const FormatException('Duplicate generated scene');
    }
    return AiManifest(_text(json['title'], 80), _ratio(json['ratio']), scenes);
  }
}

class AiJob {
  const AiJob({required this.id, required this.status, required this.progress, required this.message,
    required this.plan, this.manifest, this.error});
  final String id, status, message;
  final String? error;
  final double progress;
  final AiVideoPlan plan;
  final AiManifest? manifest;
  bool get active => status == 'queued' || status == 'running';
  factory AiJob.fromJson(Map<String, dynamic> json) {
    final id = json['id'], status = json['status'], progress = json['progress'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !['queued', 'running', 'completed', 'cancelled', 'failed'].contains(status) ||
        progress is! num || !progress.isFinite || progress < 0 || progress > 1) {
      throw const FormatException('Invalid generation status');
    }
    final manifest = json['manifest'] == null ? null : AiManifest.fromJson(aiMap(json['manifest']));
    if (status == 'completed' && manifest == null) throw const FormatException('Missing generated assets');
    return AiJob(id: id, status: status as String, progress: progress.toDouble(), message: _text(json['message'], 500),
      plan: AiVideoPlan.fromJson(aiMap(json['plan'])), manifest: manifest,
      error: json['error'] == null ? null : _text(json['error'], 1000));
  }
}
