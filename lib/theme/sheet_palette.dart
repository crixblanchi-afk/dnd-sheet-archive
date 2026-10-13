import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sheet_layout.dart';

/// Colori del documento, separati dai controlli Material e dalle fotografie.
class SheetPalette {
  const SheetPalette({
    required this.workspace,
    required this.paper,
    required this.ink,
    required this.text,
    required this.accent,
    required this.comment,
    required this.expertise,
  });

  final Color workspace;
  final Color paper;
  final Color ink;
  final Color text;
  final Color accent;
  final Color comment;
  final Color expertise;

  static const light = SheetPalette(
    workspace: Color(0xffdedbd2),
    paper: Colors.white,
    ink: Colors.black,
    text: Colors.black,
    accent: Color(0xff7b1f1f),
    comment: Color(0xffd32f2f),
    expertise: Color(0xffc62828),
  );

  // I valori di `paper` e `ink` sono gli stessi che
  // `scripts/generate_dark_artwork.py` cuoce dentro l'artwork scuro: devono
  // restare allineati, altrimenti i campi non appoggiano più sulla carta che
  // vedono intorno.
  static const dark = SheetPalette(
    workspace: Colors.black,
    paper: Color(0xff24211e),
    ink: Color(0xffc2b8a9),
    text: Color(0xffd4c9b8),
    accent: Color(0xffe5bd78),
    comment: Color(0xffffa08e),
    expertise: Color(0xffffa08e),
  );

  static SheetPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class SheetArtwork extends StatelessWidget {
  const SheetArtwork({super.key, required this.pageIndex});

  final int pageIndex;

  /// L'immagine dell'artwork così come la disegna [build], da precaricare.
  ///
  /// La chiave deve coincidere con quella di `Image.asset`, altrimenti il
  /// precaricamento riempirebbe la cache con un'immagine che nessuno usa.
  static ImageProvider imageFor(BuildContext context, int pageIndex) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ResizeImage.resizeIfNeeded(
      _cacheWidth(context),
      null,
      AssetImage(
        'assets/sheet/page-${pageIndex + 1}${dark ? '-dark' : ''}.png',
      ),
    );
  }

  // L'artwork è grande 1700x2200 per una pagina di 612x792 punti: a piena
  // risoluzione sono 15 MB di bitmap per pagina, e la vista a scorrimento le
  // tiene tutte e tre insieme. Decodificarlo alla densità dello schermo, con
  // un fattore 2 di margine per lo zoom, dimezza la memoria sui display 1x
  // senza togliere un pixel a ciò che si vede; il limite superiore è l'asset
  // stesso, oltre il quale non c'è più dettaglio da estrarre.
  static int _cacheWidth(BuildContext context) => math.min(
    sheetArtworkPixelWidth,
    (sheetPageWidth * MediaQuery.devicePixelRatioOf(context) * 2).round(),
  );

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    // La versione scura dell'artwork è precalcolata, non filtrata a runtime.
    // Prima due `ColorFiltered` annidati imponevano due `saveLayer` a piena
    // pagina a ogni rasterizzazione: con tre pagine vive nella vista a
    // scorrimento erano sei buffer fuori schermo da ridisegnare a ogni
    // variazione di zoom. Lo stesso risultato cotto nel PNG non costa nulla.
    // Ritratto e simbolo restano fuori da qui e conservano i colori originali.
    return ColoredBox(
      color: palette.paper,
      child: Image(
        image: imageFor(context, pageIndex),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
