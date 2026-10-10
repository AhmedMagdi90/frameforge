import 'package:flutter/material.dart';
import 'screens/library_screen.dart';
import 'services/project_library.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FrameForgeApp());
}

class FrameForgeApp extends StatelessWidget {
  const FrameForgeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FrameForge', debugShowCheckedModeBanner: false,
    theme: appTheme(), home: LibraryScreen(library: ProjectLibrary()),
  );
}
