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
