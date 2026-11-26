import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/character.dart';
import '../models/daggerheart_card.dart';
import '../models/game_system.dart';
import '../models/image_payload.dart';
import '../models/sheet_document.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import 'export_progress.dart';
import 'pdf_file_saver.dart';

typedef PdfFileSaver = Future<bool> Function(Uint8List bytes, String filename);

/// Risolve il valore di un campo immagine nei byte da incorporare.
typedef SheetImageReader = Future<Uint8List?> Function(Object? value);

/// Schede già composte sulle schede totali.
typedef ExportProgress = void Function(int done, int total);

class CharacterPdfExporter {
  CharacterPdfExporter({PdfFileSaver? saveFile, SheetImageReader? readImage})
    : _saveFile = saveFile ?? savePdfFile,
      _readImage = readImage ?? _readInlineImage;

  final PdfFileSaver _saveFile;
  final SheetImageReader _readImage;

  static Future<Uint8List?> _readInlineImage(Object? value) async =>
      decodeInlineImage(value);

  Future<bool> exportCharacters(
    List<Character> characters, {
    ExportProgress? onProgress,
  }) async {
    final bytes = await buildPdf(characters, onProgress: onProgress);
    return _saveFile(bytes, filenameFor(characters));
  }

  Future<Uint8List> buildPdf(
    List<Character> characters, {
    ExportProgress? onProgress,
  }) async {
    if (characters.isEmpty) {
      throw ArgumentError.value(
        characters,
        'characters',
        'Seleziona una scheda',
      );
    }
    // Copia prima degli await: l'export rappresenta una singola istantanea.
    final copies = characters.map((character) => character.copy()).toList();
    final documents = <SheetDocumentDef>[];
    final backgrounds = <String, ByteData>{};
    final images = <String, Uint8List>{};
    final cardAssets = <String, ByteData>{};
    List<DaggerheartCardDef>? cardCatalog;

    for (final character in copies) {
      final document = await SheetDocumentDef.loadFor(character);
      documents.add(document);
      for (final page in document.pages) {
        if (!backgrounds.containsKey(page.lightAsset)) {
          backgrounds[page.lightAsset] = await rootBundle.load(page.lightAsset);
        }
        for (final field in page.imageFields) {
          final value = character.fields[field.name];
          if (value is! String || value.isEmpty || images.containsKey(value)) {
            continue;
          }
          final bytes = await _readImage(value);
          if (bytes != null) images[value] = bytes;
        }
      }
      if (document.hasCardsPage) {
        final selected = selectedDaggerheartCardsFromFields(character.fields);
        if (selected.isNotEmpty) {
          cardCatalog ??= await DaggerheartCardDef.loadCatalog();
          for (final card in cardCatalog) {
            if (selected.containsKey(card.id) &&
                !cardAssets.containsKey(card.asset)) {
              cardAssets[card.asset] = await rootBundle.load(card.asset);
            }
          }
        }
      }
    }

    final font = await rootBundle.load('assets/fonts/RobotoSlab-Regular.ttf');
    final cardOrder = cardCatalog == null
        ? const <String>[]
        : [for (final card in cardCatalog) card.id];
    final cardAssetById = cardCatalog == null
        ? const <String, String>{}
        : {for (final card in cardCatalog) card.id: card.asset};

    final progress = openExportProgress(
      onProgress == null ? null : (done) => onProgress(done, copies.length),
    );
    try {
      return await compute(
        _buildPdf,
        _ExportData(
          copies,
          documents,
          backgrounds,
          font,
          images,
          cardAssets,
          cardOrder,
          cardAssetById,
          progress.token,
        ),
        debugLabel: 'character-pdf-export',
      );
    } finally {
      progress.close();
    }
  }

  static String filenameFor(List<Character> characters) {
    if (characters.length != 1) {
      final systems = characters.map((c) => c.system).toSet();
      if (systems.length == 1 && systems.single == GameSystem.daggerheart) {
        return 'schede-daggerheart.pdf';
      }
      return 'schede-dnd.pdf';
    }
    final single = characters.single;
    var name = single.name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) {
      name = single.system == GameSystem.daggerheart
          ? 'scheda-daggerheart'
          : 'scheda-dnd';
    }
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
  const _ExportData(
    this.characters,
    this.documents,
    this.backgrounds,
    this.font,
    this.images,
    this.cardAssets,
    this.cardOrder,
    this.cardAssetById,
    this.progressToken,
  );

