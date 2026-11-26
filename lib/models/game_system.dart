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
  bard('bard', 'Bard', ['grace', 'codex'], 5, 6, 10),
  druid('druid', 'Druid', ['sage', 'arcana'], 6, 6, 10),
  guardian('guardian', 'Guardian', ['valor', 'blade'], 7, 6, 9),
  ranger('ranger', 'Ranger', ['bone', 'sage'], 6, 6, 12),
  rogue('rogue', 'Rogue', ['midnight', 'grace'], 6, 6, 12),
  seraph('seraph', 'Seraph', ['splendor', 'valor'], 7, 6, 9),
  sorcerer('sorcerer', 'Sorcerer', ['arcana', 'midnight'], 6, 6, 10),
  warrior('warrior', 'Warrior', ['blade', 'bone'], 6, 6, 11),
  wizard('wizard', 'Wizard', ['codex', 'splendor'], 5, 6, 11),
  blank('blank', 'Generica (vuota)', [], 5, 6, 10);

  const DaggerheartClass(
    this.id,
    this.label,
    this.domains,
    this.startingHp,
    this.startingStress,
    this.startingEvasion,
  );

  final String id;
  final String label;

  /// I due domini della classe (vuoto per la scheda generica).
  final List<String> domains;

  /// Numero di slot HP iniziali (caselle a bordo continuo sulla scheda di classe).
  final int startingHp;

  /// Numero di slot Stress iniziali sulla scheda di classe.
  final int startingStress;

  /// Valore iniziale di Evasion riportato sulla scheda di classe.
  final int startingEvasion;

  static DaggerheartClass? fromJson(Object? value) {
    if (value is! String) return null;
    for (final cls in values) {
      if (cls.id == value) return cls;
    }
    return null;
  }
}
