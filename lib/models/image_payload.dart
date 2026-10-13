import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'sheet_layout.dart';

/// I campi della scheda che contengono un'immagine invece di testo.
final imageFieldNames = {for (final field in sheetImageFields) field.name};

/// Prefisso dei valori che non contengono l'immagine ma la indirizzano.
const blobReferencePrefix = 'blob:';

bool isBlobReference(Object? value) =>
    value is String && value.startsWith(blobReferencePrefix);

/// Riferimento di un'immagine: l'hash del suo contenuto.
///
/// Indirizzare per contenuto significa che due schede, o dieci versioni della
/// stessa scheda, che mostrano la stessa immagine ne condividono una sola
/// copia, sia nell'archivio locale sia nel backup su Drive.
String blobReferenceFor(List<int> bytes) =>
    '$blobReferencePrefix${sha256.convert(bytes)}';

/// I byte di un'immagine ancora salvata dentro il campo, in base64.
///
/// Prima dell'archivio dei blob era l'unico formato: resta leggibile perché le
/// schede salvate allora devono continuare ad aprirsi, e perché un backup
/// Drive scritto da una versione precedente arriva ancora così.
Uint8List? decodeInlineImage(Object? value) {
  if (value is! String || value.isEmpty || isBlobReference(value)) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}

/// I riferimenti citati dai campi immagine di una scheda o di una versione.
Iterable<String> blobReferencesIn(Map<String, Object?> fields) => [
  for (final name in imageFieldNames)
    if (isBlobReference(fields[name])) fields[name] as String,
];

/// Sposta nei blob le immagini ancora salvate dentro i campi.
///
/// Opera sulla mappa dei campi passata, che viene riscritta con i soli
/// riferimenti, e restituisce `true` se qualcosa si è spostato.
bool extractInlineImages(
  Map<String, Object?> fields,
  Map<String, String> blobs,
) {
  var moved = false;
  for (final name in imageFieldNames) {
    final bytes = decodeInlineImage(fields[name]);
    if (bytes == null) continue;
    final reference = blobReferenceFor(bytes);
    // La riscrittura canonica evita che due codifiche base64 degli stessi
    // byte convivano nel backup come payload distinti.
    blobs[reference] = base64Encode(bytes);
    fields[name] = reference;
    moved = true;
  }
  return moved;
}
