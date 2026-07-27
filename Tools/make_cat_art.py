#!/usr/bin/env python3
"""
Generates the 9 MoodCats assets: 8 moods plus one neutral placeholder.

The spec is emphatic that these must NOT be 8 independent generations -- eight separate
images produce eight different line weights, head shapes and eye styles, and the set
looks like a ransom note. So this script does the correct thing structurally: there is
exactly ONE body (ears, head, cheeks, nose, whiskers, torso, tail, paws), defined once
below, and each mood overrides only the FACE. Same silhouette, same stroke width, same
corner radii, every time, by construction rather than by discipline.

Output per mood:
    Art/svg/cat_<key>.svg                      -- editable source
    Shared/CatAssets.xcassets/cat_<key>.imageset/cat_<key>.pdf
    Art/preview/cat_<key>.png                  -- for eyeballing only, not shipped

The asset catalog entries are written with "preserves-vector-representation": true and
"template-rendering-intent": "template", which is what makes the art crisp at every
widget size and free in Lock Screen vibrant mode.

These are placeholder-grade but production-shaped. Replacing them means dropping new
PDFs into the imagesets with the same names -- no code changes.

Usage:  python3 Tools/make_cat_art.py
"""

from __future__ import annotations

import json
import os
import pathlib

import cairosvg

ROOT = pathlib.Path(__file__).resolve().parent.parent
SVG_DIR = ROOT / "Art" / "svg"
PNG_DIR = ROOT / "Art" / "preview"
ASSETS = ROOT / "Shared" / "CatAssets.xcassets"

SIZE = 220
STROKE = 7.5          # one line weight for the whole set, no exceptions
STROKE_THIN = 5.5     # whiskers and incidental detail only

# --------------------------------------------------------------------------------------
# THE BODY. Drawn once, shared by all 9 assets.
# --------------------------------------------------------------------------------------

BODY = f"""
  <!-- ears -->
  <path d="M 62 62 L 50 18 L 96 42" />
  <path d="M 158 62 L 170 18 L 124 42" />
  <!-- head -->
  <ellipse cx="110" cy="86" rx="62" ry="55" />
  <!-- torso -->
  <path d="M 66 128 C 48 158 46 192 60 203" />
  <path d="M 154 128 C 172 158 174 192 160 203" />
  <path d="M 60 203 L 160 203" />
  <!-- front paws -->
  <path d="M 82 203 C 82 190 98 190 98 203" />
  <path d="M 122 203 C 122 190 138 190 138 203" />
  <!-- tail -->
  <path d="M 160 196 C 196 196 204 168 188 152 C 180 144 168 148 170 158" />
  <!-- nose -->
  <path d="M 103 99 L 117 99 L 110 107 Z" />
"""

WHISKERS = f"""
  <g stroke-width="{STROKE_THIN}">
    <path d="M 44 92 L 76 96" />
    <path d="M 44 106 L 76 104" />
    <path d="M 176 92 L 144 96" />
    <path d="M 176 106 L 144 104" />
  </g>
"""

# --------------------------------------------------------------------------------------
# THE FACES. Eyes and mouth only, plus at most one small mood token.
# Eye centres are always (86, 82) and (134, 82); the mouth always sits at y ~ 112.
# --------------------------------------------------------------------------------------