  final List<Character> characters;
  final List<SheetDocumentDef> documents;
  final Map<String, ByteData> backgrounds;
  final ByteData font;

  /// Valore del campo immagine -> byte dell'immagine.
  final Map<String, Uint8List> images;

  /// Asset path -> byte WebP della card Daggerheart.
  final Map<String, ByteData> cardAssets;
  final List<String> cardOrder;
  final Map<String, String> cardAssetById;

  final Object? progressToken;
}

Future<Uint8List> _buildPdf(_ExportData data) async {
  final document = PdfDocument();
  PdfInfo(
    document,
    title: data.characters.map((c) => c.name).join(', '),
    creator: 'Archivio Schede',
  );
  final font = PdfTtfFont(document, data.font);
  // Font standard per l'editing: i lettori PDF possono rigenerare l'aspetto
  // senza dipendere dalla codifica CID del font incorporato nelle anteprime.
  final formFont = PdfFont.helvetica(document);
  final appearanceFont = _AppearanceFont(font);
  final backgrounds = <String, PdfImage>{
    for (final entry in data.backgrounds.entries)
      entry.key: PdfImage.file(
        document,
        bytes: entry.value.buffer.asUint8List(
          entry.value.offsetInBytes,
          entry.value.lengthInBytes,
        ),
      ),
  };
  // Una sola copia per immagine anche quando più schede la mostrano: il PDF
  // la referenzia da ogni pagina invece di incorporarla ogni volta.
  final images = <String, PdfImage>{};
  final cardImages = <String, PdfImage>{};

  for (var index = 0; index < data.characters.length; index++) {
    final character = data.characters[index];
    final sheetDoc = data.documents[index];
    for (var pageIndex = 0; pageIndex < sheetDoc.pages.length; pageIndex++) {
      final pageSpec = sheetDoc.pages[pageIndex];
      final page = PdfPage(
        document,
        pageFormat: const PdfPageFormat(sheetPageWidth, sheetPageHeight),
      );
      page.getGraphics().drawImage(
        backgrounds[pageSpec.lightAsset]!,
        0,
        0,
        sheetPageWidth,
        sheetPageHeight,
      );
      for (final imageField in pageSpec.imageFields) {
        final value = character.fields[imageField.name];
        final bytes = value is String ? data.images[value] : null;
        if (bytes != null) {
          final image = images.putIfAbsent(
            value! as String,
            () => PdfImage.file(document, bytes: bytes),
          );
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
      for (final field in pageSpec.fields) {
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

    if (sheetDoc.hasCardsPage) {
      final selected = selectedDaggerheartCardsFromFields(character.fields);
      final selectedAssets = <String>[
        for (final cardId in data.cardOrder)
          if (selected.containsKey(cardId) &&
              data.cardAssetById.containsKey(cardId))
            data.cardAssetById[cardId]!,
      ];
      // Griglia 3x3 Print-and-Play (180x252 pt per card su pagina Letter).
      const cardW = 180.0;
      const cardH = 252.0;
      const marginX = 36.0;
      const marginY = 18.0;
      for (var offset = 0; offset < selectedAssets.length; offset += 9) {
        final page = PdfPage(
          document,
          pageFormat: const PdfPageFormat(sheetPageWidth, sheetPageHeight),
        );
        final graphics = page.getGraphics();
        final slice = selectedAssets.skip(offset).take(9).toList();
        for (var slot = 0; slot < slice.length; slot++) {
          final asset = slice[slot];
          final pdfImage = cardImages.putIfAbsent(asset, () {
            final raw = data.cardAssets[asset]!;
            final bytes = raw.buffer.asUint8List(
              raw.offsetInBytes,
              raw.lengthInBytes,
            );
            final decoded = img.decodeWebP(bytes);
            final jpeg = decoded == null
                ? bytes
                : Uint8List.fromList(img.encodeJpg(decoded, quality: 86));
            return PdfImage.file(document, bytes: jpeg);
          });
          final col = slot % 3;
          final row = slot ~/ 3;
          final x = marginX + col * cardW;
          final y = sheetPageHeight - marginY - (row + 1) * cardH;
          graphics.drawImage(pdfImage, x, y, cardW, cardH);
        }
      }
    }

    reportExportProgress(data.progressToken, index + 1);
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
