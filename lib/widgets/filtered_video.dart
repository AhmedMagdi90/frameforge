import 'package:flutter/material.dart';
import '../models/clip_filter.dart';

/// Mirror native linear-RGB processing; leave the surrounding canvas untouched.
class FilteredVideo extends StatelessWidget {
  const FilteredVideo({super.key, required this.filter, required this.intensity, required this.child, this.brightness = 1});
  final ClipFilter filter;
  final double intensity;
  final Widget child;
  final double brightness;
  @override
  Widget build(BuildContext context) {
    if ((filter == ClipFilter.none || intensity == 0) && brightness == 1) return child;
    final matrix = filter.matrix(intensity);
    for (var index = 0; index < 15; index++) {
      matrix[index] *= brightness.clamp(0, 1).toDouble();
    }
    return ColorFiltered(colorFilter: const ColorFilter.linearToSrgbGamma(),
      child: ColorFiltered(colorFilter: ColorFilter.matrix(matrix),
        child: ColorFiltered(colorFilter: const ColorFilter.srgbToLinearGamma(), child: child)));
  }
}
