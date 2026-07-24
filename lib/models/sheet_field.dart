import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SheetFieldType { text, checkbox }

enum SheetCheckboxValue {
  unchecked,
  proficient,
  expertise;

  factory SheetCheckboxValue.fromStored(Object? value) => switch (value) {
    true => SheetCheckboxValue.proficient,
    'expertise' => SheetCheckboxValue.expertise,
    _ => SheetCheckboxValue.unchecked,
  };

  SheetCheckboxValue next({required bool allowExpertise}) => switch (this) {
    SheetCheckboxValue.unchecked => SheetCheckboxValue.proficient,
    SheetCheckboxValue.proficient when allowExpertise =>
      SheetCheckboxValue.expertise,
    _ => SheetCheckboxValue.unchecked,
  };
}

class SheetFieldDef {
  const SheetFieldDef({
    required this.name,
    required this.page,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.multiline,
    required this.align,
  });

  final String name;
  final int page;
  final SheetFieldType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool multiline;
  final int align;

  bool get supportsExpertise => _skillProficiencyFields.contains(name);

  factory SheetFieldDef.fromJson(Map<String, Object?> json) {
    final pageValue = json['page'];
    if (pageValue is! num || pageValue != pageValue.roundToDouble()) {
      throw FormatException('Invalid field page: $pageValue');
    }
    final type = switch (json['type']) {
      'text' => SheetFieldType.text,
      'checkbox' => SheetFieldType.checkbox,
      final value => throw FormatException('Unknown field type: $value'),
    };
    return SheetFieldDef(
      name: json['name']! as String,
      page: pageValue.toInt(),
      type: type,
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: (json['w']! as num).toDouble(),
      height: (json['h']! as num).toDouble(),
      multiline: json['multiline'] as bool? ?? false,
      align: (json['align'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<List<SheetFieldDef>>>? _cachedByPage;

  static Future<List<List<SheetFieldDef>>> loadByPage() =>
      _cachedByPage ??= _loadByPage();

  static Future<List<List<SheetFieldDef>>> _loadByPage() async {
    final source = await rootBundle.loadString('assets/sheet/fields.json');
    final decoded = await compute(_decodeFieldJson, source);
    final pages = List.generate(3, (_) => <SheetFieldDef>[]);
    for (final item in decoded) {
      final field = SheetFieldDef.fromJson(
        Map<String, Object?>.from(item as Map),
      );
      if (field.page < 0 || field.page >= pages.length) {
        throw FormatException(
          'Field ${field.name} refers to missing page ${field.page}',
        );
      }
      pages[field.page].add(field);
    }
    return List.unmodifiable(
      pages.map((fields) => List<SheetFieldDef>.unmodifiable(fields)),
    );
  }
}

const _skillProficiencyFields = {
  'Check Box 23',
  'Check Box 24',
  'Check Box 25',
  'Check Box 26',
  'Check Box 27',
  'Check Box 28',
  'Check Box 29',
  'Check Box 30',
  'Check Box 31',
  'Check Box 32',
  'Check Box 33',
  'Check Box 34',
  'Check Box 35',
  'Check Box 36',
  'Check Box 37',
  'Check Box 38',
  'Check Box 39',
  'Check Box 40',
};

List<dynamic> _decodeFieldJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List<dynamic>) {
    throw const FormatException('fields.json must contain a JSON array');
  }
  return decoded;
}
