#!/usr/bin/env python3
"""
Creates the per-target asset catalogs (app icon, accent colour, widget background).

The cats themselves are kaomoji rendered as text at runtime -- see Shared/Mood.swift --
so there is no cat art in the asset catalogs at all. The only image in the whole project
is the app icon, which iOS requires as a raster, and which this script draws from the
same happy face the app shows: (=^ω^=)

The icon is explicitly a placeholder (spec section 17, task 6). It exists so the project
builds without an asset-catalog warning and so App Store Connect validation has something
to chew on during Phase 0-3.

Usage:  python3 Tools/make_catalogs.py
"""

from __future__ import annotations

import json
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent

ACCENT_LIGHT = (0.910, 0.514, 0.235)   # warm amber
ACCENT_DARK = (1.000, 0.655, 0.369)
WIDGET_BG_LIGHT = (0.965, 0.961, 0.949)
WIDGET_BG_DARK = (0.110, 0.106, 0.098)

# Must match Mood.happy.face in Shared/Mood.swift.
ICON_FACE = "(=^ω^=)"

# DejaVu covers every character in the face set: ASCII, Latin-1, Greek omega and the
# two Misc Symbols eyes. Verified rather than assumed -- see the note in Mood.swift.
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
]

INFO = {"author": "xcode", "version": 1}


def colorset(light: tuple[float, float, float], dark: tuple[float, float, float]) -> dict:
    def component(rgb, appearances=None):
        entry = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "alpha": "1.000",
                    "red": f"{rgb[0]:.3f}",
                    "green": f"{rgb[1]:.3f}",
                    "blue": f"{rgb[2]:.3f}",
                },
            },
            "idiom": "universal",
        }
        if appearances:
            entry["appearances"] = appearances
        return entry

    return {
        "colors": [
            component(light),
            component(dark, [{"appearance": "luminosity", "value": "dark"}]),
        ],
        "info": INFO,
    }


def write_json(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if pathlib.Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    raise SystemExit(f"no usable font found; tried {FONT_CANDIDATES}")


def render_app_icon(destination: pathlib.Path) -> None:
    """Amber field, white face, no alpha channel (an App Store requirement)."""
    canvas = 1024
    target_width = 840

    # Binary search the font size that makes the face the width we want, rather than
    # hardcoding a number that breaks the moment the face changes.
    low, high, best = 10, 400, 10
    while low <= high:
        mid = (low + high) // 2
        box = load_font(mid).getbbox(ICON_FACE)
        if box[2] - box[0] <= target_width:
            best, low = mid, mid + 1
        else:
            high = mid - 1

    font = load_font(best)
    icon = Image.new("RGB", (canvas, canvas), tuple(int(c * 255) for c in ACCENT_LIGHT))
    draw = ImageDraw.Draw(icon)

    left, top, right, bottom = draw.textbbox((0, 0), ICON_FACE, font=font)
    draw.text(
        ((canvas - (right - left)) / 2 - left, (canvas - (bottom - top)) / 2 - top),
        ICON_FACE,
        font=font,
        fill=(255, 255, 255),
    )

    destination.parent.mkdir(parents=True, exist_ok=True)
    icon.save(destination)
    print(f"  app icon: {ICON_FACE} at {best}pt, {canvas}x{canvas} RGB")


def build() -> None:
    app = ROOT / "MoodCats" / "Assets.xcassets"
    widget = ROOT / "MoodCatsWidget" / "Assets.xcassets"

    for catalog in (app, widget):
        write_json(catalog / "Contents.json", {"info": INFO})
        write_json(catalog / "AccentColor.colorset" / "Contents.json",
                   colorset(ACCENT_LIGHT, ACCENT_DARK))

    write_json(widget / "WidgetBackground.colorset" / "Contents.json",
               colorset(WIDGET_BG_LIGHT, WIDGET_BG_DARK))

    write_json(app / "AppIcon.appiconset" / "Contents.json", {
        "images": [{
            "filename": "AppIcon.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }],
        "info": INFO,
    })
    render_app_icon(app / "AppIcon.appiconset" / "AppIcon.png")

    print(f"  wrote {app.relative_to(ROOT)} and {widget.relative_to(ROOT)}")


if __name__ == "__main__":
    build()
