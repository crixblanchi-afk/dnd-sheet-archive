import 'package:dnd_sheet_archive/theme/sheet_palette.dart';
import 'package:dnd_sheet_archive/widgets/inline_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseStyle = TextStyle(fontFamily: 'RobotoSlab', fontSize: 10);

void main() {
  test('nel tema scuro il grassetto spicca sul testo normale', () {
    final span = buildInlineMarkdownSpan(
      'Testo **importante**',
      TextStyle(color: SheetPalette.dark.text, fontFamily: 'RobotoSlab'),
      boldColor: SheetPalette.dark.bold,
    );

    final spans = span.children!.cast<TextSpan>();
    expect(spans.last.style!.fontWeight, FontWeight.w800);
    expect(spans.last.style!.color, const Color(0xffe5d9c6));
    // Il testo normale non viene ricolorato: eredita lo stile della casella.
    expect(spans.first.style, isNull);
  });

  test('grassetto, corsivo e la combinazione prendono ciascuno il '
      'proprio colore', () {
    const palette = SheetPalette.lightColored;
    Color? colorOf(String source, String text) => _spans(
      buildInlineMarkdownSpan(
        source,
        _baseStyle,
        boldColor: palette.bold,
        italicColor: palette.italic,
        boldItalicColor: palette.boldItalic,
      ),
    ).singleWhere((child) => child.text == text).style?.color;

    expect(colorOf('**g**', 'g'), palette.bold);
    expect(colorOf('*c*', 'c'), palette.italic);
    expect(colorOf('***e***', 'e'), palette.boldItalic);
    expect(colorOf('testo *c*', 'testo '), isNull);
  });

  test('senza colori dedicati il formattato eredita quello della casella', () {
    expect(_styleOf('**g**', 'g').color, isNull);
    expect(_styleOf('*c*', 'c').color, isNull);
    expect(_styleOf('***e***', 'e').color, isNull);
  });

  test('il testo senza delimitatori resta un unico frammento', () {
    final span = buildInlineMarkdownSpan('Solo testo', _baseStyle);

    expect(span.style, _baseStyle);
    expect(span.toPlainText(), 'Solo testo');
    expect(_spans(span).single.style, isNull);
  });

  test('una stringa vuota non produce frammenti', () {
    expect(buildInlineMarkdownSpan('', _baseStyle).toPlainText(), '');
  });

  test('gli asterischi delimitano grassetto, corsivo e la combinazione', () {
    expect(_styleOf('**grassetto**', 'grassetto').fontWeight, FontWeight.bold);
    expect(_styleOf('**grassetto**', 'grassetto').fontStyle, isNull);

    expect(_styleOf('*corsivo*', 'corsivo').fontStyle, FontStyle.italic);
    expect(_styleOf('*corsivo*', 'corsivo').fontWeight, isNull);

    final both = _styleOf('***entrambi***', 'entrambi');
    expect(both.fontWeight, FontWeight.bold);
    expect(both.fontStyle, FontStyle.italic);
  });

  test('i trattini bassi si comportano come gli asterischi', () {
    expect(_styleOf('__grassetto__', 'grassetto').fontWeight, FontWeight.bold);
    expect(_styleOf('_corsivo_', 'corsivo').fontStyle, FontStyle.italic);

    final both = _styleOf('___entrambi___', 'entrambi');
    expect(both.fontWeight, FontWeight.bold);
    expect(both.fontStyle, FontStyle.italic);
  });

  test('il delimitatore più lungo vince su quello più corto', () {
    // `***testo***` non deve essere letto come `**` seguito da `*testo*`.
    final children = _spans(buildInlineMarkdownSpan('***testo***', _baseStyle));

    expect(children.single.text, 'testo');
  });

  test('i frammenti fuori dai delimitatori restano senza stile', () {
    final span = buildInlineMarkdownSpan(
      'Un **colpo** e un *affondo*',
      _baseStyle,
    );

    expect(span.toPlainText(), 'Un colpo e un affondo');
    final children = _spans(span);
    expect(children.map((child) => child.text), [
      'Un ',
      'colpo',
      ' e un ',
      'affondo',
    ]);
    expect(children[0].style, isNull);
    expect(children[2].style, isNull);
  });

  test('un delimitatore mai chiuso resta visibile', () {
    for (final source in ['**aperto', 'testo *sospeso', '__ancora']) {
      expect(
        buildInlineMarkdownSpan(source, _baseStyle).toPlainText(),
        source,
        reason: source,
      );
    }
  });

  test('i delimitatori senza contenuto restano visibili', () {
    for (final source in ['****', '**', '*', '____']) {
      expect(
        buildInlineMarkdownSpan(source, _baseStyle).toPlainText(),
        source,
        reason: source,
      );
    }
  });

  test('più formattazioni consecutive vengono riconosciute tutte', () {
    final children = _spans(
      buildInlineMarkdownSpan('**a***b*', _baseStyle),
    ).where((child) => child.style != null);

    expect(children.map((child) => child.text), ['a', 'b']);
  });
}

TextStyle _styleOf(String source, String text) => _spans(
  buildInlineMarkdownSpan(source, _baseStyle),
).singleWhere((child) => child.text == text).style!;

List<TextSpan> _spans(TextSpan root) {
  final result = <TextSpan>[];

  void collect(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text != null) result.add(span);
    for (final child in span.children ?? const <InlineSpan>[]) {
      collect(child);
    }
  }

  collect(root);
  return result;
}
