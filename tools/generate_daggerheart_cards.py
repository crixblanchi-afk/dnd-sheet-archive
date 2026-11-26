#!/usr/bin/env python3
"""Extract Daggerheart Print-and-Play cards into WebP assets and catalog JSON.

Usage:
    uv run --with pymupdf --with pillow python3 \
        tools/generate_daggerheart_cards.py <cards_pdf>
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import re
import subprocess
from pathlib import Path

import numpy as np
import pymupdf
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "daggerheart" / "cards"

SUBCLASS_CLASSES = [
    "bard",
    "druid",
    "guardian",
    "ranger",
    "rogue",
    "seraph",
    "sorcerer",
    "warrior",
    "wizard",
]

DOMAINS = [
    "arcana",
    "blade",
    "bone",
    "codex",
    "grace",
    "midnight",
    "sage",
    "splendor",
    "valor",
]

# Known exact overrides only if OCR struggles on tiny footer/ornament edges.
# We still prefer algorithmic extraction and verify 0 missing/duplicate IDs.
IGNORE_LABELS = {
    "SPELL",
    "ABILITY",
    "GRIMOIRE",
    "COMMUNITY",
    "ANCESTRY",
    "FOUNDATION",
    "SPECIALIZATION",
    "MASTERY",
    "BARD",
    "DRUID",
    "GUARDIAN",
    "RANGER",
    "ROGUE",
    "SERAPH",
    "SORCERER",
    "WARRIOR",
    "WIZARD",
}


def find_text_start_y(im: Image.Image) -> int:
    """Find the Y coordinate right below the horizontal gold divider bar."""
    arr = np.asarray(im, dtype=np.float32)
    h, w, _ = arr.shape
    # The gold/yellow banner sits in the middle band (roughly y=30%..52%).
    # Detect rows with strong warm yellow/gold chroma (R > B + 25) across the width.
    y0, y1 = int(h * 0.25), int(h * 0.56)
    band = arr[y0:y1, int(w * 0.1) : int(w * 0.9)]
    yellow = (band[:, :, 0] - band[:, :, 2]) > 22
    row_frac = yellow.mean(axis=1)
    gold_rows = np.where(row_frac > 0.25)[0]
    if len(gold_rows) > 0:
        return y0 + int(gold_rows[-1]) + 4
    return int(h * 0.49)


def ocr_image(im: Image.Image, psm: int = 6, scale: int = 3, threshold: bool = False) -> str:
    gray = ImageOps.grayscale(im)
    if threshold:
        arr = np.asarray(gray)
        gray = Image.fromarray(np.where(arr < 180, 0, 255).astype(np.uint8))
    if scale > 1:
        gray = gray.resize((gray.width * scale, gray.height * scale), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    gray.save(buf, "PNG")
    res = subprocess.run(
        ["tesseract", "stdin", "stdout", "--psm", str(psm)],
        input=buf.getvalue(),
        capture_output=True,
        check=False,
    )
    return res.stdout.decode("utf-8", errors="ignore").strip()


def extract_core_number(im: Image.Image, category: str) -> int | None:
    w, h = im.size
    # Try multiple footer crops / thresholds so tiny 3-digit numbers never drop digits.
    crops = [
        ((150, int(h * 0.935), w - 15, h - 5), 7, 4, False),
        ((150, int(h * 0.93), w - 15, h - 4), 6, 4, True),
        ((100, int(h * 0.91), w - 5, h), 6, 3, False),
    ]
    lo, hi = {
        "subclass": (1, 54),
        "ancestry": (55, 72),
        "community": (73, 81),
        "domain": (82, 270),
    }[category]
    for box, psm, scale, thresh in crops:
        text = ocr_image(im.crop(box), psm=psm, scale=scale, threshold=thresh)
        for m in re.finditer(r"(\d{2,3})\s*/\s*270", text):
            num = int(m.group(1))
            if lo <= num <= hi:
                return num
            # Common OCR drop of leading '1' on domain cards (e.g. 150 -> 50, 111 -> 11)
            if category == "domain" and lo <= num + 100 <= hi:
                return num + 100
            if category == "domain" and lo <= num + 200 <= hi:
                return num + 200
    return None


def extract_title(text: str) -> str:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    for ln in lines[:4]:
        # Strip leading/trailing punctuation noise
        cleaned = re.sub(r"[^A-Za-z0-9'\-&\s]", " ", ln).strip()
        cleaned = re.sub(r"\s+", " ", cleaned)
        if not cleaned or len(cleaned) < 3:
            continue
        upper = cleaned.upper()
        if upper in IGNORE_LABELS:
            continue
        if upper.startswith("SPELLCAST TRAIT"):
            continue
        # Title lines on Daggerheart cards are ALL CAPS (mostly uppercase letters).
        letters = [c for c in cleaned if c.isalpha()]
        if not letters:
            continue
        upper_ratio = sum(1 for c in letters if c.isupper()) / len(letters)
        if upper_ratio >= 0.7 and len(cleaned) <= 36:
            return cleaned.title()
    return ""


def process_card(task: tuple[int, str, int, bytes]) -> dict:
    order, page_label, page_num, raw_bytes = task
    im = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
    w, h = im.size  # 500x700

    label_low = page_label.lower().strip()
    level: int | None = None
    tier: str | None = None
    if label_low.startswith("domain level"):
        category = "domain"
        m = re.search(r"(\d+)", label_low)
        level = int(m.group(1)) if m else 1
    elif "foundation" in label_low:
        category = "subclass"
        tier = "foundation"
    elif "specialization" in label_low:
        category = "subclass"
        tier = "specialization"
    elif "mastery" in label_low:
        category = "subclass"
        tier = "mastery"
    elif "community" in label_low:
        category = "community"
    else:
        category = "ancestry"

    core_num = extract_core_number(im, category)

    # Locate the exact white text area strictly below the gold divider bar.
    start_y = find_text_start_y(im)
    title_text = ocr_image(im.crop((16, start_y, w - 16, min(h - 40, start_y + 72))), psm=6, scale=3)
    body_text = ocr_image(im.crop((16, start_y, w - 16, int(h * 0.925))), psm=6, scale=2)

    title = extract_title(title_text) or extract_title(body_text)
    if not title:
        # Try slightly higher start_y in case the gold bar detection landed slightly low
        alt = ocr_image(im.crop((16, max(0, start_y - 22), w - 16, min(h - 40, start_y + 75))), psm=6, scale=3)
        title = extract_title(alt) or f"Card {core_num or order}"

    # Fix tiny title casing quirks (e.g. 'S -> 's, Of -> of)
    title = re.sub(r"'S\b", "'s", title)

    domain: str | None = None
    class_name: str | None = None
    if category == "domain" and core_num is not None and 82 <= core_num <= 270:
        domain = DOMAINS[(core_num - 82) // 21]
    elif category == "subclass" and core_num is not None and 1 <= core_num <= 54:
        class_name = SUBCLASS_CLASSES[(core_num - 1) // 6]

    snippet = re.sub(r"\s+", " ", body_text).strip()
    if len(snippet) > 220:
        snippet = snippet[:220]

    return {
        "order": order,
        "coreNumber": core_num,
        "title": title,
        "category": category,
        "domain": domain,
        "level": level,
        "className": class_name,
        "tier": tier,
        "searchText": snippet,
        "_raw": raw_bytes,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("cards_pdf", type=Path)
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # Clean old webp files to avoid stale card_XXX files
    for old in OUT_DIR.glob("*.webp"):
        old.unlink()

    doc = pymupdf.open(args.cards_pdf)

    seen_hashes: set[str] = set()
    tasks: list[tuple[int, str, int, bytes]] = []
    order = 0
    for page_idx, page in enumerate(doc):
        page_label = page.get_text().strip()
        slots = []
        for img in page.get_images(full=True):
            xref = img[0]
            for rect in page.get_image_rects(xref):
                slots.append((round(rect.y0), round(rect.x0), xref))
        slots.sort()
        for _, _, xref in slots:
            raw = doc.extract_image(xref)["image"]
            h = hashlib.sha256(raw).hexdigest()
            if h in seen_hashes:
                continue
            seen_hashes.add(h)
            order += 1
            tasks.append((order, page_label, page_idx + 1, raw))
    doc.close()

    print(f"Extracting and OCR-ing {len(tasks)} unique cards...")
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(process_card, tasks))

    # Sanity check & save WebPs
    cards: list[dict] = []
    used_ids: set[str] = set()
    missing = 0
    for item in results:
        raw_bytes = item.pop("_raw")
        ord_idx = item.pop("order")
        core_num = item["coreNumber"]
        if core_num is None:
            missing += 1
            card_id = f"card_{ord_idx:03d}"
        else:
            card_id = f"core_{core_num:03d}"
            if card_id in used_ids:
                card_id = f"card_{ord_idx:03d}"
        used_ids.add(card_id)
        asset_name = f"{card_id}.webp"
        Image.open(io.BytesIO(raw_bytes)).convert("RGB").save(
            OUT_DIR / asset_name, "WEBP", quality=80, method=4
        )
        entry = {
            "id": card_id,
            "coreNumber": core_num,
            "title": item["title"],
            "category": item["category"],
            "asset": f"assets/daggerheart/cards/{asset_name}",
            "searchText": item["searchText"],
        }
        for k in ("domain", "level", "className", "tier"):
            if item[k] is not None:
                entry[k] = item[k]
        cards.append(entry)

    cat_order = {"ancestry": 0, "community": 1, "subclass": 2, "domain": 3}
    tier_order = {"foundation": 0, "specialization": 1, "mastery": 2}
    cards.sort(
        key=lambda c: (
            cat_order.get(c["category"], 9),
            c.get("className", ""),
            tier_order.get(c.get("tier", ""), 9),
            c.get("domain", ""),
            c.get("level", 0),
            c.get("coreNumber") or 9999,
            c["title"],
        )
    )

    catalog_path = OUT_DIR / "catalog.json"
    catalog_path.write_text(
        json.dumps(cards, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(cards)} cards (missing coreNumber: {missing})")
    # Print any remaining anomalies
    nums = [c["coreNumber"] for c in cards if c["coreNumber"] is not None]
    print("Missing in 1..270:", sorted(set(range(1, 271)) - set(nums)))
    dups = [n for n in sorted(set(nums)) if nums.count(n) > 1]
    print("Duplicates:", dups)
    bad_titles = [
        c for c in cards
        if c["title"].startswith("Card ") or len(c["title"]) < 3 or len(c["title"]) > 34
    ]
    print(f"Suspicious titles: {len(bad_titles)}")
    for c in bad_titles:
        print("  BAD:", c["id"], c["category"], c["title"], "|", c["searchText"][:60])


if __name__ == "__main__":
    main()
