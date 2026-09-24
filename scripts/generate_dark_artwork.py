#!/usr/bin/env python3
"""Generate the shipped dark sheet artwork (requires Pillow and NumPy).

Run from any directory after changing the monochrome source pages or palette.
This bakes the former sRGB-to-linear + ink/paper mapping into PNGs, avoiding
full-page ColorFiltered layers on mobile GPUs. Character uploads never enter
this script.
"""
from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PAPER = (32, 35, 41)  # SheetPalette.dark.paper
INK = (221, 216, 205)  # SheetPalette.dark.ink


for page in range(1, 4):
    source = ROOT / "assets" / "sheet" / f"page-{page}.png"
    with Image.open(source) as image:
        rgb = np.asarray(image.convert("RGB"), dtype=np.float64) / 255
        linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
        luminance = linear @ np.array([.2126, .7152, .0722])
        pixels = np.rint(np.array(INK) + luminance[..., None] * (np.array(PAPER) - INK))
        destination = source.with_name(f"page-{page}-dark.png")
        Image.fromarray(pixels.clip(0, 255).astype(np.uint8)).save(destination, optimize=True)
        print(destination.name)
