#!/usr/bin/env python3
"""Generate Daggerheart sheet PNGs (light & dark) and fillable field definitions.

Usage:
    uv run --with pymupdf --with pillow --with numpy python3 \
        tools/generate_daggerheart_assets.py <sheets_dir>
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pymupdf
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "daggerheart" / "sheets"

# Match D&D 5e sheet artwork dimensions (612x792 pts -> 1700x2200 px, 200 dpi).
PAGE_W = 612.0
PAGE_H = 792.0
PIXEL_W = 1700
PIXEL_H = 2200

# Match SheetPalette.dark in lib/theme/sheet_palette.dart and scripts/generate_dark_artwork.py.
PAPER = (36, 33, 30)
INK = (194, 184, 169)
ORNAMENT = (145, 134, 121)

CLASSES = [
    ("bard", "Bard.pdf"),
    ("druid", "Druid.pdf"),
    ("guardian", "Guardian.pdf"),
    ("ranger", "Ranger.pdf"),
    ("rogue", "Rogue.pdf"),
    ("seraph", "Seraph.pdf"),
    ("sorcerer", "Sorcerer.pdf"),
    ("warrior", "Warrior.pdf"),
    ("wizard", "Wizard.pdf"),
    ("blank", "Blank_Character_Sheet.pdf"),
]


def _field_text(
    name: str,
    x: float,
    y: float,
    w: float,
    h: float,
    *,
    multiline: bool = False,
    align: int = 0,
) -> dict:
    return {
        "name": name,
        "type": "text",
        "x": round(x, 2),
        "y": round(y, 2),
        "w": round(w, 2),
        "h": round(h, 2),
        "multiline": multiline,
        "align": align,
    }


def _field_check(name: str, x: float, y: float, w: float, h: float) -> dict:
    return {
        "name": name,
        "type": "checkbox",
        "x": round(x, 2),
        "y": round(y, 2),
        "w": round(w, 2),
        "h": round(h, 2),
    }


def build_main_common_fields() -> list[dict]:
    fields: list[dict] = []

    # Header boxes (Name, Pronouns, Heritage, Subclass, Level)
    # Name box is 206.4..395.8, y 7.8..25.8; label "NAME" occupies top ~7pt.
    fields.append(_field_text("CharacterName", 209.0, 14.0, 184.0, 11.5))
    fields.append(_field_text("DH_Pronouns", 402.5, 14.0, 128.5, 11.5))
    fields.append(_field_text("DH_Heritage", 198.5, 34.0, 165.0, 11.5))
    fields.append(_field_text("DH_Subclass", 372.5, 34.0, 158.5, 11.5))
    fields.append(_field_text("DH_Level", 554.0, 16.0, 35.0, 27.0, align=1))

    # Defense: Evasion, Armor Score, 12 Armor Slots (4 rows x 3 cols)
    fields.append(_field_text("DH_Evasion", 21.0, 86.0, 36.5, 28.0, align=1))
    fields.append(_field_text("DH_ArmorScore", 86.5, 86.0, 37.5, 28.0, align=1))
    armor_xs = [135.7, 148.8, 161.8]
    armor_ys = [78.7, 93.1, 107.5, 121.8]
    slot_idx = 1
    for y in armor_ys:
        for x in armor_xs:
            fields.append(_field_check(f"DH_ArmorSlot_{slot_idx}", x, y, 10.8, 12.0))
            slot_idx += 1

    # 6 Core Traits: shield score + level-up mark circle
    traits = [
        ("Agility", 208.4, 247.4),
        ("Strength", 276.7, 315.7),
        ("Finesse", 343.2, 382.2),
        ("Instinct", 409.8, 448.8),
        ("Presence", 478.1, 517.1),
        ("Knowledge", 544.5, 583.5),
    ]
    for trait, box_x, circle_x in traits:
        fields.append(_field_text(f"DH_Trait_{trait}", box_x + 2.0, 81.0, 32.7, 29.0, align=1))
        fields.append(_field_check(f"DH_TraitMark_{trait}", circle_x, 66.3, 13.7, 13.7))

    # Damage & Health: Major & Severe Thresholds (arrows between Minor/Major/Severe)
    fields.append(_field_text("DH_Threshold_Major", 83.0, 190.5, 22.0, 17.0, align=1))
    fields.append(_field_text("DH_Threshold_Severe", 171.0, 190.5, 22.0, 17.0, align=1))

    # 12 HP slots & 12 Stress slots
    for i in range(12):
        fields.append(_field_check(f"DH_HP_{i + 1}", 37.0 + i * 18.77, 229.6, 15.3, 9.6))
    for i in range(12):
        fields.append(_field_check(f"DH_Stress_{i + 1}", 62.9 + i * 16.5, 251.6, 13.4, 9.6))

    # Hope: 6 diamond checkboxes
    hope_xs = [39.9, 75.3, 110.8, 146.3, 181.7, 217.2]
    for i, x in enumerate(hope_xs):
        fields.append(_field_check(f"DH_Hope_{i + 1}", x, 302.3, 14.4, 14.4))

    # Experience: 5 lines + 5 modifier boxes
    exp_ys = [394.8, 414.5, 434.1, 453.8, 473.5]
    for i, line_y in enumerate(exp_ys):
        fields.append(_field_text(f"DH_Experience_{i + 1}", 16.0, line_y - 14.0, 196.0, 14.0))
        fields.append(_field_text(f"DH_ExperienceMod_{i + 1}", 216.5, line_y - 14.0, 40.5, 14.0, align=1))

    # Gold: 9 Handfuls, 9 Bags, 1 Chest
    handful_xs = [15.5, 27.8, 40.1, 52.7, 65.1, 77.9, 90.2, 102.6, 115.2]
    for i, x in enumerate(handful_xs):
        fields.append(_field_check(f"DH_GoldHandful_{i + 1}", x - 0.8, 512.5, 9.3, 9.3))
    bag_xs = [133.8 + i * 11.25 for i in range(9)]
    for i, x in enumerate(bag_xs):
        fields.append(_field_check(f"DH_GoldBag_{i + 1}", x, 510.7, 10.2, 12.8))
    fields.append(_field_check("DH_GoldChest", 242.8, 508.9, 14.7, 14.7))

    # Active Weapons: Proficiency (6 circles)
    prof_xs = [439.0, 450.4, 461.9, 473.3, 484.8, 496.2]
    for i, x in enumerate(prof_xs):
        fields.append(_field_check(f"DH_Proficiency_{i + 1}", x, 172.0, 9.9, 9.9))

    # Active Primary & Secondary Weapons
    for prefix, base_y, feat_y1, feat_y2 in [
        ("DH_PrimaryWeapon", 209.2, 234.8, 258.1),
        ("DH_SecondaryWeapon", 302.5, 328.1, 352.1),
    ]:
        fields.append(_field_text(f"{prefix}_Name", 291.0, base_y - 13.5, 123.0, 13.5))
        fields.append(_field_text(f"{prefix}_TraitRange", 417.0, base_y - 13.5, 92.5, 13.5))
        fields.append(_field_text(f"{prefix}_Damage", 512.5, base_y - 13.5, 82.0, 13.5))
        fields.append(_field_text(f"{prefix}_Feature", 291.0, feat_y1 - 13.0, 303.5, 13.0))
        fields.append(_field_text(f"{prefix}_Feature2", 328.0, feat_y2 - 13.0, 266.5, 13.0))

    # Active Armor
    fields.append(_field_text("DH_Armor_Name", 291.0, 406.5 - 13.5, 157.5, 13.5))
    fields.append(_field_text("DH_Armor_Thresholds", 451.5, 406.5 - 13.5, 80.0, 13.5, align=1))
    fields.append(_field_text("DH_Armor_BaseScore", 534.5, 406.5 - 13.5, 60.0, 13.5, align=1))
    fields.append(_field_text("DH_Armor_Feature", 291.0, 433.1 - 13.5, 303.5, 13.5))
    fields.append(_field_text("DH_Armor_Feature2", 328.0, 456.1 - 13.5, 266.5, 13.5))

    # Inventory (5 lines)
    inv_ys = [503.7, 524.0, 544.2, 564.4, 584.6]
    for i, line_y in enumerate(inv_ys):
        height = 12.5 if i == 0 else 15.0
        fields.append(_field_text(f"DH_Inventory_{i + 1}", 291.0, line_y - height, 303.5, height))

    # Inventory Weapons (2 blocks, each with Primary/Secondary checkboxes + fields)
    for idx, (cb_y, base_y, feat_y1, feat_y2) in enumerate(
        [
            (606.5, 630.5, 656.1, 678.1),
            (697.1, 721.0, 746.7, 768.7),
        ],
        start=1,
    ):
        prefix = f"DH_InvWeapon{idx}"
        fields.append(_field_check(f"{prefix}_Primary", 498.1, cb_y - 1.0, 9.2, 9.2))
        fields.append(_field_check(f"{prefix}_Secondary", 548.0, cb_y - 1.0, 9.2, 9.2))
        fields.append(_field_text(f"{prefix}_Name", 291.0, base_y - 13.5, 123.0, 13.5))
        fields.append(_field_text(f"{prefix}_TraitRange", 417.0, base_y - 13.5, 92.5, 13.5))
        fields.append(_field_text(f"{prefix}_Damage", 512.5, base_y - 13.5, 82.0, 13.5))
        fields.append(_field_text(f"{prefix}_Feature", 291.0, feat_y1 - 13.0, 303.5, 13.0))
        fields.append(_field_text(f"{prefix}_Feature2", 328.0, feat_y2 - 13.0, 266.5, 13.0))

    return fields


def build_main_extras() -> dict[str, list[dict]]:
    return {
        "blank": [
            _field_text("DH_HopeFeature", 16.0, 326.0, 240.0, 15.0),
            _field_text("DH_ClassFeature", 14.0, 566.0, 244.0, 190.0, multiline=True),
        ],
        "guardian": [
            _field_text("DH_UnstoppableDie", 214.0, 603.0, 21.6, 21.6, align=1),
        ],
        "seraph": [
            _field_text("DH_PrayerDie_1", 164.0, 584.5, 22.0, 22.0, align=1),
            _field_text("DH_PrayerDie_2", 216.0, 584.5, 22.0, 22.0, align=1),
            _field_text("DH_PrayerDie_3", 164.0, 647.5, 22.0, 22.0, align=1),
            _field_text("DH_PrayerDie_4", 216.0, 647.5, 22.0, 22.0, align=1),
            _field_text("DH_PrayerDie_5", 164.0, 710.5, 22.0, 22.0, align=1),
            _field_text("DH_PrayerDie_6", 216.0, 710.5, 22.0, 22.0, align=1),
        ],
        "wizard": [
            _field_text("DH_StrangePatterns", 201.0, 661.0, 47.5, 14.5, align=1),
        ],
    }


def build_guide_fields() -> list[dict]:
    # Guide PDF pages are 629x809 with 8.5pt bleed on all 4 sides -> subtract 8.5.
    b = 8.5
    fields: list[dict] = []

    # Background Questions (3 multiline answer boxes below each question)
    # Boxes: y=273.4..327.6, 327.8..382.8, 382.6..433.4 (in 629x809 coords).
    fields.append(_field_text("DH_Background_1", 32.0 - b, 294.0 - b, 265.0, 31.0, multiline=True))
    fields.append(_field_text("DH_Background_2", 32.0 - b, 342.0 - b, 265.0, 36.0, multiline=True))
    fields.append(_field_text("DH_Background_3", 32.0 - b, 403.0 - b, 265.0, 27.0, multiline=True))

    # Connections (3 multiline answer boxes)
    fields.append(_field_text("DH_Connection_1", 339.0 - b, 288.0 - b, 256.0, 37.0, multiline=True))
    fields.append(_field_text("DH_Connection_2", 339.0 - b, 342.0 - b, 256.0, 36.0, multiline=True))
    fields.append(_field_text("DH_Connection_3", 339.0 - b, 396.0 - b, 256.0, 33.0, multiline=True))

    # Tier 2 checkboxes (10 boxes)
    t2_rows = [
        ("Traits", [24.1, 35.5, 46.9], 555.8),
        ("HP", [35.5, 46.9], 576.0),
        ("Stress", [35.5, 46.9], 588.3),
        ("Exp", [46.9], 600.5),
        ("DomainCard", [46.9], 620.8),
        ("Evasion", [46.9], 649.5),
    ]
    for key, xs, y in t2_rows:
        for i, x in enumerate(xs, start=1):
            fields.append(_field_check(f"DH_Tier2_{key}_{i}", x - b, y - b, 9.2, 9.2))

    # Tier 3 & Tier 4 checkboxes (15 boxes each)
    for tier, x_offset in [(3, 0.0), (4, 206.8)]:
        rows = [
            ("Traits", [228.4, 239.8, 251.2], 555.8),
            ("HP", [239.8, 251.2], 576.0),
            ("Stress", [239.8, 251.2], 588.3),
            ("Exp", [251.2], 600.5),
            ("DomainCard", [251.2], 620.8),
            ("Evasion", [251.2], 649.0),
            ("Subclass", [251.2], 661.3),
            ("Proficiency", [238.9, 250.2], 686.1),
            ("Multiclass", [238.9, 250.2], 702.3),
        ]
        for key, xs, y in rows:
            for i, x in enumerate(xs, start=1):
                fields.append(
                    _field_check(
                        f"DH_Tier{tier}_{key}_{i}",
                        x + x_offset - b,
                        y - b,
                        9.2,
                        9.2,
                    )
                )

    return fields


def build_ranger_companion_fields() -> list[dict]:
    fields: list[dict] = []

    # Companion Name & Evasion
    fields.append(_field_text("DH_Comp_Name", 180.0, 62.0, 292.0, 17.5))
    fields.append(_field_text("DH_Comp_Evasion", 502.0, 27.0, 36.0, 28.0, align=1))

    # Companion Experience (5 lines + 5 modifier boxes)
    for i, line_y in enumerate([363.1, 382.8, 402.4, 422.1, 441.8], start=1):
        fields.append(_field_text(f"DH_Comp_Exp_{i}", 172.5, line_y - 14.0, 196.0, 14.0))
        fields.append(_field_text(f"DH_Comp_ExpMod_{i}", 372.5, line_y - 14.0, 41.0, 14.0, align=1))

    # Attack & Damage
    fields.append(_field_text("DH_Comp_Attack", 161.0, 521.0, 77.5, 14.5))
    fields.append(_field_text("DH_Comp_Range", 241.0, 521.0, 91.5, 14.5))
    for die, x, y in [
        ("d6", 171.9, 554.8),
        ("d8", 209.4, 555.0),
        ("d10", 245.9, 554.8),
        ("d12", 283.4, 555.0),
    ]:
        fields.append(_field_check(f"DH_Comp_Die_{die}", x, y, 8.0, 8.0))

    # Companion Stress (6 boxes)
    stress_xs = [207.5, 227.7, 247.8, 268.2, 288.3, 308.5]
    for i, x in enumerate(stress_xs, start=1):
        fields.append(_field_check(f"DH_Comp_Stress_{i}", x, 653.0, 19.3, 10.5))

    # Companion Training checkboxes
    training_rows = [
        ("Intelligent", [352.8, 365.1, 377.4], 550.0),
        ("LightInDark", [377.4], 580.7),
        ("LightInDarkHope", [458.3], 581.0),
        ("CreatureComfort", [377.4], 601.0),
        ("Armored", [377.5], 633.1),
        ("Vicious", [352.8, 365.1, 377.4], 663.4),
        ("Resilient", [352.8, 365.1, 377.4], 686.1),
        ("Bonded", [377.4], 700.2),
        ("Aware", [352.8, 365.1, 377.4], 748.4),
    ]
    for key, xs, y in training_rows:
        for i, x in enumerate(xs, start=1):
            size = 10.8 if key == "LightInDarkHope" else 10.0
            fields.append(_field_check(f"DH_Comp_Train_{key}_{i}", x, y, size, size))

    return fields


def render_page_light_and_dark(
    page: pymupdf.Page,
    out_light: Path,
    out_dark: Path,
    *,
    crop_bleed: bool = False,
) -> None:
    clip = page.rect
    if crop_bleed and (page.rect.width > PAGE_W + 1 or page.rect.height > PAGE_H + 1):
        dx = (page.rect.width - PAGE_W) / 2.0
        dy = (page.rect.height - PAGE_H) / 2.0
        clip = pymupdf.Rect(dx, dy, dx + PAGE_W, dy + PAGE_H)

    sx = PIXEL_W / clip.width
    sy = PIXEL_H / clip.height
    mat = pymupdf.Matrix(sx, sy)
    pix = page.get_pixmap(matrix=mat, clip=clip, alpha=False)
    image = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
    if image.size != (PIXEL_W, PIXEL_H):
        image = image.resize((PIXEL_W, PIXEL_H), Image.Resampling.LANCZOS)

    # Save light image as compact grayscale PNG (sheet artwork is monochrome).
    image.convert("L").save(out_light, optimize=True)

    # Generate dark artwork using the exact same algorithm as scripts/generate_dark_artwork.py.
    rgb = np.asarray(image, dtype=np.float64) / 255.0
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    luminance = linear @ np.array([0.2126, 0.7152, 0.0722])

    mask = Image.new("L", image.size)
    draw = ImageDraw.Draw(mask)
    for x0, y0, x1, y1, *_ in page.get_text("words"):
        rx0 = (x0 - clip.x0) * sx
        ry0 = (y0 - clip.y0) * sy
        rx1 = (x1 - clip.x0) * sx
        ry1 = (y1 - clip.y0) * sy
        if rx1 < 0 or ry1 < 0 or rx0 > PIXEL_W or ry0 > PIXEL_H:
            continue
        draw.rectangle((rx0, ry0, rx1, ry1), fill=255)
    labels = np.asarray(mask, dtype=np.float64)[..., None] / 255.0
    ink = np.array(ORNAMENT) * (1.0 - labels) + np.array(INK) * labels
    pixels = np.rint(ink + luminance[..., None] * (np.array(PAPER) - ink))
    dark_img = Image.fromarray(pixels.clip(0, 255).astype(np.uint8))
    dark_img.quantize(colors=64, method=Image.Quantize.MEDIANCUT).save(
        out_dark, optimize=True
    )


def render_debug_overlay(light_png: Path, fields: list[dict], out_path: Path) -> None:
    im = Image.open(light_png).convert("RGBA")
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    sx = im.width / PAGE_W
    sy = im.height / PAGE_H
    for f in fields:
        x0, y0 = f["x"] * sx, f["y"] * sy
        x1, y1 = (f["x"] + f["w"]) * sx, (f["y"] + f["h"]) * sy
        color = (0, 120, 255, 85) if f["type"] == "text" else (230, 50, 50, 110)
        outline = (0, 70, 200, 220) if f["type"] == "text" else (190, 0, 0, 230)
        draw.rectangle((x0, y0, x1, y1), fill=color, outline=outline, width=2)
    merged = Image.alpha_composite(im, overlay).convert("RGB")
    merged.resize((850, 1100), Image.Resampling.LANCZOS).save(out_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sheets_dir", type=Path)
    parser.add_argument("--debug-dir", type=Path, default=None)
    parser.add_argument("--fields-only", action="store_true")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if not args.fields_only:
        for slug, filename in CLASSES:
            doc = pymupdf.open(args.sheets_dir / filename)
            render_page_light_and_dark(
                doc[0],
                OUT_DIR / f"{slug}-p1.png",
                OUT_DIR / f"{slug}-p1-dark.png",
            )
            print(f"Rendered {slug}-p1")
            if slug == "druid":
                render_page_light_and_dark(
                    doc[1],
                    OUT_DIR / "druid-beastform-1.png",
                    OUT_DIR / "druid-beastform-1-dark.png",
                )
                render_page_light_and_dark(
                    doc[2],
                    OUT_DIR / "druid-beastform-2.png",
                    OUT_DIR / "druid-beastform-2-dark.png",
                )
                print("Rendered druid-beastform-1 & 2")
            if slug == "ranger":
                render_page_light_and_dark(
                    doc[1],
                    OUT_DIR / "ranger-companion.png",
                    OUT_DIR / "ranger-companion-dark.png",
                )
                print("Rendered ranger-companion")
            if slug != "blank":
                render_page_light_and_dark(
                    doc[-1],
                    OUT_DIR / f"{slug}-guide.png",
                    OUT_DIR / f"{slug}-guide-dark.png",
                    crop_bleed=True,
                )
                print(f"Rendered {slug}-guide")
            doc.close()

    main_common = build_main_common_fields()
    main_extras = build_main_extras()
    guide = build_guide_fields()
    ranger_companion = build_ranger_companion_fields()

    payload = {
        "mainCommon": main_common,
        "mainExtras": main_extras,
        "guide": guide,
        "rangerCompanion": ranger_companion,
    }
    fields_path = OUT_DIR / "fields.json"
    fields_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"Wrote {fields_path}: mainCommon={len(main_common)}, "
        f"guide={len(guide)}, rangerCompanion={len(ranger_companion)}"
    )

    if args.debug_dir is not None:
        args.debug_dir.mkdir(parents=True, exist_ok=True)
        render_debug_overlay(OUT_DIR / "bard-p1.png", main_common, args.debug_dir / "debug_bard_p1.png")
        render_debug_overlay(OUT_DIR / "bard-guide.png", guide, args.debug_dir / "debug_bard_guide.png")
        render_debug_overlay(
            OUT_DIR / "blank-p1.png",
            main_common + main_extras["blank"],
            args.debug_dir / "debug_blank_p1.png",
        )
        render_debug_overlay(
            OUT_DIR / "seraph-p1.png",
            main_common + main_extras["seraph"],
            args.debug_dir / "debug_seraph_p1.png",
        )
        render_debug_overlay(
            OUT_DIR / "ranger-companion.png",
            ranger_companion,
            args.debug_dir / "debug_ranger_companion.png",
        )
        print(f"Wrote debug overlays to {args.debug_dir}")


if __name__ == "__main__":
    main()
