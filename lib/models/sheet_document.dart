import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'character.dart';
import 'game_system.dart';
import 'sheet_field.dart';
import 'sheet_layout.dart';

class SheetImageFieldSpec {
  const SheetImageFieldSpec({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
}

class SheetPageSpec {
  const SheetPageSpec({
    required this.label,
    required this.lightAsset,
    required this.darkAsset,
    required this.fields,
    this.imageFields = const [],
  });

  final String label;
  final String lightAsset;
  final String darkAsset;
  final List<SheetFieldDef> fields;
  final List<SheetImageFieldSpec> imageFields;
}

class SheetDocumentDef {
  SheetDocumentDef({
    required this.system,
    required this.pages,
    required this.hasCardsPage,
  }) : fieldsByPage = List<List<SheetFieldDef>>.unmodifiable([
         for (final page in pages) page.fields,
       ]);

  final GameSystem system;
  final List<SheetPageSpec> pages;
  final List<List<SheetFieldDef>> fieldsByPage;
  final bool hasCardsPage;

  int get pdfPageCount => pages.length;
  int get totalPageCount => pages.length + (hasCardsPage ? 1 : 0);

  double get scrollContentHeight =>
      sheetContentHeightForPageCount(pages.length);

  static Future<_DaggerheartFieldBundle>? _daggerheartBundle;

  static Future<SheetDocumentDef> loadFor(Character character) async {
    switch (character.system) {
      case GameSystem.dnd5e:
        final fieldsByPage = await SheetFieldDef.loadByPage();
        return SheetDocumentDef(
          system: GameSystem.dnd5e,
          hasCardsPage: false,
          pages: List<SheetPageSpec>.unmodifiable([
            for (var page = 0; page < sheetPageCount; page++)
              SheetPageSpec(
                label: 'Pagina ${page + 1}',
                lightAsset: 'assets/sheet/page-${page + 1}.png',
                darkAsset: 'assets/sheet/page-${page + 1}-dark.png',
                fields: fieldsByPage[page],
                imageFields: [
                  for (final imageField in sheetImageFields)
                    if (imageField.page == page)
                      SheetImageFieldSpec(
                        name: imageField.name,
                        x: imageField.x,
                        y: imageField.y,
                        width: imageField.width,
                        height: imageField.height,
                      ),
                ],
              ),
          ]),
        );
      case GameSystem.daggerheart:
        final bundle = await (_daggerheartBundle ??= _loadDaggerheartFields());
        final cls = character.daggerheartClass ?? DaggerheartClass.blank;
        final pages = <SheetPageSpec>[];

        final mainFields = List<SheetFieldDef>.unmodifiable([
          ...bundle.mainCommon,
          ...?bundle.mainExtras[cls.id],
        ]);
        pages.add(
          SheetPageSpec(
            label: 'Scheda',
            lightAsset: 'assets/daggerheart/sheets/${cls.id}-p1.png',
            darkAsset: 'assets/daggerheart/sheets/${cls.id}-p1-dark.png',
            fields: mainFields,
          ),
        );

        if (cls == DaggerheartClass.druid) {
          pages.add(
            const SheetPageSpec(
              label: 'Beastform 1–2',
              lightAsset: 'assets/daggerheart/sheets/druid-beastform-1.png',
              darkAsset: 'assets/daggerheart/sheets/druid-beastform-1-dark.png',
              fields: [],
            ),
          );
          pages.add(
            const SheetPageSpec(
              label: 'Beastform 3–4',
              lightAsset: 'assets/daggerheart/sheets/druid-beastform-2.png',
              darkAsset: 'assets/daggerheart/sheets/druid-beastform-2-dark.png',
              fields: [],
            ),
          );
        }

        if (cls == DaggerheartClass.ranger) {
          pages.add(
            SheetPageSpec(
              label: 'Compagno',
              lightAsset: 'assets/daggerheart/sheets/ranger-companion.png',
              darkAsset: 'assets/daggerheart/sheets/ranger-companion-dark.png',
              fields: bundle.rangerCompanion,
              imageFields: const [
                SheetImageFieldSpec(
                  name: 'DH_CompanionImage',
                  x: 184,
                  y: 105,
                  width: 362,
                  height: 145,
                ),
              ],
            ),
          );
        }

        if (cls != DaggerheartClass.blank) {
          pages.add(
            SheetPageSpec(
              label: 'Guida & Livelli',
              lightAsset: 'assets/daggerheart/sheets/${cls.id}-guide.png',
              darkAsset: 'assets/daggerheart/sheets/${cls.id}-guide-dark.png',
              fields: bundle.guide,
            ),
          );
        }

        return SheetDocumentDef(
          system: GameSystem.daggerheart,
          hasCardsPage: true,
          pages: List<SheetPageSpec>.unmodifiable(pages),
        );
    }
  }

  static Future<_DaggerheartFieldBundle> _loadDaggerheartFields() async {
    final source = await rootBundle.loadString(
      'assets/daggerheart/sheets/fields.json',
    );
    final decoded = await compute(_decodeDaggerheartJson, source);
    List<SheetFieldDef> parseList(Object? raw, int page) {
      if (raw is! List) return const [];
      return List<SheetFieldDef>.unmodifiable([
        for (final item in raw)
          SheetFieldDef.fromJson({
            ...Map<String, Object?>.from(item as Map),
            'page': page,
          }),
      ]);
    }

    final extrasMap = decoded['mainExtras'] as Map? ?? const {};
    return _DaggerheartFieldBundle(
      mainCommon: parseList(decoded['mainCommon'], 0),
      mainExtras: {
        for (final entry in extrasMap.entries)
          entry.key as String: parseList(entry.value, 0),
      },
      guide: parseList(decoded['guide'], 1),
      rangerCompanion: parseList(decoded['rangerCompanion'], 1),
    );
  }
}

class _DaggerheartFieldBundle {
  const _DaggerheartFieldBundle({
    required this.mainCommon,
    required this.mainExtras,
    required this.guide,
    required this.rangerCompanion,
  });

  final List<SheetFieldDef> mainCommon;
  final Map<String, List<SheetFieldDef>> mainExtras;
  final List<SheetFieldDef> guide;
  final List<SheetFieldDef> rangerCompanion;
}

Map<String, Object?> _decodeDaggerheartJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException(
      'daggerheart fields.json must be a JSON object',
    );
  }
  return Map<String, Object?>.from(decoded);
}
