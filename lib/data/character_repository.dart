import 'dart:convert';
import 'dart:typed_data';

import '../models/character.dart';
import '../models/character_version.dart';
import '../models/image_payload.dart';

abstract class CharacterRepository {
  Stream<List<CharacterSummary>> watchCharacters();
  Future<Character?> getCharacter(String id);
  Future<Character> createCharacter(String name);
  Future<void> saveCharacter(Character character);
  Future<Character> saveCharacterEdits(
    Character character,
    Character base,
  ) async {
    await saveCharacter(character);
    return character.copy();
  }

  Stream<Character?> watchCharacter(String id) => const Stream.empty();

  /// I byte dell'immagine a cui punta il valore di un campo immagine.
  ///
  /// L'implementazione di base risolve il solo formato storico, con
  /// l'immagine in base64 dentro il campo.
  Future<Uint8List?> readImage(Object? value) async => decodeInlineImage(value);

  /// Salva l'immagine e restituisce il valore da scrivere nel campo.
  Future<String> storeImage(Uint8List bytes) async => base64Encode(bytes);

  Future<void> renameCharacter(String id, String newName);
  Future<void> deleteCharacter(String id);
  Future<List<VersionMeta>> listVersions(String characterId);
  Future<CharacterVersion?> getVersion(String versionId);
  Future<void> createSnapshot(Character character, String reason);
  Future<void> restoreVersion(String characterId, String versionId);
}
