import 'package:dnd_sheet_archive/widgets/about_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la finestra Informazioni attribuisce la scheda a WotC', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [AboutButton()])),
      ),
    );

    await tester.tap(find.byTooltip('Informazioni'));
    await tester.pumpAndSettle();

    expect(find.text('Sheet Archive 5e'), findsOneWidget);
    expect(find.textContaining(sheetCopyrightNotice), findsOneWidget);
    expect(find.textContaining('non è affiliata'), findsOneWidget);
  });

  test('le licenze includono la scheda e Roboto Slab', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerThirdPartyLicenses();

    final packages = {
      await for (final entry in LicenseRegistry.licenses) ...entry.packages,
    };

    expect(packages, contains('Scheda del personaggio D&D 5e'));
    expect(packages, contains('Roboto Slab'));
  });
}
