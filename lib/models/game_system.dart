/// Sistema di gioco supportato dall'archivio schede.
enum GameSystem {
  dnd5e('dnd5e', 'D&D 5e'),
  daggerheart('daggerheart', 'Daggerheart');

  const GameSystem(this.id, this.label);

  final String id;
  final String label;

  static GameSystem fromJson(Object? value) {
    if (value is String) {
      for (final system in values) {
        if (system.id == value) return system;
      }
    }
    return GameSystem.dnd5e;
  }
}

/// Template di classe per le schede Daggerheart.
enum DaggerheartClass {
  bard('bard', 'Bard', ['grace', 'codex']),
  druid('druid', 'Druid', ['sage', 'arcana']),
  guardian('guardian', 'Guardian', ['valor', 'blade']),
  ranger('ranger', 'Ranger', ['bone', 'sage']),
  rogue('rogue', 'Rogue', ['midnight', 'grace']),
  seraph('seraph', 'Seraph', ['splendor', 'valor']),
  sorcerer('sorcerer', 'Sorcerer', ['arcana', 'midnight']),
  warrior('warrior', 'Warrior', ['blade', 'bone']),
  wizard('wizard', 'Wizard', ['codex', 'splendor']),
  blank('blank', 'Generica (vuota)', []);

  const DaggerheartClass(this.id, this.label, this.domains);

  final String id;
  final String label;

  /// I due domini della classe (vuoto per la scheda generica).
  final List<String> domains;

  static DaggerheartClass? fromJson(Object? value) {
    if (value is! String) return null;
    for (final cls in values) {
      if (cls.id == value) return cls;
    }
    return null;
  }
}
