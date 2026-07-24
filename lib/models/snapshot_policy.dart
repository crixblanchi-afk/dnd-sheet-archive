import 'character_version.dart';

const automaticSnapshotWindow = Duration(days: 1);
const maxSnapshotsPerCharacter = 10;

bool isAutomaticSnapshot(String reason) =>
    reason == 'session' || reason == 'lock';

List<CharacterVersion> retainRecentSnapshots(
  Iterable<CharacterVersion> versions, {
  Set<String>? activeCharacterIds,
}) {
  final grouped = <String, List<CharacterVersion>>{};
  for (final version in versions) {
    if (activeCharacterIds != null &&
        !activeCharacterIds.contains(version.characterId)) {
      continue;
    }
    grouped.putIfAbsent(version.characterId, () => []).add(version);
  }

  final retained = <CharacterVersion>[];
  for (final characterVersions in grouped.values) {
    characterVersions.sort((a, b) {
      final dateOrder = b.createdAt.compareTo(a.createdAt);
      return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
    });
    retained.addAll(characterVersions.take(maxSnapshotsPerCharacter));
  }
  return retained;
}
