#!/usr/bin/env python3
"""
Creates the per-target asset catalogs (app icon, accent colour, widget background) and
renders a placeholder 1024x1024 app icon from the same cat art the widget uses.

The icon is explicitly a placeholder -- shipping needs a real one (spec section 17,
task 6). It exists so the project builds without an asset-catalog warning and so
App Store Connect validation has something to chew on during Phase 0-3.

Usage:  python3 Tools/make_catalogs.py
"""

from __future__ import annotations

import json
import pathlib

import cairosvg
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent

ACCENT_LIGHT = (0.910, 0.514, 0.235)   # warm amber
ACCENT_DARK = (1.000, 0.655, 0.369)
WIDGET_BG_LIGHT = (0.965, 0.961, 0.949)
WIDGET_BG_DARK = (0.110, 0.106, 0.098)

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


def render_app_icon(destination: pathlib.Path) -> None:
    """Amber field, white cat, no transparency and no alpha channel (App Store rule)."""
    svg = (ROOT / "Art" / "svg" / "cat_happy.svg").read_text()
    svg = svg.replace('stroke="#000000"', 'stroke="#FFFFFF"')

    cat_png = ROOT / "Art" / "preview" / "_icon_cat.png"
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(cat_png),
                     output_width=760, output_height=760)

    background = tuple(int(c * 255) for c in ACCENT_LIGHT)
    icon = Image.new("RGB", (1024, 1024), background)
    cat = Image.open(cat_png).convert("RGBA")
    icon.paste(cat, ((1024 - 760) // 2, (1024 - 760) // 2), cat)

    destination.parent.mkdir(parents=True, exist_ok=True)
    icon.save(destination)
    cat_png.unlink(missing_ok=True)


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

    print(f"wrote {app.relative_to(ROOT)} and {widget.relative_to(ROOT)}")


if __name__ == "__main__":
    build()
