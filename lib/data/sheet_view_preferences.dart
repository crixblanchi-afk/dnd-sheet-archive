import 'package:flutter/widgets.dart';
import 'package:sembast/sembast.dart';

/// Le modalità di visualizzazione della scheda, nell'ordine del menù.
enum SheetViewMode {
  pages('A pagine'),
  scroll('A scorrimento'),
  vertical('Verticale');

  const SheetViewMode(this.label);

  final String label;
}

/// Preferenza locale: non fa parte delle schede o dei backup su Drive.
class SheetViewPreferences extends ChangeNotifier {
  SheetViewPreferences.inMemory({SheetViewMode mode = SheetViewMode.pages})
    : _database = null,
      _mode = mode;

  SheetViewPreferences._(this._database, this._mode);

  static final _store = StoreRef<String, String>('app_preferences');
  static const _recordKey = 'sheet_view_mode';

  final Database? _database;
  SheetViewMode _mode;
  Future<void> _writeTail = Future<void>.value();

  SheetViewMode get mode => _mode;

  static Future<SheetViewPreferences> open(Database database) async {
    final saved = await _store.record(_recordKey).get(database);
    final mode = SheetViewMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => SheetViewMode.pages,
    );
    return SheetViewPreferences._(database, mode);
  }

  Future<void> setMode(SheetViewMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    final database = _database;
    if (database == null) return Future<void>.value();
    // Scritture in ordine anche con cambi rapidi; un errore non blocca i
    // tentativi successivi e viene comunicato al selettore.
    _writeTail = _writeTail.then<void>(
      (_) async {
        await _store.record(_recordKey).put(database, mode.name);
      },
      onError: (Object _, StackTrace _) async {
        await _store.record(_recordKey).put(database, mode.name);
      },
    );
    return _writeTail;
  }
}

class SheetViewPreferenceScope extends InheritedNotifier<SheetViewPreferences> {
  const SheetViewPreferenceScope({
    super.key,
    required SheetViewPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);

  static SheetViewPreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SheetViewPreferenceScope>()
      ?.notifier;
}
