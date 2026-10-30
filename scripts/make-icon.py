#!/usr/bin/env python3
"""Draw Midtrack's app icon and build Resources/AppIcon.icns.

The mark is a waveform split by an orange midpoint marker: a track, and the
place Midtrack sends it. Everything is drawn at 4x and downsampled so the small
menu bar / Dock sizes stay clean.

    python3 scripts/make-icon.py
"""

from __future__ import annotations

import math
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024
SUPERSAMPLE = 4
HI = SIZE * SUPERSAMPLE
ICONSET = ROOT / "build" / "AppIcon.iconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"
PREVIEW = ROOT / "docs" / "icon.png"

# macOS Big Sur-and-later icon proportions: an 824 x 824 rounded square on a
# 1024 canvas, with the remaining margin left for the shadow.
ART_INSET = 100
ART_SIZE = SIZE - ART_INSET * 2
ART_RADIUS = 185


def rounded_mask() -> Image.Image:
    hi = Image.new("L", (HI, HI), 0)
    draw = ImageDraw.Draw(hi)
    inset = ART_INSET * SUPERSAMPLE
    draw.rounded_rectangle(
        (inset, inset, HI - inset, HI - inset),
        radius=ART_RADIUS * SUPERSAMPLE,
        fill=255,
    )
    return hi.resize((SIZE, SIZE), Image.LANCZOS)


def vertical_gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (1, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        pixels[0, y] = tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    return image.resize((SIZE, SIZE), Image.BILINEAR)


def radial_glow(center: tuple[float, float], radius: float, color: tuple[int, int, int],
                strength: float) -> Image.Image:
    """A soft radial light. `center` is in 0...1 icon coordinates."""
    size = 512
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    cx, cy = center[0] * size, center[1] * size
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - cx, y - cy)
            falloff = max(0.0, 1.0 - distance / (radius * size))
            alpha = round(255 * strength * falloff * falloff)
            if alpha:
                pixels[x, y] = (*color, alpha)
    return image.resize((SIZE, SIZE), Image.BICUBIC)


def draw_bars() -> Image.Image:
    """A mirrored waveform of rounded bars, returned at icon resolution."""
    hi = Image.new("L", (HI, HI), 0)
    draw = ImageDraw.Draw(hi)
    heights = [96, 188, 292, 408, 292, 188, 96]
    bar_width = 46
    gap = 25
    total = len(heights) * bar_width + (len(heights) - 1) * gap
    left = (SIZE - total) / 2
    for index, height in enumerate(heights):
        x = (left + index * (bar_width + gap)) * SUPERSAMPLE
        half = height * SUPERSAMPLE / 2
        draw.rounded_rectangle(
            (x, HI / 2 - half, x + bar_width * SUPERSAMPLE, HI / 2 + half),
            radius=bar_width * SUPERSAMPLE / 2,
            fill=255,
        )
    return hi.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> int:
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # The square itself: deep navy to ink, with a cool glow in the top-left.
    background = vertical_gradient((17, 22, 45), (9, 12, 26)).convert("RGBA")
    background.alpha_composite(radial_glow((0.22, 0.18), 0.72, (20, 170, 160), 0.30))
    background.alpha_composite(radial_glow((0.82, 0.86), 0.60, (74, 94, 190), 0.26))
    background.putalpha(rounded_mask())
    icon.alpha_composite(background)

    # A soft drop shadow under the tile.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (ART_INSET, ART_INSET + 18, SIZE - ART_INSET, SIZE - ART_INSET + 18),
        radius=ART_RADIUS,
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    composed = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    composed.alpha_composite(shadow)
    composed.alpha_composite(icon)
    icon = composed

    # Inner highlight along the top edge of the tile.
    rim_hi = Image.new("RGBA", (HI, HI), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim_hi)
    rim_draw.rounded_rectangle(
        (ART_INSET * SUPERSAMPLE, ART_INSET * SUPERSAMPLE,
         HI - ART_INSET * SUPERSAMPLE, HI - ART_INSET * SUPERSAMPLE),
        radius=ART_RADIUS * SUPERSAMPLE,
        outline=(255, 255, 255, 34),
        width=3 * SUPERSAMPLE,
    )
    icon.alpha_composite(rim_hi.resize((SIZE, SIZE), Image.LANCZOS))

    # The waveform: white at the crest, sea-glass at the base.
    bars = draw_bars()
    bar_gradient = vertical_gradient((250, 255, 255), (104, 226, 214)).convert("RGBA")
    icon.paste(bar_gradient, (0, 0), bars)

    # The midpoint marker: a warm, glowing line exactly at 50%.
    marker_width = 22
    marker_left = SIZE / 2 - marker_width / 2
    marker_top, marker_bottom = 236, 788

    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.rounded_rectangle(
        (marker_left - 8, marker_top, marker_left + marker_width + 8, marker_bottom),
        radius=marker_width,
        fill=(255, 138, 40, 190),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(20))
    icon.alpha_composite(glow)

    marker = Image.new("RGBA", (HI, HI), (0, 0, 0, 0))
    marker_draw = ImageDraw.Draw(marker)
    marker_draw.rounded_rectangle(
        (marker_left * SUPERSAMPLE, marker_top * SUPERSAMPLE,
         (marker_left + marker_width) * SUPERSAMPLE, marker_bottom * SUPERSAMPLE),
        radius=marker_width * SUPERSAMPLE / 2,
        fill=(255, 166, 77, 255),
    )
    marker_draw.rounded_rectangle(
        (marker_left * SUPERSAMPLE + 3 * SUPERSAMPLE, marker_top * SUPERSAMPLE + 6 * SUPERSAMPLE,
         marker_left * SUPERSAMPLE + 7 * SUPERSAMPLE, marker_bottom * SUPERSAMPLE - 6 * SUPERSAMPLE),
        radius=2 * SUPERSAMPLE,
        fill=(255, 236, 205, 170),
    )
    icon.alpha_composite(marker.resize((SIZE, SIZE), Image.LANCZOS))

    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    variants = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in variants.items():
        icon.resize((size, size), Image.LANCZOS).save(ICONSET / name)

    ICNS.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)

    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    icon.save(PREVIEW)
    print(f"wrote {ICNS.relative_to(ROOT)} and {PREVIEW.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
