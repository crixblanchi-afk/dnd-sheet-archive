import 'package:dnd_sheet_archive/controllers/sheet_controller.dart';
import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/widgets/text_field_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses a lightweight value until the field is edited', (
    tester,
  ) async {
    final character = Character(
      id: 'character',
      name: 'Character',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      locked: false,
    );
    final controller = SheetController(
      repository: _FakeRepository(),
      character: character,
    );
    const field = SheetFieldDef(
      name: 'Name',
      page: 0,
      type: SheetFieldType.text,
      x: 0,
      y: 0,
      width: 180,
      height: 30,
      multiline: false,
      align: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: field.width,
              height: field.height,
              child: TextFieldOverlay(
                field: field,
                sheetController: controller,
                onFocused: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);

    await tester.tapAt(const Offset(30, 15));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).style?.fontFamily,
      'RobotoSlab',
    );

    await tester.enterText(find.byType(TextField), 'Arannis');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Arannis', findRichText: true), findsOneWidget);
    expect(
      tester
          .widget<RichText>(find.text('Arannis', findRichText: true))
          .text
          .style
          ?.fontFamily,
      'RobotoSlab',
    );
    expect(character.fields['Name'], 'Arannis');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shrinks single-line text to remain inside the field', (
    tester,
  ) async {
    const value = 'A very long character name with many titles';
    final fixture = _Fixture(
      field: const SheetFieldDef(
        name: 'Name',
        page: 0,
        type: SheetFieldType.text,
        x: 0,
        y: 0,
        width: 70,
        height: 20,
        multiline: false,
        align: 0,
      ),
      value: value,
    );

    await tester.pumpWidget(fixture.widget);

    final richText = tester.widget<RichText>(find.byType(RichText).last);
    final idleStyle = richText.text.style!;
    expect(idleStyle.fontSize, lessThan(4));
    expect(
      _singleLineSpanWidth(richText.text),
      lessThanOrEqualTo(68.01),
      reason: 'font size: ${idleStyle.fontSize}',
    );

    await tester.tapAt(const Offset(30, 10));
    await tester.pump();
    final editingStyle = tester
        .widget<TextField>(find.byType(TextField))
        .style!;
    expect(editingStyle.fontSize, closeTo(idleStyle.fontSize!, .02));
    expect(_singleLineWidth(value, editingStyle), lessThanOrEqualTo(68.01));

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });

  testWidgets('shrinks multiline text to remain inside the field', (
    tester,
  ) async {
    const value =
        'Long traits and abilities must stay within this short multiline '
        'field while the complete value remains visible.';
    final fixture = _Fixture(
      field: const SheetFieldDef(
        name: 'Traits',
        page: 0,
        type: SheetFieldType.text,
        x: 0,
        y: 0,
        width: 110,
        height: 30,
        multiline: true,
        align: 0,
      ),
      value: value,
    );

    await tester.pumpWidget(fixture.widget);

    final richText = tester.widget<RichText>(find.byType(RichText).last);
    final style = richText.text.style!;
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 108);
    expect(style.fontSize, lessThan(9.5));
    expect(style.fontSize, greaterThan(1));
    expect(painter.computeLineMetrics().length, greaterThan(1));
    expect(painter.width, lessThanOrEqualTo(108.01));
    expect(
      painter.height,
      lessThanOrEqualTo(30.01),
      reason: 'font size: ${style.fontSize}',
    );

    await tester.tapAt(const Offset(30, 10));
    await tester.pump();
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.maxLines, isNull);
    expect(textField.expands, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });

  testWidgets('does not shrink multiline text before wrapped lines fill it', (
    tester,
  ) async {
    const value = 'One two three four five six seven eight nine ten';
    const baseStyle = TextStyle(
      fontFamily: 'RobotoSlab',
      fontSize: 9.5,
      height: 1,
    );
    final basePainter = TextPainter(
      text: const TextSpan(text: value, style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 108);
    final fixture = _Fixture(
      field: SheetFieldDef(
        name: 'Traits',
        page: 0,
        type: SheetFieldType.text,
        x: 0,
        y: 0,
        width: 110,
        height: basePainter.height + .5,
        multiline: true,
        align: 0,
      ),
      value: value,
    );

    await tester.pumpWidget(fixture.widget);

    final richText = tester.widget<RichText>(find.byType(RichText).last);
    expect(richText.text.style?.fontSize, 9.5);
    final renderedPainter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 108);
    expect(renderedPainter.computeLineMetrics().length, greaterThan(1));
    expect(
      renderedPainter.height,
      lessThanOrEqualTo(fixture.field.height + .01),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });

  testWidgets('a touch on the empty sheet ends text editing', (tester) async {
    final fixture = _Fixture(
      field: const SheetFieldDef(
        name: 'Name',
        page: 0,
        type: SheetFieldType.text,
        x: 0,
        y: 0,
        width: 180,
        height: 30,
        multiline: false,
        align: 0,
      ),
      value: 'Arannis',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveViewer(
            boundaryMargin: const EdgeInsets.all(100),
            child: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.white)),
                  SizedBox(
                    width: fixture.field.width,
                    height: fixture.field.height,
                    child: TextFieldOverlay(
                      field: fixture.field,
                      sheetController: fixture.controller,
                      onFocused: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(30, 15));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    final insideGesture = await tester.startGesture(const Offset(40, 15));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await insideGesture.up();

    final panGesture = await tester.startGesture(const Offset(300, 300));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await panGesture.moveBy(const Offset(20, 10));
    await panGesture.up();

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });
  testWidgets('renders inline bold and italic Markdown', (tester) async {
    final fixture = _Fixture(
      field: const SheetFieldDef(
        name: 'Traits',
        page: 0,
        type: SheetFieldType.text,
        x: 0,
        y: 0,
        width: 300,
        height: 40,
        multiline: true,
        align: 0,
      ),
      value: 'A **bold** and *italic* trait',
    );

    await tester.pumpWidget(fixture.widget);

    final span =
        tester.widget<RichText>(find.byType(RichText).last).text as TextSpan;
    expect(span.toPlainText(), 'A bold and italic trait');
    final children = _descendantTextSpans(span);
    expect(
      children.singleWhere((child) => child.text == 'bold').style?.fontWeight,
      FontWeight.bold,
    );
    expect(
      children.singleWhere((child) => child.text == 'italic').style?.fontStyle,
      FontStyle.italic,
    );

    await tester.tapAt(const Offset(30, 20));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('A **bold** and *italic* trait'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });
}

double _singleLineWidth(String value, TextStyle style) =>
    _singleLineSpanWidth(TextSpan(text: value, style: style));

double _singleLineSpanWidth(InlineSpan span) {
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  return painter.width;
}

List<TextSpan> _descendantTextSpans(TextSpan root) {
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

class _Fixture {
  _Fixture({required this.field, required String value}) {
    character = Character(
      id: 'character',
      name: 'Character',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      locked: false,
      fields: {field.name: value},
    );
    controller = SheetController(
      repository: _FakeRepository(),
      character: character,
    );
  }

  final SheetFieldDef field;
  late final Character character;
  late final SheetController controller;

  Widget get widget => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: field.width,
          height: field.height,
          child: TextFieldOverlay(
            field: field,
            sheetController: controller,
            onFocused: (_) {},
          ),
        ),
      ),
    ),
  );
}

class _FakeRepository implements CharacterRepository {
  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
