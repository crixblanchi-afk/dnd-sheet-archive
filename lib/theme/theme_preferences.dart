import 'package:flutter/material.dart';
import 'package:sembast/sembast.dart';

/// I temi fra cui si sceglie, nell'ordine in cui il menù li elenca.
///
/// Le varianti colorate cambiano solo grassetto e corsivo della scheda: carta,
/// inchiostro e controlli restano quelli del tema chiaro o scuro.
enum AppTheme {
  light('Chiaro', ThemeMode.light),
  dark('Scuro', ThemeMode.dark),
  lightColored('Chiaro colorato', ThemeMode.light, colored: true),
  darkColored('Scuro colorato', ThemeMode.dark, colored: true),
  system('Sistema', ThemeMode.system);

  const AppTheme(this.label, this.mode, {this.colored = false});

  final String label;
  final ThemeMode mode;
  final bool colored;
}

/// Preferenza locale: non fa parte delle schede o dei backup su Drive.
class ThemePreferences extends ChangeNotifier {
  ThemePreferences.inMemory({AppTheme theme = AppTheme.system})
    : _database = null,
      _theme = theme;

  ThemePreferences._(this._database, this._theme);

  static final _store = StoreRef<String, String>('app_preferences');
  final Database? _database;
  AppTheme _theme;
  Future<void> _writeTail = Future<void>.value();

  AppTheme get theme => _theme;
  ThemeMode get mode => _theme.mode;

  static Future<ThemePreferences> open(Database database) async {
    final saved = await _store.record('theme_mode').get(database);
    // I nomi salvati prima dei temi colorati — light, dark, system — sono
    // gli stessi delle voci corrispondenti.
    final theme = AppTheme.values.firstWhere(
      (theme) => theme.name == saved,
      orElse: () => AppTheme.system,
    );
    return ThemePreferences._(database, theme);
  }

  Future<void> setTheme(AppTheme theme) {
    if (_theme != theme) {
      _theme = theme;
      notifyListeners();
    }
    final database = _database;
    if (database == null) return Future<void>.value();
    // Scritture in ordine anche con cambi rapidi; un errore non blocca i
    // tentativi successivi e viene comunicato al selettore del tema.
    _writeTail = _writeTail.then<void>(
      (_) async {
        await _store.record('theme_mode').put(database, theme.name);
      },
      onError: (Object _, StackTrace _) async {
        await _store.record('theme_mode').put(database, theme.name);
      },
    );
    return _writeTail;
  }
}

class ThemePreferenceScope extends InheritedNotifier<ThemePreferences> {
  const ThemePreferenceScope({
    super.key,
    required ThemePreferences preferences,
    required super.child,
  }) : super(notifier: preferences);

  static ThemePreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemePreferenceScope>()
      ?.notifier;
}
