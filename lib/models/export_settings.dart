class ExportSettings {
  const ExportSettings({this.shortEdge = 1080, this.fps = 30});
  final int shortEdge;
  final int fps;
  static const resolutions = [720, 1080, 2160];
  static const frameRates = [24, 30, 60];
  bool get isValid => resolutions.contains(shortEdge) && frameRates.contains(fps);
}
