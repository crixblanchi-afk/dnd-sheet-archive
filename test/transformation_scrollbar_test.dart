import 'package:dnd_sheet_archive/widgets/transformation_scrollbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('una scheda più stretta della finestra resta centrata', (
    tester,
  ) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 200,
            child: TransformationWheelScroller(
              controller: controller,
              viewportSize: const Size(400, 200),
              contentSize: const Size(300, 600),
              child: const SizedBox(width: 300, height: 600),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(controller.value.storage[12], closeTo(50, .01));

    // È quello che fa `InteractiveViewer` a ogni interazione quando il suo
    // boundaryMargin è più stretto del viewport: riappoggia tutto a sinistra.
    controller.value = Matrix4.identity();
    await tester.pump();

    expect(controller.value.storage[12], closeTo(50, .01));

    // Anche uno scorrimento orizzontale non deve staccarla dal centro.
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(60, 0),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.value.storage[12], closeTo(50, .01));
    controller.dispose();
  });

  testWidgets('il centraggio segue il ridimensionamento della finestra', (
    tester,
  ) async {
    final controller = TransformationController();

    Widget build(double viewportWidth) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: viewportWidth,
          height: 200,
          child: TransformationWheelScroller(
            controller: controller,
            viewportSize: Size(viewportWidth, 200),
            contentSize: const Size(300, 600),
            child: const SizedBox(width: 300, height: 600),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(400));
    await tester.pump();
    expect(controller.value.storage[12], closeTo(50, .01));

    await tester.pumpWidget(build(700));
    await tester.pump();
    expect(controller.value.storage[12], closeTo(200, .01));

    // Tornando più stretta della scheda il centraggio non si applica più e
    // la scheda resta scorrevole dal bordo sinistro.
    await tester.pumpWidget(build(200));
    await tester.pump();
    expect(controller.value.storage[12], closeTo(0, .01));

    controller.dispose();
  });

  testWidgets('horizontal scrollbar drag pans the transformation', (
    tester,
  ) async {
    final controller = TransformationController(
      Matrix4.diagonal3Values(2, 2, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 12,
              child: TransformationScrollbar(
                axis: Axis.horizontal,
                controller: controller,
                viewportExtent: 200,
                contentExtent: 300,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(TransformationScrollbar),
      const Offset(50, 0),
    );
    await tester.pump();

    expect(controller.value.storage[12], lessThan(-50));
    controller.dispose();
  });

  testWidgets('vertical scrollbar track click jumps the transformation', (
    tester,
  ) async {
    final controller = TransformationController(
      Matrix4.diagonal3Values(2, 2, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 12,
              height: 200,
              child: TransformationScrollbar(
                axis: Axis.vertical,
                controller: controller,
                viewportExtent: 200,
                contentExtent: 300,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(6, 150));
    await tester.pump();

    expect(controller.value.storage[13], lessThan(-300));
    controller.dispose();
  });

  testWidgets('thumb follows the pointer without drag slop', (tester) async {
    final controller = TransformationController(
      Matrix4.diagonal3Values(2, 2, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 12,
              child: TransformationScrollbar(
                axis: Axis.horizontal,
                controller: controller,
                viewportExtent: 200,
                contentExtent: 300,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(20, 6));
    await gesture.moveTo(const Offset(70, 6));
    await gesture.up();
    await tester.pump();

    expect(controller.value.storage[12], closeTo(-150, .01));
    controller.dispose();
  });

  testWidgets('mouse wheel pans without changing zoom', (tester) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: TransformationWheelScroller(
              controller: controller,
              viewportSize: const Size(200, 200),
              contentSize: const Size(300, 600),
              child: InteractiveViewer(
                transformationController: controller,
                constrained: false,
                scaleFactor: double.infinity,
                child: const SizedBox(width: 300, height: 600),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, 80),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    expect(controller.value.storage[13], inExclusiveRange(-80, 0));
    expect(controller.value.getMaxScaleOnAxis(), 1);
    await tester.pumpAndSettle();
    expect(controller.value.storage[13], closeTo(-80, .01));
    controller.dispose();
  });

  testWidgets('mouse wheel accumulates deltas while interpolation is active', (
    tester,
  ) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: TransformationWheelScroller(
              controller: controller,
              viewportSize: const Size(200, 200),
              contentSize: const Size(300, 600),
              child: const SizedBox(width: 300, height: 600),
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 2; i++) {
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(100, 100),
          scrollDelta: Offset(0, 80),
          kind: PointerDeviceKind.mouse,
        ),
      );
    }
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.value.storage[13], closeTo(-160, .01));
    controller.dispose();
  });

  testWidgets('control plus mouse wheel zooms around the pointer', (
    tester,
  ) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: TransformationWheelScroller(
              controller: controller,
              viewportSize: const Size(200, 200),
              contentSize: const Size(300, 600),
              child: const SizedBox(width: 300, height: 600),
            ),
          ),
        ),
      ),
    );

    const pointer = Offset(80, 120);
    final scenePointBefore = controller.toScene(pointer);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: pointer,
        scrollDelta: Offset(0, -80),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(controller.toScene(pointer).dx, closeTo(scenePointBefore.dx, .01));
    expect(controller.toScene(pointer).dy, closeTo(scenePointBefore.dy, .01));
    controller.dispose();
  });
}
