#!/usr/bin/env python3
"""Generate the shipped dark sheet artwork (requires Pillow, NumPy, PyMuPDF).

Run from any directory after changing the monochrome source pages or palette.
This bakes the former sRGB-to-linear + ink/paper mapping into PNGs, avoiding
full-page ColorFiltered layers on mobile GPUs. Character uploads never enter
this script.
"""
from pathlib import Path
import fitz
from PIL import Image, ImageDraw
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PAPER = (36, 33, 30)  # SheetPalette.dark.paper
INK = (194, 184, 169)  # SheetPalette.dark.ink, for printed labels
ORNAMENT = (145, 134, 121)  # Frames, lines and other non-text artwork

with fitz.open(ROOT / "dnd_5e_charactersheet_formfillable.pdf") as document:
    for page in range(1, 4):
        source = ROOT / "assets" / "sheet" / f"page-{page}.png"
        with Image.open(source) as image:
            rgb = np.asarray(image.convert("RGB"), dtype=np.float64) / 255
            linear = np.where(
                rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4
            )
            luminance = linear @ np.array([.2126, .7152, .0722])

            # The source PDF retains the printed labels as selectable text.
            # Protect their rectangles so ornamentation can be dimmed without
            # making the tiny labels harder to read.
            mask = Image.new("L", image.size)
            draw = ImageDraw.Draw(mask)
            sx = image.width / document[page - 1].rect.width
            sy = image.height / document[page - 1].rect.height
            for x0, y0, x1, y1, *_ in document[page - 1].get_text("words"):
                draw.rectangle(
                    (x0 * sx, y0 * sy, x1 * sx, y1 * sy), fill=255
                )
            labels = np.asarray(mask, dtype=np.float64)[..., None] / 255
            ink = np.array(ORNAMENT) * (1 - labels) + np.array(INK) * labels
            pixels = np.rint(
                ink + luminance[..., None] * (np.array(PAPER) - ink)
            )
            destination = source.with_name(f"page-{page}-dark.png")
            Image.fromarray(pixels.clip(0, 255).astype(np.uint8)).save(
                destination, optimize=True
            )
            print(destination.name)
