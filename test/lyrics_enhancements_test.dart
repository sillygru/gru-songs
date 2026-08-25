import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/models/rich_lyrics.dart';
import 'package:wispie/presentation/widgets/lyrics_line.dart';
import 'package:wispie/presentation/widgets/lyrics_resume_button.dart';

void main() {
  group('LyricsVoiceAlignment detection', () {
    test('detects lead voice for standard lines', () {
      expect(
        LyricsLine.detectAlignment('Hello world'),
        LyricsVoiceAlignment.lead,
      );
      expect(
        LyricsLine.detectAlignment('Never gonna give you up'),
        LyricsVoiceAlignment.lead,
      );
    });

    test('detects backing voice for bracketed and parenthesized lines', () {
      expect(
        LyricsLine.detectAlignment('(ooh yeah)'),
        LyricsVoiceAlignment.backing,
      );
      expect(
        LyricsLine.detectAlignment('[backing vocals]'),
        LyricsVoiceAlignment.backing,
      );
    });

    test('detects duet voice for multi-singer annotations', () {
      expect(
        LyricsLine.detectAlignment('(Both) Sing together'),
        LyricsVoiceAlignment.duet,
      );
      expect(
        LyricsLine.detectAlignment('[All] Harmonize'),
        LyricsVoiceAlignment.duet,
      );
    });
  });

  group('LyricsResumeButton widget', () {
    testWidgets('renders when visible and responds to tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsResumeButton(
              visible: true,
              accent: Colors.deepPurple,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Resume Sync'), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

      await tester.tap(find.text('Resume Sync'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('ignores pointer when hidden', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsResumeButton(
              visible: false,
              accent: Colors.deepPurple,
              onTap: () {},
            ),
          ),
        ),
      );

      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(LyricsResumeButton),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);
    });
  });

  group('LyricsLine widget', () {
    testWidgets('renders lead and backing lines with appropriate layout',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LyricsLine(
                  text: 'Lead lyric line',
                  isActive: true,
                  isPlayed: true,
                  blurSigma: 0,
                  hasTime: true,
                  activeColor: Colors.amber,
                  glowIntensity: 1.0,
                ),
                LyricsLine(
                  text: '(Backing vocal line)',
                  isActive: false,
                  isPlayed: false,
                  blurSigma: 0.5,
                  hasTime: true,
                  activeColor: Colors.amber,
                  glowIntensity: 0.0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Lead lyric line'), findsOneWidget);
      expect(find.text('(Backing vocal line)'), findsOneWidget);
    });

    testWidgets('renders rich sync word spans without error', (tester) async {
      const wordLine = RichLyricLine(
        start: Duration(seconds: 1),
        end: Duration(seconds: 4),
        text: 'Singing in the rain',
        words: [
          RichLyricWord(
            start: Duration(seconds: 1),
            end: Duration(seconds: 2),
            text: 'Singing',
          ),
          RichLyricWord(
            start: Duration(seconds: 2),
            end: Duration(milliseconds: 2500),
            text: 'in',
          ),
          RichLyricWord(
            start: Duration(milliseconds: 2500),
            end: Duration(milliseconds: 3000),
            text: 'the',
          ),
          RichLyricWord(
            start: Duration(milliseconds: 3000),
            end: Duration(seconds: 4),
            text: 'rain',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LyricsLine(
              text: 'Singing in the rain',
              isActive: true,
              isPlayed: true,
              blurSigma: 0,
              hasTime: true,
              activeColor: Colors.cyan,
              glowIntensity: 1.0,
              playbackPosition: Duration(milliseconds: 1500),
              wordLine: wordLine,
            ),
          ),
        ),
      );

      expect(find.byType(LyricsLine), findsOneWidget);
    });
  });
}
