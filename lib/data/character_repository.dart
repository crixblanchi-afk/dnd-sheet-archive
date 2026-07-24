import '../models/character.dart';
import '../models/character_version.dart';

abstract class CharacterRepository {
  Stream<List<CharacterSummary>> watchCharacters();
  Future<Character?> getCharacter(String id);
  Future<Character> createCharacter(String name);
  Future<void> saveCharacter(Character character);
  Future<void> renameCharacter(String id, String newName);
  Future<void> deleteCharacter(String id);
  Future<List<VersionMeta>> listVersions(String characterId);
  Future<CharacterVersion?> getVersion(String versionId);
  Future<void> createSnapshot(Character character, String reason);
  Future<void> restoreVersion(String characterId, String versionId);
}
