import 'music_track.dart';

const soundtrackId = '__soundtrack__';
const maxAdditionalAudioLayers = 7;

enum AudioKind {
  music('Music'), voice('Voice audio'), effect('Sound effect');
  const AudioKind(this.label);
  final String label;
}

class AudioLayer {
  const AudioLayer({required this.id, required this.track, this.kind = AudioKind.effect});
  final String id;
  final MusicTrack track;
  final AudioKind kind;
  bool get isValid => id.isNotEmpty && id != soundtrackId && track.isValid;
  AudioLayer copyWith({String? id, MusicTrack? track, AudioKind? kind}) => AudioLayer(
    id: id ?? this.id, track: track ?? this.track, kind: kind ?? this.kind);
  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'track': track.toJson()};
  factory AudioLayer.fromJson(Map<String, dynamic> json) {
    final layer = AudioLayer(id: json['id'] as String,
      kind: AudioKind.values.firstWhere((kind) => kind.name == json['kind'], orElse: () => AudioKind.effect),
      track: MusicTrack.fromJson(Map<String, dynamic>.from(json['track'] as Map)));
    if (!layer.isValid) throw const FormatException('Invalid audio layer');
    return layer;
  }
}
