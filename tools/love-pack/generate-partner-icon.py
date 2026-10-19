#!/usr/bin/env python3
"""Draw the partner theme's app icon, "Srdce ninji" (add-partner-love-theme D4).

Original art, drawn procedurally -- no official Naruto artwork, logo or
font: a big white heart with a swirl cut out of it (a spiral, the shape of
a fish-cake's swirl) and a small white four-point shuriken in the lower
right, on a full-bleed diagonal gradient from love pink (bottom left)
through rose to Naruto orange (top right) -- the theme's own colours.

Drawn at 4096 px and downsampled (anti-aliasing without a vector renderer),
written as the alternate icon pair iOS uses:

    ios/GarminFood/AppIcons/AppIcon-Partner@2x.png   120 px
    ios/GarminFood/AppIcons/AppIcon-Partner@3x.png   180 px

Usage (from the repo root; needs Pillow):
    python tools/love-pack/generate-partner-icon.py           # write both
    python tools/love-pack/generate-partner-icon.py --check   # exit 1 if they differ
"""

import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ios" / "GarminFood" / "AppIcons"
SIZE = 1024
SUPER = 4

# Bottom-left -> middle -> top-right gradient stops (the theme's palette).
STOPS = [(0xE8, 0x45, 0x7A), (0xF0, 0x5E, 0x5C), (0xF7, 0x84, 0x1E)]
WHITE = (255, 255, 255)
CREAM = (255, 246, 241)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(t):
    if t < 0.5:
        return lerp(STOPS[0], STOPS[1], t * 2)
    return lerp(STOPS[1], STOPS[2], (t - 0.5) * 2)


def in_heart(x, y):
    """The classic implicit heart, (x² + y² - 1)³ - x² y³ <= 0, in unit space."""
    q = x * x + y * y - 1
    return q * q * q - x * x * y * y * y <= 0


def in_swirl(x, y):
    """A thick Archimedean spiral (about 2.3 turns) centred in the heart."""
    r = math.hypot(x, y)
    if r > 0.62 or r < 0.02:
        return False
    theta = math.atan2(y, x)
    pitch = 0.17          # distance between turns
    width = 0.055         # stroke half-width
    for turn in range(0, 4):
        rr = pitch * (theta / (2 * math.pi) + turn)
        if rr > 0 and abs(r - rr) < width:
            return True
    return False


def in_shuriken(x, y, cx, cy, size):
    """A four-point star (the shuriken) with a round hole."""
    dx, dy = x - cx, y - cy
    r = math.hypot(dx, dy)
    if r < size * 0.16:
        return False
    angle = math.atan2(dy, dx) - math.radians(15)
    # Radius of a 4-point star at this angle: sharp points, deep valleys.
    k = abs(math.cos(2 * angle))
    edge = size * (0.30 + 0.70 * k ** 4)
    return r <= edge


def render():
    n = SIZE * SUPER
    img = Image.new("RGB", (n, n))
    px = img.load()
    for j in range(n):
        v = j / (n - 1)
        for i in range(n):
            u = i / (n - 1)
            t = (u + (1 - v)) / 2
            color = gradient(t)
            # Heart: centred slightly high, ~62% of the icon wide.
            hx = (u - 0.5) / 0.30
            hy = -(v - 0.47) / 0.30
            if in_heart(hx, hy):
                # Swirl centre a little below the heart's middle.
                if in_swirl(hx * 0.96, hy + 0.12):
                    color = gradient(t)
                else:
                    color = WHITE
            elif in_shuriken(u, v, 0.80, 0.80, 0.12):
                color = CREAM
            px[i, j] = color
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    check = "--check" in sys.argv
    full = render()
    targets = {"AppIcon-Partner@2x.png": 120, "AppIcon-Partner@3x.png": 180}
    differs = False
    for name, size in targets.items():
        icon = full.resize((size, size), Image.LANCZOS)
        path = OUT / name
        if check:
            if not path.exists() or list(Image.open(path).convert("RGB").getdata()) != list(icon.getdata()):
                print(f"{path.relative_to(ROOT)} is out of date")
                differs = True
        else:
            icon.save(path, optimize=True)
            print(f"wrote {path.relative_to(ROOT)}")
    if check:
        sys.exit(1 if differs else 0)


if __name__ == "__main__":
    main()
