import 'package:dnd_sheet_archive/controllers/sheet_controller.dart';
import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/models/sheet_layout.dart';
import 'package:dnd_sheet_archive/widgets/scrollable_sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _field = SheetFieldDef(
  name: 'TestField',
  page: 0,
  type: SheetFieldType.text,
  x: 100,
  y: 500,
  width: 160,
  height: 30,
  multiline: false,
  align: 0,
);

void main() {
  late SheetController controller;

  setUp(() {
    controller = SheetController(
      repository: _Repository(),
      character: Character(
        id: 'character',
        name: 'Character',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        locked: false,
      ),
    );
  });

  tearDown(() => controller.dispose());

  Future<TransformationController> openView(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(612, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollableSheetView(
            controller: controller,
            fields: const [
              [_field],
              [],
              [],
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
  }

  for (final scale in [.5, 2.0]) {
    testWidgets('keyboard reveal moves the field by screen pixels at $scale', (
      tester,
    ) async {
      final transform = await openView(tester);
      transform.value = Matrix4.identity()
        ..translateByDouble(
          sheetCenterOffset(612, sheetPageWidth * scale),
          250 - _field.y * scale,
          0,
          1,
        )
        // Uniforme su tutti gli assi, come fa `InteractiveViewer`.
        ..scaleByDouble(scale, scale, scale, 1);
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('TestField'))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      tester.view.viewInsets = FakeViewPadding(
        bottom: 600 * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      final fieldRect = tester.getRect(find.byType(TextField));
      expect(fieldRect.bottom, closeTo(800 - 600 - 16, .01));
      expect(fieldRect.top, greaterThanOrEqualTo(0));
      expect(transform.value.storage[0], closeTo(scale, .001));
      expect(transform.value.storage[5], closeTo(scale, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('sotto il 100% lo zoom resta leggibile su tutti gli assi', (
    tester,
  ) async {
    final transform = await openView(tester);

    await tester.tap(find.byTooltip('Riduci zoom'));
    await tester.pumpAndSettle();

    final scale = transform.value.storage[0];
    expect(scale, lessThan(1));
    // `getMaxScaleOnAxis()` prende il massimo dei tre assi: lasciando Z a 1,
    // ogni zoom sotto il 100% veniva letto come 100% da InteractiveViewer,
    // dalle scrollbar e dal vincolo orizzontale.
    expect(transform.value.getMaxScaleOnAxis(), closeTo(scale, .000001));
    expect(find.text('${(scale * 100).round()}%'), findsOneWidget);

    // Più stretta del viewport, la scheda resta centrata: con la scala letta
    // male finiva appoggiata al bordo sinistro e il trascinamento orizzontale
    // le si opponeva.
    final centered = sheetCenterOffset(612, sheetPageWidth * scale);
    expect(transform.value.storage[12], closeTo(centered, .01));
    await tester.dragFrom(const Offset(306, 400), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(transform.value.storage[12], closeTo(centered, .01));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('metric changes do not reveal a field after focus is lost', (
    tester,
  ) async {
    final transform = await openView(tester);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('TestField'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    transform.value = transform.value.clone()..storage[13] = 100;
    tester.view.viewInsets = FakeViewPadding(
      bottom: 400 * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();
    expect(transform.value.storage[13], closeTo(100, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Repository extends CharacterRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
