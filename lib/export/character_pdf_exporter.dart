import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/character.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import 'pdf_file_saver.dart';

typedef PdfFileSaver = Future<bool> Function(Uint8List bytes, String filename);

class CharacterPdfExporter {
  CharacterPdfExporter({PdfFileSaver? saveFile})
    : _saveFile = saveFile ?? savePdfFile;

  final PdfFileSaver _saveFile;

  Future<bool> exportCharacters(List<Character> characters) async {
    final bytes = await buildPdf(characters);
    return _saveFile(bytes, filenameFor(characters));
  }

  Future<Uint8List> buildPdf(List<Character> characters) async {
    if (characters.isEmpty) {
      throw ArgumentError.value(
        characters,
        'characters',
        'Seleziona una scheda',
      );
    }
    // Copia prima degli await: l'export rappresenta una singola istantanea.
    final copies = characters.map((character) => character.copy()).toList();
    final fields = await SheetFieldDef.loadByPage();
    final backgrounds = <ByteData>[];
    for (var page = 1; page <= sheetPageCount; page++) {
      backgrounds.add(await rootBundle.load('assets/sheet/page-$page.png'));
    }
    final font = await rootBundle.load('assets/fonts/RobotoSlab-Regular.ttf');
    return compute(
      _buildPdf,
      _ExportData(copies, fields, backgrounds, font),
      debugLabel: 'character-pdf-export',
    );
  }

  static String filenameFor(List<Character> characters) {
    if (characters.length != 1) return 'schede-dnd.pdf';
    var name = characters.single.name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = 'scheda-dnd';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = 'scheda-$name';
    }
    name = String.fromCharCodes(name.runes.take(100));
    return '$name.pdf';
  }
}

class _ExportData {
  const _ExportData(this.characters, this.fields, this.backgrounds, this.font);

  final List<Character> characters;
  final List<List<SheetFieldDef>> fields;
  final List<ByteData> backgrounds;
  final ByteData font;
}

