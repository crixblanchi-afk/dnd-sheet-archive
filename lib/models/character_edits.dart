import 'character.dart';

/// Applica solo le differenze della sessione, conservando gli altri valori
/// ricevuti da Drive. Sullo stesso campo prevale la modifica locale esplicita.
Character applyCharacterEdits({
  required Character base,
  required Character edited,
  required Character current,
}) {
  if (base.id != edited.id || edited.id != current.id) {
    throw ArgumentError('Le modifiche appartengono a un altro personaggio.');
  }
  final result = current.copy();
  void applyMap<T>(
    Map<String, T> before,
    Map<String, T> after,
    Map<String, T> to,
  ) {
    for (final key in {...before.keys, ...after.keys}) {
      if (before.containsKey(key) == after.containsKey(key) &&
          before[key] == after[key]) {
        continue;
      }
      if (after.containsKey(key)) {
        to[key] = after[key] as T;
      } else {
        to.remove(key);
      }
    }
  }

  applyMap(base.fields, edited.fields, result.fields);
  applyMap(base.comments, edited.comments, result.comments);
  if (edited.name != base.name) result.rename(edited.name);
  if (edited.locked != base.locked) result.locked = edited.locked;
  return result;
}
