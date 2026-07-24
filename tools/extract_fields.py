#!/usr/bin/env python3
"""Extract the fixed character sheet AcroForm into Flutter-friendly JSON."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from pypdf import PdfReader


PUSHBUTTON_FLAG = 1 << 16
MULTILINE_FLAG = 1 << 12


def inherited(widget, key):
    """Return an inheritable form value, walking through /Parent fields."""
    current = widget
    while current is not None:
        obj = current.get_object()
        if key in obj:
            return obj[key]
        current = obj.get("/Parent")
    return None


def extract(source: Path) -> list[dict]:
    reader = PdfReader(source)
    fields: list[dict] = []

    for page_index, page in enumerate(reader.pages):
        page_width = float(page.mediabox.width)
        page_height = float(page.mediabox.height)
        for annotation_ref in page.get("/Annots", []):
            annotation = annotation_ref.get_object()
            if annotation.get("/Subtype") != "/Widget":
                continue

            field_type = inherited(annotation, "/FT")
            flags = int(inherited(annotation, "/Ff") or 0)
            if field_type == "/Btn" and flags & PUSHBUTTON_FLAG:
                continue
            if field_type not in ("/Tx", "/Btn"):
                continue

            name = inherited(annotation, "/T")
            if name is None:
                raise ValueError(f"Widget on page {page_index + 1} has no /T")

            x1, y1, x2, y2 = (float(value) for value in annotation["/Rect"])
            left, right = sorted((x1, x2))
            bottom, top = sorted((y1, y2))
            rect = {
                "x": left,
                "y": page_height - top,
                "w": right - left,
                "h": top - bottom,
            }
            if not (
                0 <= rect["x"] <= page_width
                and 0 <= rect["y"] <= page_height
                and rect["x"] + rect["w"] <= page_width + 0.01
                and rect["y"] + rect["h"] <= page_height + 0.01
            ):
                raise ValueError(f"Out-of-bounds rect for {name!r}: {rect}")

            item = {
                "name": str(name),
                "page": page_index,
                "type": "text" if field_type == "/Tx" else "checkbox",
                **{key: round(value, 4) for key, value in rect.items()},
            }
            if field_type == "/Tx":
                item["multiline"] = bool(flags & MULTILINE_FLAG)
                item["align"] = int(inherited(annotation, "/Q") or 0)
            fields.append(item)

    names = [field["name"] for field in fields]
    if len(names) != len(set(names)):
        duplicates = sorted({name for name in names if names.count(name) > 1})
        raise ValueError(f"Duplicate field names: {duplicates}")
    if len(fields) != 332:
        raise ValueError(f"Expected 332 fields, extracted {len(fields)}")
    return fields


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    fields = extract(args.source)
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(
        json.dumps(fields, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(fields)} fields to {args.destination}")


if __name__ == "__main__":
    main()
