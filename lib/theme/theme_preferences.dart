import 'package:flutter/material.dart';
import 'package:sembast/sembast.dart';

/// Preferenza locale: non fa parte delle schede o dei backup su Drive.
class ThemePreferences extends ChangeNotifier {
  ThemePreferences.inMemory({ThemeMode mode = ThemeMode.system})
    : _database = null,
      _mode = mode;

  ThemePreferences._(this._database, this._mode);

  static final _store = StoreRef<String, String>('app_preferences');
  final Database? _database;
  ThemeMode _mode;
  Future<void> _writeTail = Future<void>.value();

  ThemeMode get mode => _mode;

  static Future<ThemePreferences> open(Database database) async {
    final saved = await _store.record('theme_mode').get(database);
    final mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ThemePreferences._(database, mode);
  }

  Future<void> setMode(ThemeMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    final database = _database;
    if (database == null) return Future<void>.value();
    // Scritture in ordine anche con cambi rapidi; un errore non blocca i
    // tentativi successivi e viene comunicato al selettore del tema.
    _writeTail = _writeTail.then<void>(
      (_) async {
        await _store.record('theme_mode').put(database, mode.name);
      },
      onError: (Object _, StackTrace _) async {
        await _store.record('theme_mode').put(database, mode.name);
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
