import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Prefisso delle chiavi in `Character.fields` per le card selezionate.
///
/// Salvare una voce per card invece di una singola lista fa sì che il merge
/// campo per campo di Drive conservi le selezioni fatte su dispositivi diversi.
const daggerheartCardFieldPrefix = 'dh_card:';

String daggerheartCardFieldKey(String cardId) =>
    '$daggerheartCardFieldPrefix$cardId';

bool isDaggerheartCardFieldKey(String key) =>
    key.startsWith(daggerheartCardFieldPrefix);

String? daggerheartCardIdFromFieldKey(String key) =>
    isDaggerheartCardFieldKey(key)
    ? key.substring(daggerheartCardFieldPrefix.length)
    : null;

/// Stato di una card nella scheda del personaggio.
enum DaggerheartCardState {
  none,
  loadout,
  vault;

  bool get isSelected => this != none;

  factory DaggerheartCardState.fromStored(Object? value) => switch (value) {
    true || 'loadout' => DaggerheartCardState.loadout,
    'vault' => DaggerheartCardState.vault,
    _ => DaggerheartCardState.none,
  };

  Object? toStored() => switch (this) {
    DaggerheartCardState.none => null,
    DaggerheartCardState.loadout => true,
    DaggerheartCardState.vault => 'vault',
  };
}

enum DaggerheartCardCategory {
  ancestry('ancestry', 'Ancestry'),
  community('community', 'Community'),
  subclass('subclass', 'Subclass'),
  domain('domain', 'Domain');

  const DaggerheartCardCategory(this.id, this.label);

  final String id;
  final String label;

  static DaggerheartCardCategory fromJson(Object? value) {
    if (value is String) {
      for (final category in values) {
        if (category.id == value) return category;
      }
    }
    return DaggerheartCardCategory.domain;
  }
}

const daggerheartDomainLabels = <String, String>{
  'arcana': 'Arcana',
  'blade': 'Blade',
  'bone': 'Bone',
  'codex': 'Codex',
  'grace': 'Grace',
  'midnight': 'Midnight',
  'sage': 'Sage',
  'splendor': 'Splendor',
  'valor': 'Valor',
};

const daggerheartSubclassTierLabels = <String, String>{
  'foundation': 'Foundation',
  'specialization': 'Specialization',
  'mastery': 'Mastery',
};

class DaggerheartCardDef {
  const DaggerheartCardDef({
    required this.id,
    required this.title,
    required this.category,
    required this.asset,
    required this.searchText,
    this.coreNumber,
    this.domain,
    this.level,
    this.className,
    this.tier,
  });

  final String id;
  final int? coreNumber;
  final String title;
  final DaggerheartCardCategory category;
  final String asset;
  final String searchText;
  final String? domain;
  final int? level;
  final String? className;
  final String? tier;

  String get subtitle {
    switch (category) {
      case DaggerheartCardCategory.ancestry:
        return 'Ancestry';
      case DaggerheartCardCategory.community:
        return 'Community';
      case DaggerheartCardCategory.subclass:
        final cls = className == null
            ? 'Subclass'
            : '${className![0].toUpperCase()}${className!.substring(1)}';
        final tierLabel = tier == null
            ? ''
            : ' · ${daggerheartSubclassTierLabels[tier] ?? tier}';
        return '$cls$tierLabel';
      case DaggerheartCardCategory.domain:
        final domainLabel = domain == null
            ? 'Domain'
            : (daggerheartDomainLabels[domain] ?? domain!);
        final lv = level == null ? '' : ' · Lv $level';
        return '$domainLabel$lv';
    }
  }

  bool matchesQuery(String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return title.toLowerCase().contains(normalizedQuery) ||
        subtitle.toLowerCase().contains(normalizedQuery) ||
        (domain?.toLowerCase().contains(normalizedQuery) ?? false) ||
        (className?.toLowerCase().contains(normalizedQuery) ?? false) ||
        searchText.toLowerCase().contains(normalizedQuery);
  }

  factory DaggerheartCardDef.fromJson(Map<String, Object?> json) =>
      DaggerheartCardDef(
        id: json['id']! as String,
        coreNumber: (json['coreNumber'] as num?)?.toInt(),
        title: json['title']! as String,
        category: DaggerheartCardCategory.fromJson(json['category']),
        asset: json['asset']! as String,
        searchText: json['searchText'] as String? ?? '',
        domain: json['domain'] as String?,
        level: (json['level'] as num?)?.toInt(),
        className: json['className'] as String?,
        tier: json['tier'] as String?,
      );

  static Future<List<DaggerheartCardDef>>? _cachedCatalogFuture;
  static List<DaggerheartCardDef>? _cachedCatalog;

  static List<DaggerheartCardDef>? get cachedCatalog => _cachedCatalog;

  static Future<List<DaggerheartCardDef>> loadCatalog() =>
      _cachedCatalogFuture ??= _loadCatalog();

  static Future<List<DaggerheartCardDef>> _loadCatalog() async {
    final source = await rootBundle.loadString(
      'assets/daggerheart/cards/catalog.json',
    );
    final decoded = await compute(_decodeCatalogJson, source);
    return _cachedCatalog = List<DaggerheartCardDef>.unmodifiable([
      for (final item in decoded)
        DaggerheartCardDef.fromJson(Map<String, Object?>.from(item as Map)),
    ]);
  }
}

List<dynamic> _decodeCatalogJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List<dynamic>) {
    throw const FormatException('catalog.json must contain a JSON array');
  }
  return decoded;
}

/// Restituisce le selezioni correnti (cardId -> stato) salvate nei campi.
Map<String, DaggerheartCardState> selectedDaggerheartCardsFromFields(
  Map<String, Object?> fields,
) {
  final result = <String, DaggerheartCardState>{};
  for (final entry in fields.entries) {
    final cardId = daggerheartCardIdFromFieldKey(entry.key);
    if (cardId == null) continue;
    final state = DaggerheartCardState.fromStored(entry.value);
    if (state.isSelected) result[cardId] = state;
  }
  return result;
}
