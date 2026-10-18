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
    expect(preferences.theme, AppTheme.system);
    await Future.wait([
      preferences.setTheme(AppTheme.light),
      preferences.setTheme(AppTheme.darkColored),
    ]);
    final restored = await ThemePreferences.open(database);
    addTearDown(restored.dispose);
    expect(restored.theme, AppTheme.darkColored);
    expect(restored.mode, ThemeMode.dark);
    await preferences.setTheme(AppTheme.system);
    final automatic = await ThemePreferences.open(database);
    addTearDown(automatic.dispose);
    expect(automatic.theme, AppTheme.system);
  });

  test('i temi salvati prima dei colorati vengono riletti', () async {
    final database = await databaseFactoryMemory.openDatabase('legacy.db');
    addTearDown(database.close);
    final store = StoreRef<String, String>('app_preferences');
    for (final entry in {
      'light': AppTheme.light,
      'dark': AppTheme.dark,
      'system': AppTheme.system,
      'sconosciuto': AppTheme.system,
    }.entries) {
      await store.record('theme_mode').put(database, entry.key);
      final preferences = await ThemePreferences.open(database);
      addTearDown(preferences.dispose);
      expect(preferences.theme, entry.value, reason: entry.key);
    }
  });

  testWidgets('appearance menu lists, selects and checks each theme', (
    tester,
  ) async {
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
    await tester.tap(find.byTooltip('Aspetto'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CheckedPopupMenuItem<AppTheme>>(
            find.byType(CheckedPopupMenuItem<AppTheme>),
          )
          .map((item) => item.value),
      AppTheme.values,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    for (final theme in AppTheme.values.reversed) {
      await tester.tap(find.byTooltip('Aspetto'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<AppTheme>, theme.label),
      );
      await tester.pumpAndSettle();
      expect(preferences.theme, theme);
      await tester.tap(find.byTooltip('Aspetto'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<AppTheme>>(
              find.widgetWithText(CheckedPopupMenuItem<AppTheme>, theme.label),
            )
            .checked,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });
}