Future<Uint8List> _buildPdf(_ExportData data) async {
  final document = PdfDocument();
  PdfInfo(
    document,
    title: data.characters.map((c) => c.name).join(', '),
    creator: 'Archivio schede D&D 5e',
  );
  final font = PdfTtfFont(document, data.font);
  // Font standard per l'editing: i lettori PDF possono rigenerare l'aspetto
  // senza dipendere dalla codifica CID del font incorporato nelle anteprime.
  final formFont = PdfFont.helvetica(document);
  final appearanceFont = _AppearanceFont(font);
  final backgrounds = [
    for (final bytes in data.backgrounds)
      PdfImage.file(
        document,
        bytes: bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
      ),
  ];
  for (var index = 0; index < data.characters.length; index++) {
    final character = data.characters[index];
    for (var pageIndex = 0; pageIndex < sheetPageCount; pageIndex++) {
      final page = PdfPage(
        document,
        pageFormat: const PdfPageFormat(sheetPageWidth, sheetPageHeight),
      );
      page.getGraphics().drawImage(
        backgrounds[pageIndex],
        0,
        0,
        sheetPageWidth,
        sheetPageHeight,
      );
      for (final imageField in sheetImageFields.where(
        (field) => field.page == pageIndex,
      )) {
        final value = character.fields[imageField.name];
        if (value is String && value.isNotEmpty) {
          final image = PdfImage.file(document, bytes: base64Decode(value));
          final scale = math.min(
            imageField.width / image.width,
            imageField.height / image.height,
          );
          final width = image.width * scale;
          final height = image.height * scale;
          page.getGraphics().drawImage(
            image,
            imageField.x + (imageField.width - width) / 2,
            sheetPageHeight - imageField.y - (imageField.height + height) / 2,
            width,
            height,
          );
        }
      }
      for (final field in data.fields[pageIndex]) {
        final rect = PdfRect(
          field.x,
          sheetPageHeight - field.y - field.height,
          field.width,
          field.height,
        );
        // Il prefisso impedisce che modificare una scheda cambi anche le altre.
        final name = 'character_${index + 1}_${field.name}';
        final value = character.fields[field.name];
        if (field.type == SheetFieldType.text) {
          final text = value?.toString() ?? '';
          final fontSize = field.multiline
              ? 9.0
              : math.min(12.0, field.height * .65);
          final annotation = PdfTextField(
            rect: rect,
            fieldName: name,
            alternateName: '${character.name}: ${field.name}',
            font: formFont,
            fontSize: 0, // Ridimensionamento automatico anche nelle modifiche.
            textColor: PdfColors.black,
            textAlign: PdfTextFieldAlign.values[field.align.clamp(0, 2)],
            fieldFlags: {if (field.multiline) PdfFieldFlags.multiline},
            value: text,
            defaultValue: text,
          );
          final canvas = annotation.appearance(
            document,
            PdfAnnotAppearance.normal,
            boundingBox: PdfRect(0, 0, field.width, field.height),
          );
          if (text.isNotEmpty) {
            final alignment = field.align == 1
                ? (field.multiline
                      ? pw.Alignment.topCenter
                      : pw.Alignment.center)
                : field.align == 2
                ? (field.multiline
                      ? pw.Alignment.topRight
                      : pw.Alignment.centerRight)
                : (field.multiline
                      ? pw.Alignment.topLeft
                      : pw.Alignment.centerLeft);
            final textWidget = pw.Text(
              text,
              style: pw.TextStyle(font: appearanceFont, fontSize: fontSize),
              softWrap: field.multiline,
              textAlign: switch (field.align) {
                1 => pw.TextAlign.center,
                2 => pw.TextAlign.right,
                _ => pw.TextAlign.left,
              },
            );
            pw.Widget.draw(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: alignment,
                  child: field.multiline
                      ? pw.SizedBox(
                          width: math.max(1, field.width - 2),
                          child: textWidget,
                        )
                      : textWidget,
                ),
              ),
              page: page,
              canvas: canvas,
              offset: PdfPoint.zero,
              constraints: pw.BoxConstraints.tightFor(
                width: field.width,
                height: field.height,
              ),
            );
          }
          PdfAnnot(page, annotation);
        } else {
          final state = SheetCheckboxValue.fromStored(value);
          final selected = switch (state) {
            SheetCheckboxValue.unchecked => '/Off',
            SheetCheckboxValue.proficient => '/Yes',
            SheetCheckboxValue.expertise => '/Expertise',
          };
          final annotation = PdfButtonField(
            rect: rect,
            fieldName: name,
            alternateName: '${character.name}: ${field.name}',
            value: selected,
            defaultValue: selected,
          );
          for (final appearance in [
            '/Off',
            '/Yes',
            if (field.supportsExpertise) '/Expertise',
          ]) {
            final canvas = annotation.appearance(
              document,
              PdfAnnotAppearance.normal,
              name: appearance,
              selected: appearance == selected,
              boundingBox: PdfRect(0, 0, field.width, field.height),
            );
            if (appearance != '/Off') {
              final radius = math.min(field.width, field.height) * .30;
              canvas
                ..setFillColor(
                  appearance == '/Expertise'
                      ? PdfColors.red700
                      : PdfColors.black,
                )
                ..drawEllipse(field.width / 2, field.height / 2, radius, radius)
                ..fillPath();
            }
          }
          PdfAnnot(page, annotation);
        }
        final comment = character.comments[field.name];
        if (comment != null && comment.isNotEmpty) {
          PdfAnnot(
            page,
            PdfAnnotText(
              rect: PdfRect(rect.right - 8, rect.top - 8, 8, 8),
              content: comment,
              subject: field.name,
              author: character.name,
            ),
          );
        }
      }
    }
  }
  return document.save();
}

class _AppearanceFont extends pw.Font {
  _AppearanceFont(this.embedded);

  final PdfFont embedded;

  @override
  PdfFont buildFont(PdfDocument pdfDocument) => embedded;

  @override
  String get fontName => embedded.fontName;
}
