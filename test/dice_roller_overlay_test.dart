import 'dart:math';

import 'package:dnd_sheet_archive/widgets/dice_roller_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the dice menu stays open after a roll and reveals the result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiceRollerOverlay(
            random: Random(1),
            revealDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('dice-button-20')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dice-menu-fab')));
    await tester.pumpAndSettle();

    for (final sides in [4, 6, 8, 10, 12, 20, 100]) {
      expect(find.byKey(ValueKey('dice-button-$sides')), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('dice-button-20')));
    await tester.pump();
    expect(find.byKey(const ValueKey('dice-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-button-20')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('dice-result-value-0')))
          .data,
      '?',
    );

    await tester.pump(const Duration(milliseconds: 110));
    final result = int.parse(
      tester
          .widget<Text>(find.byKey(const ValueKey('dice-result-value-0')))
          .data!,
    );
    expect(result, inInclusiveRange(1, 20));
  });

  testWidgets('multiple rolls use independent 30 second expiry timers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiceRollerOverlay(
            random: Random(2),
            revealDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('dice-menu-fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dice-button-4')));
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.byKey(const ValueKey('dice-button-100')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('dice-roll-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-roll-1')), findsOneWidget);

    await tester.pump(const Duration(seconds: 19, milliseconds: 800));
    expect(find.byKey(const ValueKey('dice-roll-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-roll-1')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('dice-roll-0')), findsNothing);
    expect(find.byKey(const ValueKey('dice-roll-1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('dice-total')), findsNothing);

    await tester.pump(const Duration(seconds: 9, milliseconds: 600));
    expect(find.byKey(const ValueKey('dice-roll-1')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('dice-roll-1')), findsNothing);
  });

  testWidgets('the clear button removes every roll without closing the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiceRollerOverlay(
            random: Random(5),
            revealDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('dice-menu-fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dice-button-4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dice-button-20')));
    await tester.pump();
    expect(find.byKey(const ValueKey('dice-roll-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-roll-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dice-clear-button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('dice-roll-0')), findsNothing);
    expect(find.byKey(const ValueKey('dice-roll-1')), findsNothing);
    expect(find.byKey(const ValueKey('dice-total')), findsNothing);
    expect(find.byKey(const ValueKey('dice-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-button-20')), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the total appears only for multiple revealed rolls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiceRollerOverlay(
            random: Random(6),
            revealDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('dice-menu-fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dice-button-4')));
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.byKey(const ValueKey('dice-total')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dice-button-20')));
    await tester.pump();
    expect(find.byKey(const ValueKey('dice-total')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('dice-total-value'))).data,
      'Totale: …',
    );

    await tester.pump(const Duration(milliseconds: 110));
    final firstResult = int.parse(
      tester
          .widget<Text>(find.byKey(const ValueKey('dice-result-value-0')))
          .data!,
    );
    final secondResult = int.parse(
      tester
          .widget<Text>(find.byKey(const ValueKey('dice-result-value-1')))
          .data!,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('dice-total-value'))).data,
      'Totale: ${firstResult + secondResult}',
    );
  });

  testWidgets('every die result uses a distinct silhouette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiceRollerOverlay(
            random: Random(3),
            revealDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('dice-menu-fab')));
    await tester.pumpAndSettle();

    final signatures = <String>{};
    final silhouettes = <int, Path>{};
    for (var index = 0; index < 7; index++) {
      final sides = [4, 6, 8, 10, 12, 20, 100][index];
      await tester.tap(find.byKey(ValueKey('dice-button-$sides')));
      await tester.pump();

      final shape = tester.widget<PhysicalShape>(
        find.byKey(ValueKey('dice-result-shape-$index')),
      );
      final path = shape.clipper.getClip(const Size.square(90));
      silhouettes[sides] = path;
      final signature = StringBuffer();
      for (var y = 0; y <= 20; y++) {
        for (var x = 0; x <= 20; x++) {
          signature.write(path.contains(Offset(x * 4.5, y * 4.5)) ? '1' : '0');
        }
      }
      signatures.add(signature.toString());
    }

    expect(signatures, hasLength(7));

    final d10 = silhouettes[10]!;
    for (var y = 5.0; y < 90; y += 5) {
      for (var x = 5.0; x < 45; x += 5) {
        expect(
          d10.contains(Offset(x, y)),
          d10.contains(Offset(90 - x, y)),
          reason: 'Il profilo del d10 deve essere simmetrico.',
        );
      }
    }

    final d12Bounds = silhouettes[12]!.getBounds();
    expect(d12Bounds.width / d12Bounds.height, inInclusiveRange(.95, 1.05));
  });
}
