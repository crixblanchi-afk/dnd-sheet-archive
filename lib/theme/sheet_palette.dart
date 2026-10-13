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

  static const dark = SheetPalette(
    workspace: Color(0xff111418),
    paper: Color(0xff202329),
    ink: Color(0xffddd8cd),
    text: Color(0xfff2eadb),
    accent: Color(0xffe5bd78),
    comment: Color(0xffffa08e),
    expertise: Color(0xffffa08e),
  );

  static SheetPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Nero → inchiostro, bianco → carta, alpha invariato. Il filtro va
  /// applicato esclusivamente all'artwork, mai allo Stack della pagina.
  ColorFilter get artworkFilter {
    final r = (paper.r - ink.r);
    final g = (paper.g - ink.g);
    final b = (paper.b - ink.b);
    return ColorFilter.matrix([
      r * .2126,
      r * .7152,
      r * .0722,
      0,
      ink.r * 255,
      g * .2126,
      g * .7152,
      g * .0722,
      0,
      ink.g * 255,
      b * .2126,
      b * .7152,
      b * .0722,
      0,
      ink.b * 255,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}

class SheetArtwork extends StatelessWidget {
  const SheetArtwork({super.key, required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    // L'artwork è grande 1700x2200 per una pagina di 612x792 punti: a piena
    // risoluzione sono 15 MB di bitmap per pagina, e la vista a scorrimento le
    // tiene tutte e tre insieme. Decodificarlo alla densità dello schermo, con
    // un fattore 2 di margine per lo zoom, dimezza la memoria sui display 1x
    // senza togliere un pixel a ciò che si vede; il limite superiore è l'asset
    // stesso, oltre il quale non c'è più dettaglio da estrarre.
    final cacheWidth = math.min(
      sheetArtworkPixelWidth,
      (sheetPageWidth * MediaQuery.devicePixelRatioOf(context) * 2).round(),
    );
    final image = Image.asset(
      'assets/sheet/page-${pageIndex + 1}.png',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      cacheWidth: cacheWidth,
    );
    return ColoredBox(
      color: palette.paper,
      child: Theme.of(context).brightness == Brightness.dark
          ? ColorFiltered(
              colorFilter: palette.artworkFilter,
              // La curva tonale mantiene leggibili le etichette grigie del
              // PDF; una semplice inversione le renderebbe troppo scure.
              child: ColorFiltered(
                colorFilter: const ColorFilter.srgbToLinearGamma(),
                child: image,
              ),
            )
          : image,
    );
  }
}
