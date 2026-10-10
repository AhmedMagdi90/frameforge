import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:frameforge/screens/ai_studio_screen.dart';
import 'package:frameforge/services/ai_client.dart';
import 'package:frameforge/services/project_library.dart';
import 'ai_client_test.dart' show MemoryCredentials, capabilities;

void main() {
  testWidgets('AI studio offers service connection without requiring an account for local editing', (tester) async {
    final client = AiClient(credentials: MemoryCredentials(), httpClient: MockClient((_) async => capabilities()));
    await tester.pumpWidget(MaterialApp(home: AiStudioScreen(library: ProjectLibrary(), client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Connect AI service'), findsOneWidget);
    expect(find.text('Generate video'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); client.close();
  });
  testWidgets('connected studio discloses synthetic media and separate API billing before sign-in', (tester) async {
    final storage = MemoryCredentials()..values['ff_ai_url'] = 'https://example.com';
    final client = AiClient(credentials: storage, httpClient: MockClient((_) async => capabilities()));
    await tester.pumpWidget(MaterialApp(home: AiStudioScreen(library: ProjectLibrary(), client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    expect(find.textContaining('separately from your ChatGPT subscription'), findsOneWidget);
    expect(find.text('Generate video'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); client.close();
  });
}
