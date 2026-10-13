import 'dart:convert';

import 'package:collection/collection.dart';

import 'character.dart';

const _deepEquals = DeepCollectionEquality();

/// Segnaposto per un elemento che la scheda non contiene.
const Object _absent = Object();

/// Le chiavi degli orologi che descrivono una scheda: nome, blocco, ogni
/// campo e ogni commento, compresi quelli rimossi di cui resta l'orologio.
Set<String> characterClockKeys(Character character) => {
  'name',
  'locked',
  for (final name in character.fields.keys) 'field:$name',
  for (final name in character.comments.keys) 'comment:$name',
  ...character.clocks.keys,
};

/// Registra come cambiati, all'istante corrente, gli elementi di [after] che
/// differiscono da [before], la versione salvata finora.
///
/// Gli altri elementi riprendono l'orologio di [before]: chi salva una copia
/// della scheda non deve poter rinfrescare, o invecchiare, ciò che non ha
/// toccato.
///
/// L'istante non scende mai sotto l'ultimo orologio di [before]: una modifica
/// fatta dopo aver ricevuto quella di un dispositivo con l'orologio avanti
/// resta comunque la più recente, invece di perdere il confronto.
void stampCharacterChanges({
  required Character? before,
  required Character after,
  required DateTime now,
}) {
  var stamp = now.toUtc();
  if (before == null) {
    after
      ..clocks.clear()
      ..clockFloor = stamp
      ..updatedAt = stamp;
    return;
  }
  final latest = [
    before.updatedAt,
    ...before.clocks.values,
  ].reduce((a, b) => a.isAfter(b) ? a : b);
  if (!stamp.isAfter(latest)) {
    // Un millisecondo, non un microsecondo: sul Web `DateTime` non scende
    // sotto il millisecondo e l'incremento andrebbe perso.
    stamp = latest.toUtc().add(const Duration(milliseconds: 1));
  }
  final clocks = <String, DateTime>{};
  for (final key in {
    ...characterClockKeys(before),
    ...characterClockKeys(after),
  }) {
    final unchanged = _sameValue(_valueAt(before, key), _valueAt(after, key));
    clocks[key] = unchanged ? _clockAt(before, key) : stamp;
  }
  after
    ..clockFloor = before.clockFloor
    ..clocks.clear()
    ..clocks.addAll(_explicitClocks(clocks, before.clockFloor))
    ..updatedAt = stamp;
}

/// Unisce due copie della stessa scheda elemento per elemento.
///
/// Per ogni campo, commento, nome e blocco prevale la modifica più recente; a
/// parità di orologio decide il valore, così ogni dispositivo arriva allo
/// stesso risultato in qualunque ordine riceva le copie. Due dispositivi che
/// modificano campi diversi della stessa scheda conservano quindi entrambe le
/// modifiche, invece di perdere quelle di chi ha salvato per primo.
Character mergeCharacters(Character a, Character b) {
  if (a.id != b.id) {
    throw ArgumentError('Le copie appartengono a personaggi diversi.');
  }
  final floor = _latest(a.clockFloor, b.clockFloor);
  final result = Character(
    id: a.id,
    name: a.name,
    createdAt: a.createdAt.isBefore(b.createdAt) ? a.createdAt : b.createdAt,
    updatedAt: _latest(a.updatedAt, b.updatedAt),
    locked: a.locked,
    clockFloor: floor,
  );
  final clocks = <String, DateTime>{};
  for (final key in {...characterClockKeys(a), ...characterClockKeys(b)}) {
    final clockA = _clockAt(a, key);
    final clockB = _clockAt(b, key);
    final valueA = _valueAt(a, key);
    final valueB = _valueAt(b, key);
    final order = clockA.compareTo(clockB);
    final takeB =
        order < 0 ||
        (order == 0 &&
            _stableValue(valueB).compareTo(_stableValue(valueA)) > 0);
    _assign(result, key, takeB ? valueB : valueA);
    clocks[key] = takeB ? clockB : clockA;
  }
  result.clocks.addAll(_explicitClocks(clocks, floor));
  return result;
}

/// Gli orologi che dicono qualcosa in più di [floor].
///
/// Ogni orologio è almeno pari al pavimento, quindi tralasciare quelli uguali
/// non cambia nulla, e tiene identiche due schede equivalenti: unire una
/// scheda con sé stessa la lascia com'è, e il sync non riscrive record che non
/// sono cambiati.
Map<String, DateTime> _explicitClocks(
  Map<String, DateTime> clocks,
  DateTime floor,
) => {
  for (final entry in clocks.entries)
    if (entry.value.isAfter(floor)) entry.key: entry.value.toUtc(),
};

DateTime _clockAt(Character character, String key) =>
    character.clocks[key] ?? character.clockFloor;

DateTime _latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

Object? _valueAt(Character character, String key) {
  if (key == 'name') return character.name;
  if (key == 'locked') return character.locked;
  if (key.startsWith('field:')) {
    final name = key.substring('field:'.length);
    return character.fields.containsKey(name)
        ? character.fields[name]
        : _absent;
  }
  if (key.startsWith('comment:')) {
    final name = key.substring('comment:'.length);
    return character.comments.containsKey(name)
        ? character.comments[name]
        : _absent;
  }
  return _absent;
}

void _assign(Character character, String key, Object? value) {
  if (key == 'name') {
    if (value is String) character.name = value;
  } else if (key == 'locked') {
    if (value is bool) character.locked = value;
  } else if (key.startsWith('field:')) {
    final name = key.substring('field:'.length);
    if (identical(value, _absent)) {
      character.fields.remove(name);
    } else {
      character.fields[name] = value;
    }
  } else if (key.startsWith('comment:')) {
    final name = key.substring('comment:'.length);
    if (value is String) {
      character.comments[name] = value;
    } else {
      character.comments.remove(name);
    }
  }
}

bool _sameValue(Object? a, Object? b) {
  if (identical(a, _absent) || identical(b, _absent)) return identical(a, b);
  return _deepEquals.equals(a, b);
}

/// Un ordinamento totale dei valori, per i pareggi: l'assenza viene prima di
/// qualunque valore.
String _stableValue(Object? value) =>
    identical(value, _absent) ? '' : jsonEncode(value);
