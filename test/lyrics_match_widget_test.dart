import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/domain/models/search_result.dart';
import 'package:gru_songs/presentation/widgets/lyrics_match_widget.dart';

void main() {
  group('LyricsMatchWidget', () {
    testWidgets('displays lyrics match widget', (tester) async {
      const lyricsMatch = LyricsMatch(
        matchedText: 'let you',
        fullLine: 'Never gonna let you down',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LyricsMatchWidget(
              lyricsMatch: lyricsMatch,
              searchQuery: 'let you',
            ),
          ),
        ),
      );

      // Verify the widget displays
      expect(find.byType(LyricsMatchWidget), findsOneWidget);
      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
    });

    testWidgets('handles empty query gracefully', (tester) async {
      const lyricsMatch = LyricsMatch(
        matchedText: '',
        fullLine: 'Some lyrics line',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LyricsMatchWidget(
              lyricsMatch: lyricsMatch,
              searchQuery: '',
            ),
          ),
        ),
      );

      expect(find.byType(LyricsMatchWidget), findsOneWidget);
    });

    testWidgets('handles case insensitive match', (tester) async {
      const lyricsMatch = LyricsMatch(
        matchedText: 'LET YOU',
        fullLine: 'Never gonna LET YOU down',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LyricsMatchWidget(
              lyricsMatch: lyricsMatch,
              searchQuery: 'let you',
            ),
          ),
        ),
      );

      expect(find.byType(LyricsMatchWidget), findsOneWidget);
    });
  });

  group('CompactLyricsMatchWidget', () {
    testWidgets('displays compact lyrics match', (tester) async {
      const lyricsMatch = LyricsMatch(
        matchedText: 'hello',
        fullLine: 'Hello world this is a test',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactLyricsMatchWidget(
              lyricsMatch: lyricsMatch,
              searchQuery: 'hello',
            ),
          ),
        ),
      );

      expect(find.byType(CompactLyricsMatchWidget), findsOneWidget);
      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
    });

    testWidgets('truncates long lines', (tester) async {
      const lyricsMatch = LyricsMatch(
        matchedText: 'middle',
        fullLine:
            'This is a very long line that should be truncated in the middle of the text',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactLyricsMatchWidget(
              lyricsMatch: lyricsMatch,
              searchQuery: 'middle',
            ),
          ),
        ),
      );

      expect(find.byType(CompactLyricsMatchWidget), findsOneWidget);
    });
  });

  group('LyricsAvailableIndicator', () {
    testWidgets('displays lyrics icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LyricsAvailableIndicator(),
          ),
        ),
      );

      expect(find.byType(LyricsAvailableIndicator), findsOneWidget);
      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
    });
  });
}
