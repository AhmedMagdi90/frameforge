import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameforge/models/project.dart';
import 'package:frameforge/screens/music_sheet.dart';

void main() {
  const song = MusicTrack(path: '/song.wav', name: 'Song', sourceDurationMs: 6000,
    sourceStartMs: 1000, sourceEndMs: 3000);
  MusicTrack? applied;

  Future<void> openStudio(WidgetTester tester) async {
    applied = null;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
        builder: (_) => SafeArea(child: SingleChildScrollView(child: MusicSheet(track: song, durationMs: 5000,
          onSave: (track) => applied = track, onReplace: () {}, onRemove: () {})))), child: const Text('Open audio'))))));
    await tester.tap(find.text('Open audio')); await tester.pumpAndSettle();
  }
  Future<void> enterTime(WidgetTester tester, String button, String time) async {
    await tester.ensureVisible(find.text(button)); await tester.tap(find.text(button)); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), time); await tester.tap(find.text('Set time'));
    await tester.pumpAndSettle();
  }
  Future<void> apply(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Apply audio')); await tester.tap(find.text('Apply audio'));
    await tester.pumpAndSettle();
  }

  testWidgets('exact source and timeline entry survive the audio sheet apply', (tester) async {
    await openStudio(tester);
    await enterTime(tester, 'Set in time', '1.250');
    await enterTime(tester, 'Set out time', '2.750');
    await enterTime(tester, 'Set start time', '2.001');
    expect(applied, isNull); await apply(tester);
    expect(applied!.sourceStartMs, 1250); expect(applied!.sourceEndMs, 2750);
    expect(applied!.timelineStartMs, 2001);
  });

  testWidgets('audio time entry rejects a section shorter than one hundred milliseconds', (tester) async {
    await openStudio(tester);
    await enterTime(tester, 'Set out time', '1.050');
    expect(find.text('Choose a time in the displayed range.'), findsOneWidget);
    expect(applied, isNull);
    await tester.enterText(find.byType(TextField), '1.100'); await tester.tap(find.text('Set time'));
    await tester.pumpAndSettle(); await apply(tester);
    expect(applied!.trimmedDurationMs, 100);
  });

  testWidgets('cancelling exact time entry leaves audio settings untouched', (tester) async {
    await openStudio(tester);
    await tester.ensureVisible(find.text('Set start time')); await tester.tap(find.text('Set start time'));
    await tester.pumpAndSettle(); await tester.enterText(find.byType(TextField), '4.000');
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); await apply(tester);
    expect(applied!.toJson(), song.toJson());
  });
}
