import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Renders artist metadata where individual artist names within multi-artist
/// strings (e.g. "Artist 1, Artist 2 & Artist 3") are independently clickable.
class ClickableArtistText extends StatefulWidget {
  final String artist;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final void Function(String artistName) onArtistTap;

  const ClickableArtistText({
    super.key,
    required this.artist,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    required this.onArtistTap,
  });

  @override
  State<ClickableArtistText> createState() => _ClickableArtistTextState();
}

class _ClickableArtistTextState extends State<ClickableArtistText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();

    final String artistField = widget.artist;
    if (artistField.trim().isEmpty) {
      return Text(
        'Unknown Artist',
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final splitRegex = RegExp(
      r'\s*(?:,|&|/|;|\b(?:and|featuring|x)\b|\b(?:ft|feat|vs)\b\.?)\s*',
      caseSensitive: false,
    );

    final matches = splitRegex.allMatches(artistField).toList();
    if (matches.isEmpty) {
      final trimmed = artistField.trim();
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          HapticFeedback.lightImpact();
          widget.onArtistTap(trimmed);
        };
      _recognizers.add(recognizer);

      return Text.rich(
        TextSpan(
          text: artistField,
          style: widget.style,
          recognizer: recognizer,
        ),
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    void processSegment(String textSegment) {
      if (textSegment.isEmpty) return;
      final trimmed = textSegment.trim();
      if (trimmed.isEmpty) {
        spans.add(TextSpan(text: textSegment, style: widget.style));
        return;
      }

      final firstIndex = textSegment.indexOf(trimmed);
      final prefixSpaces = textSegment.substring(0, firstIndex);
      final suffixSpaces = textSegment.substring(firstIndex + trimmed.length);

      if (prefixSpaces.isNotEmpty) {
        spans.add(TextSpan(text: prefixSpaces, style: widget.style));
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          HapticFeedback.lightImpact();
          widget.onArtistTap(trimmed);
        };
      _recognizers.add(recognizer);

      spans.add(TextSpan(
        text: trimmed,
        style: widget.style,
        recognizer: recognizer,
      ));

      if (suffixSpaces.isNotEmpty) {
        spans.add(TextSpan(text: suffixSpaces, style: widget.style));
      }
    }

    for (final match in matches) {
      final leadingText = artistField.substring(lastEnd, match.start);
      final delimiterText = artistField.substring(match.start, match.end);

      processSegment(leadingText);

      if (delimiterText.isNotEmpty) {
        spans.add(TextSpan(
          text: delimiterText,
          style: widget.style,
        ));
      }

      lastEnd = match.end;
    }

    final trailingText = artistField.substring(lastEnd);
    processSegment(trailingText);

    return Text.rich(
      TextSpan(children: spans),
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
