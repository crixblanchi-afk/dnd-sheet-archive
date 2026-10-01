import 'dart:math' as math;

/// Geometria della scheda stampata, in punti PDF a 72 dpi: sono le stesse
/// unità usate dalle coordinate di `assets/sheet/fields.json`, così i campi
/// possono essere posizionati sull'immagine senza conversioni.
const sheetPageCount = 3;
const sheetPageWidth = 612.0;
const sheetPageHeight = 792.0;

/// Spazio fra una pagina e la successiva nella colonna scorrevole.
const sheetPageGap = 12.0;

/// Altezza complessiva delle pagine impilate, spazi compresi.
const sheetContentHeight =
    sheetPageCount * sheetPageHeight + (sheetPageCount - 1) * sheetPageGap;

/// Limiti di zoom condivisi da `InteractiveViewer`, dalla rotellina del mouse
/// e dai pulsanti di zoom, che altrimenti si fermerebbero a soglie diverse.
const sheetMinScale = .3;
const sheetMaxScale = 6.0;

/// Traslazione orizzontale che tiene la scheda al centro del viewport quando
/// è più stretta di esso; zero quando deborda, così scorre dal bordo sinistro.
double sheetCenterOffset(double viewportWidth, double scaledSheetWidth) =>
    math.max(0, (viewportWidth - scaledSheetWidth) / 2);

/// Riporta la traslazione orizzontale nell'intervallo ammesso: una scheda più
/// stretta del viewport resta centrata invece di scivolare a sinistra, una più
/// larga scorre liberamente fra i due bordi.
double clampSheetTranslationX(
  double translationX,
  double viewportWidth,
  double scaledSheetWidth,
) {
  final center = sheetCenterOffset(viewportWidth, scaledSheetWidth);
  final maxScroll = math.max(0.0, scaledSheetWidth - viewportWidth);
  return translationX.clamp(center - maxScroll, center);
}

// I riquadri illustrati della pagina 2 non sono campi modulo del PDF, quindi
// non hanno una voce in fields.json: i loro limiti sono misurati a mano
// sull'artwork in assets/sheet/page-2.png.
const sheetImageFields = [
  // "Character Appearance", la colonna di sinistra.
  (
    name: 'CharacterAppearanceImage',
    page: 1,
    x: 31.0,
    y: 128.0,
    width: 172.0,
    height: 222.0,
  ),
  // Il riquadro del simbolo in "Allies & Organizations": la cornice va da
  // x 417.6 a 566.3 e da y 142 a 290, ma la parte alta è occupata dal campo
  // FactionName (fino a y 169.3) e il fondo dalla dicitura "SYMBOL".
  (
    name: 'FactionSymbolImage',
    page: 1,
    x: 420.0,
    y: 171.0,
    width: 143.0,
    height: 114.0,
  ),
];
