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
