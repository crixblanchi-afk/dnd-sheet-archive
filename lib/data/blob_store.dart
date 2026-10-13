import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import '../models/image_payload.dart';

/// Le immagini della scheda, indirizzate per hash del contenuto.
///
/// Prima vivevano in base64 dentro il campo del personaggio: ogni autosalvataggio
/// riscriveva l'immagine per intero, ciascuno dei dieci snapshot se ne portava
/// via una copia e il backup su Drive le sommava tutte, arrivando a sfiorare il
/// tetto dei 20 MB con due sole schede illustrate. Tenendole qui, le versioni di
/// una stessa scheda condividono un solo blob e il record del personaggio torna
/// a pesare quanto il suo testo.
class BlobStore {
  BlobStore(this.database);

  final Database database;

  /// Gli ultimi blob letti, con la loro identità.
  ///
  /// `MemoryImage` confronta i byte per identità: restituendo una lista nuova
  /// a ogni lettura, tornare su una pagina già vista manderebbe a vuoto la
  /// cache delle immagini di Flutter e costringerebbe a ridecodificare il
  /// ritratto da capo. Il contenuto è immutabile per costruzione — la chiave è
  /// il suo hash — quindi riusare l'istanza è sempre corretto.
  /// Legata all'istanza: il repository ne tiene una sola per tutta la vita
  /// dell'app, mentre una cache statica si porterebbe dietro i blob di un
  /// archivio diverso — nei test, di un database diverso.
  final _decoded = <String, Uint8List>{};
  static const _decodedLimit = 8;

  static final _blobs = stringMapStoreFactory.store('blobs');
  static final _characters = stringMapStoreFactory.store('characters');
  static final _versions = stringMapStoreFactory.store('versions');
  static final _metadata = stringMapStoreFactory.store('sync_metadata');
  static const _migrationKey = 'image_blob_migration';
  static const _migrationVersion = 1;

  Future<Uint8List?> read(String reference) async {
    final cached = _decoded[reference];
    if (cached != null) return cached;
    final bytes = _decode(await _blobs.record(reference).get(database));
    if (bytes == null) return null;
    _decoded[reference] = bytes;
    while (_decoded.length > _decodedLimit) {
      _decoded.remove(_decoded.keys.first);
    }
    return bytes;
  }

  /// Salva l'immagine, se non c'è già, e restituisce il suo riferimento.
  Future<String> write(Uint8List bytes) async {
    final reference = blobReferenceFor(bytes);
    await database.transaction((transaction) async {
      if (await _blobs.record(reference).get(transaction) != null) return;
      await _blobs.record(reference).put(transaction, {
        'data': base64Encode(bytes),
      });
    });
    return reference;
  }

  /// I payload base64 dei riferimenti richiesti, per il backup su Drive.
  Future<Map<String, String>> readPayloads(
    DatabaseClient client,
    Iterable<String> references,
  ) async {
    final payloads = <String, String>{};
    for (final reference in references.toSet()) {
      final data = (await _blobs.record(reference).get(client))?['data'];
      if (data is String) payloads[reference] = data;
    }
    return payloads;
  }

  /// Scrive i payload arrivati dal backup, saltando quelli già presenti.
  Future<void> writePayloads(
    DatabaseClient client,
    Map<String, String> payloads,
  ) async {
    for (final entry in payloads.entries) {
      if (await _blobs.record(entry.key).get(client) != null) continue;
      await _blobs.record(entry.key).put(client, {'data': entry.value});
    }
  }

  /// Elimina le immagini che nessuna scheda e nessuna versione cita più.
  ///
  /// Va chiamata dentro la stessa transazione che può aver lasciato orfano un
  /// blob, così l'archivio non resta mai in uno stato in cui un'immagine è
  /// irraggiungibile ma occupa ancora spazio nel backup.
  Future<void> collectGarbage(DatabaseClient client) async {
    final live = <String>{};
    for (final store in [_characters, _versions]) {
      for (final record in await store.find(client)) {
        final fields = record.value['fields'];
        if (fields is Map) {
          live.addAll(
            blobReferencesIn({
              for (final entry in fields.entries)
                if (entry.key is String) entry.key as String: entry.value,
            }),
          );
        }
      }
    }
    for (final record in await _blobs.find(client)) {
      if (!live.contains(record.key)) {
        await _blobs.record(record.key).delete(client);
        _decoded.remove(record.key);
      }
    }
  }

  /// Sposta nei blob le immagini delle schede salvate prima di questo archivio.
  ///
  /// Procede un record per volta: una migrazione interrotta lascia parte delle
  /// schede nel formato vecchio, che resta leggibile, e riprende al prossimo
  /// avvio. Restituisce `true` se qualcosa si è spostato, perché in quel caso
  /// il backup su Drive va riscritto nella forma deduplicata.
  Future<bool> migrateInlineImages() async {
    final state = await _metadata.record(_migrationKey).get(database);
    if (state?['version'] == _migrationVersion) return false;

    var moved = false;
    for (final store in [_characters, _versions]) {
      for (final record in await store.find(database)) {
        final fields = record.value['fields'];
        if (fields is! Map) continue;
        final extracted = <String, String>{};
        final migrated = {
          for (final entry in fields.entries)
            if (entry.key is String) entry.key as String: entry.value,
        };
        if (!extractInlineImages(migrated, extracted)) continue;
        await database.transaction((transaction) async {
          await writePayloads(transaction, extracted);
          await store.record(record.key).put(transaction, {
            ...record.value,
            'fields': migrated,
          });
        });
        moved = true;
      }
    }
    await _metadata.record(_migrationKey).put(database, {
      'version': _migrationVersion,
    });
    return moved;
  }

  static Uint8List? _decode(Map<String, Object?>? record) {
    final data = record?['data'];
    if (data is! String) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }
}
