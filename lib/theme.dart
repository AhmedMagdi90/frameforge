import 'package:flutter/material.dart';

const ink = Color(0xFF0C0D12);
const surface = Color(0xFF171920);
const elevated = Color(0xFF22242E);
const violet = Color(0xFFA99AFF);
const mint = Color(0xFF9FE7CF);
const muted = Color(0xFF9699AD);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: const ColorScheme.dark(primary: violet, secondary: mint,
    surface: surface, error: Color(0xFFFFA9AB)),
  appBarTheme: const AppBarTheme(backgroundColor: ink, surfaceTintColor: Colors.transparent),
  dividerColor: const Color(0xFF2C2E38),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
    foregroundColor: ink, backgroundColor: violet, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
  inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: elevated,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
  sliderTheme: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6)),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: elevated),
);

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: violet, borderRadius: BorderRadius.circular(size * .28)),
    child: Icon(Icons.auto_awesome_motion_rounded, color: ink, size: size * .6),
  );
}
