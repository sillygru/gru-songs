import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/widgets/clickable_artist_text.dart';

void main() {
  testWidgets(
      'ClickableArtistText renders multi-artist string and attaches tap recognizers for each artist',
      (WidgetTester tester) async {
    final tappedArtists = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClickableArtistText(
            artist: 'Artist 1, Artist 2 & Artist 3',
            style: const TextStyle(fontSize: 14),
            onArtistTap: (artistName) {
              tappedArtists.add(artistName);
            },
          ),
        ),
      ),
    );

    expect(find.byType(ClickableArtistText), findsOneWidget);

    final richTextFinder = find.descendant(
      of: find.byType(ClickableArtistText),
      matching: find.byType(RichText),
    );
    final richTextWidget = tester.widget<RichText>(richTextFinder);
    final rootSpan = richTextWidget.text as TextSpan;
    // Text.rich wraps the root span inside rootSpan.children[0]
    final innerSpan = rootSpan.children != null && rootSpan.children!.isNotEmpty
        ? (rootSpan.children!.first as TextSpan)
        : rootSpan;

    final children = innerSpan.children!;

    // Expect 5 spans: Artist 1, ", ", Artist 2, " & ", Artist 3
    expect(children.length, equals(5));

    final artist1Span = children[0] as TextSpan;
    expect(artist1Span.text, equals('Artist 1'));
    expect(artist1Span.recognizer, isA<TapGestureRecognizer>());
    (artist1Span.recognizer as TapGestureRecognizer).onTap?.call();

    final commaSpan = children[1] as TextSpan;
    expect(commaSpan.text, equals(', '));
    expect(commaSpan.recognizer, isNull);

    final artist2Span = children[2] as TextSpan;
    expect(artist2Span.text, equals('Artist 2'));
    expect(artist2Span.recognizer, isA<TapGestureRecognizer>());
    (artist2Span.recognizer as TapGestureRecognizer).onTap?.call();

    final ampSpan = children[3] as TextSpan;
    expect(ampSpan.text, equals(' & '));
    expect(ampSpan.recognizer, isNull);

    final artist3Span = children[4] as TextSpan;
    expect(artist3Span.text, equals('Artist 3'));
    expect(artist3Span.recognizer, isA<TapGestureRecognizer>());
    (artist3Span.recognizer as TapGestureRecognizer).onTap?.call();

    expect(tappedArtists, equals(['Artist 1', 'Artist 2', 'Artist 3']));
  });

  testWidgets('ClickableArtistText handles single artist tap',
      (WidgetTester tester) async {
    final tappedArtists = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClickableArtistText(
            artist: 'Single Artist',
            style: const TextStyle(fontSize: 14),
            onArtistTap: (artistName) {
              tappedArtists.add(artistName);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Single Artist'));
    await tester.pumpAndSettle();

    expect(tappedArtists, equals(['Single Artist']));
  });
}
