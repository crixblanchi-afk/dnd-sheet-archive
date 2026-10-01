# Sheet asset generation

The app does not parse PDFs at runtime. Regenerate its committed assets with:

```sh
python3 -m venv tools/.venv
tools/.venv/bin/pip install pypdf
tools/.venv/bin/python tools/extract_fields.py \
  dnd_5e_charactersheet_formfillable.pdf assets/sheet/fields.json
pdftoppm -png -r 200 dnd_5e_charactersheet_formfillable.pdf assets/sheet/page
```

Poppler names the images `page-1.png` through `page-3.png`.

## Editable PDF exports

The runtime builds AcroForms in Dart using the page artwork and field geometry.
Roboto Slab draws the initial values; the standard Helvetica form font lets
PDF readers regenerate field appearances while editing. The PDF font asset is
a static weight-400 version with decomposed outlines, avoiding recursive
parsing of empty composite glyphs in the PDF library. Regenerate it with:

```sh
tools/.venv/bin/pip install fonttools
tools/.venv/bin/python tools/prepare_pdf_font.py
```

Generate the test sample, inspect its logical fields, appearances, notes and
images, then edit and reopen it to check that characters remain independent:

```sh
PDF_EXPORT_PREVIEW=build/pdf-export-review.pdf \
  flutter test test/character_pdf_exporter_test.dart
tools/.venv/bin/python tools/validate_pdf_export.py \
  build/pdf-export-review.pdf --characters 2 --fixture
pdftoppm -png -r 120 build/pdf-export-review.pdf build/pdf-export-review
pdftoppm -png -r 120 build/pdf-export-review.edited.pdf build/pdf-export-edited
```

The validator can inspect other exports with `--characters N` and without
`--fixture`. It rejects missing or duplicate fields, read-only widgets,
inconsistent checkbox values and missing appearance streams.
