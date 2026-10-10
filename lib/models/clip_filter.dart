const identityColorMatrix = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// Matrices operate on linear RGB; offsets use Flutter's 0–255 convention.
enum ClipFilter {
  none('Original', identityColorMatrix),
  mono('Mono', [
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  warm('Warm', [
    1.12, 0, 0, 0, 0,
    0, 1.02, 0, 0, 0,
    0, 0, .86, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  cool('Cool', [
    .88, 0, 0, 0, 0,
    0, 1.02, 0, 0, 0,
    0, 0, 1.14, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  sepia('Sepia', [
    .393, .769, .189, 0, 0,
    .349, .686, .168, 0, 0,
    .272, .534, .131, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  vivid('Vivid', [
    1.18, 0, 0, 0, -10.2,
    0, 1.18, 0, 0, -10.2,
    0, 0, 1.18, 0, -10.2,
    0, 0, 0, 1, 0,
  ]);

  const ClipFilter(this.label, this._matrix);
  final String label;
  final List<double> _matrix;

  List<double> matrix(double intensity) {
    final amount = intensity.clamp(0, 1).toDouble();
    return List.generate(20, (index) => identityColorMatrix[index] +
      (_matrix[index] - identityColorMatrix[index]) * amount);
  }
}
