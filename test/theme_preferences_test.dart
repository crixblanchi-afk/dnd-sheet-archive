import 'package:dnd_sheet_archive/theme/theme_preferences.dart';
import 'package:dnd_sheet_archive/widgets/theme_mode_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('theme preference persists locally, including rapid changes', () async {
    final database = await databaseFactoryMemory.openDatabase('theme.db');
    addTearDown(database.close);
    final preferences = await ThemePreferences.open(database);
    addTearDown(preferences.dispose);
    expect(preferences.mode, ThemeMode.system);
    await Future.wait([
      preferences.setMode(ThemeMode.light),
      preferences.setMode(ThemeMode.dark),
    ]);
    final restored = await ThemePreferences.open(database);
    addTearDown(restored.dispose);
    expect(restored.mode, ThemeMode.dark);
    await preferences.setMode(ThemeMode.system);
    final automatic = await ThemePreferences.open(database);
    addTearDown(automatic.dispose);
    expect(automatic.mode, ThemeMode.system);
  });

  testWidgets('appearance menu selects and checks each theme', (tester) async {
    final preferences = ThemePreferences.inMemory();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ThemePreferenceScope(
          preferences: preferences,
          child: const Scaffold(body: ThemeModeButton()),
        ),
      ),
    );
    for (final entry in {
      'Scuro': ThemeMode.dark,
      'Chiaro': ThemeMode.light,
      'Sistema': ThemeMode.system,
    }.entries) {
      await tester.tap(find.byTooltip('Aspetto'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, entry.key),
      );
      await tester.pumpAndSettle();
      expect(preferences.mode, entry.value);
      await tester.tap(find.byTooltip('Aspetto'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<ThemeMode>>(
              find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, entry.key),
            )
            .checked,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });
}
