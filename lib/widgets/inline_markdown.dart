import 'package:flutter/material.dart';

/// Parses the small Markdown subset supported by character-sheet fields.
///
/// Supported delimiters are `**bold**`, `*italic*`, and `***bold italic***`
/// (with the equivalent underscore forms). Unclosed delimiters remain visible.
TextSpan buildInlineMarkdownSpan(String source, TextStyle baseStyle) {
  final children = <InlineSpan>[];
  var cursor = 0;

  while (cursor < source.length) {
    final match = _nextMarkdownMatch(source, cursor);
    if (match == null) {
      children.add(TextSpan(text: source.substring(cursor)));
      break;
    }

    if (match.start > cursor) {
      children.add(TextSpan(text: source.substring(cursor, match.start)));
    }
    children.add(
      TextSpan(
        text: match.text,
        style: TextStyle(
          fontWeight: match.bold ? FontWeight.bold : null,
          fontStyle: match.italic ? FontStyle.italic : null,
        ),
      ),
    );
    cursor = match.end;
  }

  return TextSpan(style: baseStyle, children: children);
}

_MarkdownMatch? _nextMarkdownMatch(String source, int start) {
  _MarkdownMatch? best;
  for (final delimiter in const ['***', '___', '**', '__', '*', '_']) {
    var opening = source.indexOf(delimiter, start);
    while (opening >= 0) {
      final contentStart = opening + delimiter.length;
      final closing = source.indexOf(delimiter, contentStart);
      if (closing > contentStart) {
        final candidate = _MarkdownMatch(
          start: opening,
          end: closing + delimiter.length,
          text: source.substring(contentStart, closing),
          bold: delimiter.length >= 2,
          italic: delimiter.length.isOdd,
        );
        // Delimiters are checked longest-first, so keeping the first match at
        // the same position makes *** win over ** and *.
        if (best == null || candidate.start < best.start) {
          best = candidate;
        }
        break;
      }
      opening = source.indexOf(delimiter, contentStart);
    }
  }
  return best;
}

class _MarkdownMatch {
  const _MarkdownMatch({
    required this.start,
    required this.end,
    required this.text,
    required this.bold,
    required this.italic,
  });

  final int start;
  final int end;
  final String text;
  final bool bold;
  final bool italic;
}