FACES: dict[str, str] = {
    # ^ ^ and a wide smile
    "happy": """
  <path d="M 74 86 C 80 74 92 74 98 86" />
  <path d="M 122 86 C 128 74 140 74 146 86" />
  <path d="M 92 110 C 100 122 120 122 128 110" />
""",
    # drooping eyes, frown, one tear
    "sad": """
  <path d="M 74 80 C 80 92 92 92 98 80" />
  <path d="M 122 80 C 128 92 140 92 146 80" />
  <path d="M 94 122 C 102 110 118 110 126 122" />
  <path d="M 79 100 C 73 112 73 120 79 120 C 85 120 85 112 79 100 Z" />
""",
    # closed eyes, tiny mouth, drifting z's
    "sleepy": """
  <path d="M 74 84 C 82 92 92 92 98 84" />
  <path d="M 122 84 C 130 92 140 92 146 84" />
  <path d="M 100 113 C 106 119 114 119 120 113" />
  <g stroke-width="5.5">
    <path d="M 174 44 L 192 44 L 174 62 L 192 62" />
    <path d="M 196 16 L 210 16 L 196 32 L 210 32" />
  </g>
""",
    # angled brows, hard eyes, flat mouth
    "angry": """
  <path d="M 68 62 L 100 76" />
  <path d="M 152 62 L 120 76" />
  <path d="M 76 88 L 96 88" />
  <path d="M 124 88 L 144 88" />
  <path d="M 96 116 L 124 116" />
""",
    # wide eyes, wavy mouth, sweat drop
    "anxious": """
  <ellipse cx="86" cy="83" rx="12" ry="14" />
  <ellipse cx="134" cy="83" rx="12" ry="14" />
  <path d="M 92 114 C 97 108 103 120 110 114 C 117 108 123 120 128 114" />
  <path d="M 180 58 C 173 70 173 79 180 79 C 187 79 187 70 180 58 Z" />
""",
    # sunglasses and a small smile
    "chill": """
  <path d="M 66 72 L 154 72" />
  <rect x="66" y="72" width="38" height="26" rx="10" />
  <rect x="116" y="72" width="38" height="26" rx="10" />
  <path d="M 104 80 L 116 80" />
  <path d="M 98 112 C 104 120 116 120 122 112" />
""",
    # star eyes, open grin
    "excited": """
  <path d="M 86 68 L 91 80 L 103 82 L 91 88 L 86 100 L 81 88 L 69 82 L 81 80 Z" />
  <path d="M 134 68 L 139 80 L 151 82 L 139 88 L 134 100 L 129 88 L 117 82 L 129 80 Z" />
  <path d="M 90 108 C 98 126 122 126 130 108 Z" />
""",
    # eyes down, open mouth, one drip
    "hungry": """
  <circle cx="86" cy="84" r="8" />
  <circle cx="134" cy="84" r="8" />
  <path d="M 94 108 C 100 104 120 104 126 108 C 126 124 94 124 94 108 Z" />
  <path d="M 110 126 C 105 134 105 141 110 141 C 115 141 115 134 110 126 Z" />
""",
    # neutral -- the placeholder, "friend left", and gallery cat
    "unknown": """
  <circle cx="86" cy="84" r="7" />
  <circle cx="134" cy="84" r="7" />
  <path d="M 98 114 L 122 114" />
""",
}

SVG_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">
  <title>MoodCats -- {key}</title>
  <g fill="none" stroke="#000000" stroke-width="{stroke}"
     stroke-linecap="round" stroke-linejoin="round">
{body}{whiskers}{face}  </g>
</svg>
"""

CONTENTS_IMAGESET = {
    "images": [
        {
            "filename": "",
            "idiom": "universal",
        }
    ],
    "info": {"author": "xcode", "version": 1},
    "properties": {
        # Crisp at every widget size instead of upscaling a rasterised snapshot.
        "preserves-vector-representation": True,
        # Lets the art take .foregroundStyle, and makes Lock Screen vibrant mode free.
        "template-rendering-intent": "template",
    },
}

CONTENTS_ROOT = {"info": {"author": "xcode", "version": 1}}


def build() -> None:
    for directory in (SVG_DIR, PNG_DIR, ASSETS):
        directory.mkdir(parents=True, exist_ok=True)

    (ASSETS / "Contents.json").write_text(json.dumps(CONTENTS_ROOT, indent=2) + "\n")

    for key, face in FACES.items():
        name = f"cat_{key}"
        svg = SVG_TEMPLATE.format(
            size=SIZE, stroke=STROKE, key=key, body=BODY, whiskers=WHISKERS, face=face
        )

        svg_path = SVG_DIR / f"{name}.svg"
        svg_path.write_text(svg)

        imageset = ASSETS / f"{name}.imageset"
        imageset.mkdir(parents=True, exist_ok=True)

        pdf_path = imageset / f"{name}.pdf"
        cairosvg.svg2pdf(bytestring=svg.encode(), write_to=str(pdf_path),
                         output_width=SIZE, output_height=SIZE)

        contents = json.loads(json.dumps(CONTENTS_IMAGESET))
        contents["images"][0]["filename"] = f"{name}.pdf"
        (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

        cairosvg.svg2png(bytestring=svg.encode(), write_to=str(PNG_DIR / f"{name}.png"),
                         output_width=440, output_height=440, background_color="white")

        print(f"  {name}: {os.path.getsize(pdf_path):>6} bytes pdf")

    print(f"\n{len(FACES)} assets written to {ASSETS.relative_to(ROOT)}")


if __name__ == "__main__":
    build()
