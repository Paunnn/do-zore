"""Key art, boot splash and app icon: the road from the birtija to the splav, up through the night.

The venues are the game's own 3D renders (client/assets/ui/venues/*.png, made by
client/tests/render_venue_cards.gd) set along a lamp-lit road; the lettering uses the game's
fonts. Writes client/design/key_art.svg and the icon layers; rasterise them with a renderer that
loads web fonts (Playwright Chromium, see client/design/README.md):

    python tools/art/build_key_art.py
"""

from __future__ import annotations

import base64
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "client/assets/fonts"
DESIGN = ROOT / "client/design"
RENDERS = ROOT / "client/assets/ui/venues"

W, H = 1080, 1920
GOLD = "#ffbf2e"
GOLD_LIGHT = "#ffe08a"
CREAM = "#f6eedc"
RED = "#c0322c"
NIGHT = "#0e1428"
OUTLINE = "#3a1d0e"
LAMP = "#ffd36a"
VENUES = [("birtija", "Birtija"), ("kafana", "Kafana"), ("restoran", "Restoran"), ("splav", "Splav")]


def font_faces() -> str:
    return (f'<style>@font-face{{font-family:"Shrikhand";src:url("{FONTS / "Shrikhand-Regular.ttf"}")}}'
            f'@font-face{{font-family:"Titan One";src:url("{FONTS / "TitanOne-Regular.ttf"}")}}</style>')


def image(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def outlined_text(x: float, y: float, text: str, family: str, size: int, fill: str, stroke: str = OUTLINE, width: float = 10, anchor: str = "middle", extra: str = "") -> str:
    shadow = (f'<text x="{x}" y="{y + size * 0.06:.0f}" text-anchor="{anchor}" font-family="{family}" font-size="{size}" fill="{stroke}" '
              f'stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" opacity="0.6"{extra}>{text}</text>')
    body = (f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="{family}" font-size="{size}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" paint-order="stroke"{extra}>{text}</text>')
    return shadow + body


def checker_border(parts: list, inset: float, band: float) -> None:
    """A tablecloth trim around the frame: red and cream checks between a dark and a gold line."""
    x0, y0, x1, y1 = inset, inset, W - inset, H - inset
    cell = band / 2.0
    for row in range(2):
        for top in (True, False):
            y = (y0 if top else y1 - band) + row * cell
            k, x = 0, x0
            while x < x1 - 0.1:
                parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{min(cell, x1 - x):.1f}" height="{cell:.1f}" fill="{RED if (k + row) % 2 == 0 else CREAM}"/>')
                x += cell
                k += 1
        for left in (True, False):
            x = (x0 if left else x1 - band) + row * cell
            k, y = 0, y0 + band
            while y < y1 - band - 0.1:
                parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{cell:.1f}" height="{min(cell, y1 - band - y):.1f}" fill="{RED if (k + row) % 2 == 0 else CREAM}"/>')
                y += cell
                k += 1
    parts.append(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="none" stroke="{OUTLINE}" stroke-width="5"/>')
    parts.append(f'<rect x="{x0 + band}" y="{y0 + band}" width="{x1 - x0 - 2 * band}" height="{y1 - y0 - 2 * band}" fill="none" stroke="{GOLD}" stroke-width="4"/>')


def main() -> None:
    DESIGN.mkdir(parents=True, exist_ok=True)
    rng = random.Random(1912)
    defs = [
        '<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#f0a86a"/><stop offset="0.08" stop-color="#c97a6a"/><stop offset="0.22" stop-color="#4a3f6e"/>'
        f'<stop offset="0.48" stop-color="#1d2a52"/><stop offset="1" stop-color="{NIGHT}"/></linearGradient>',
        '<linearGradient id="river" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a4a78"/><stop offset="1" stop-color="#14264a"/></linearGradient>',
        f'<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{GOLD_LIGHT}"/><stop offset="0.6" stop-color="{GOLD}"/><stop offset="1" stop-color="#f09a1c"/></linearGradient>',
        f'<radialGradient id="lamp"><stop offset="0" stop-color="{LAMP}" stop-opacity="0.5"/><stop offset="1" stop-color="{LAMP}" stop-opacity="0"/></radialGradient>',
    ]
    parts = [f'<rect width="{W}" height="{H}" fill="url(#sky)"/>']
    for gy in range(64):
        for gx in range(34):
            y = 60 + gy * 28 + rng.uniform(-10, 10)
            x = 40 + gx * 30 + rng.uniform(-12, 12)
            if rng.random() < 0.26 * min(1.0, max(0.0, (y - 240) / 900)):
                r = rng.choice((0.9, 1.1, 1.3, 1.8)) if rng.random() < 0.92 else 2.6
                parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{CREAM}" opacity="{rng.uniform(0.35, 0.9):.2f}"/>')
    # The river near the top, where the splav waits.
    parts.append('<path d="M0 668 Q160 628 300 656 T600 646 T880 628 T1080 640 L1080 720 L0 720 Z" fill="#2a2f55" opacity="0.9"/>')
    parts.append('<path d="M0 700 C220 676 420 716 640 694 S960 678 1080 690 L1080 1004 C900 1024 700 990 520 1012 S180 1034 0 1016 Z" fill="url(#river)"/>')
    for _ in range(30):
        x, y, w = rng.uniform(70, 1010), rng.uniform(724, 990), rng.uniform(18, 46)
        parts.append(f'<path d="M{x:.1f} {y:.1f} l{w:.1f} 0" stroke="#5a7ab0" stroke-width="2" stroke-linecap="round" opacity="0.55"/>')
    # Venues zig-zag up the frame; the lamp-lit road links them.
    stops = {"birtija": (300, 1580, 460), "kafana": (780, 1320, 470), "restoran": (300, 1060, 480), "splav": (770, 800, 500)}
    road = [(330, 1700), (540, 1520), (720, 1440), (560, 1230), (330, 1170), (480, 960), (720, 890)]
    d = f"M{road[0][0]} {road[0][1]} " + " ".join(f"Q{(a[0] + b[0]) / 2:.0f} {(a[1] + b[1]) / 2 - 30:.0f} {b[0]} {b[1]}" for a, b in zip(road, road[1:]))
    parts.append(f'<path d="{d}" fill="none" stroke="{GOLD}" stroke-width="3" stroke-dasharray="2 22" stroke-linecap="round" opacity="0.95"/>')
    parts.append(f'<path d="{d}" fill="none" stroke="{LAMP}" stroke-width="11" stroke-dasharray="2 94" stroke-dashoffset="-46" stroke-linecap="round" opacity="0.9"/>')
    for key, _ in VENUES:
        x, y, width = stops[key]
        height = width * 0.75
        parts.append(f'<circle cx="{x}" cy="{y}" r="{width * 0.42:.0f}" fill="url(#lamp)"/>')
        parts.append(f'<image href="{image(RENDERS / (key + ".png"))}" x="{x - width / 2:.0f}" y="{y - height / 2:.0f}" width="{width}" height="{height:.0f}"/>')
    for numeral, (key, label) in zip(("I", "II", "III", "IV"), VENUES):
        x, y, width = stops[key]
        parts.append(outlined_text(x, y + width * 0.75 / 2 + 24, f'<tspan fill="{GOLD}" font-size="32">{numeral} </tspan>{label}', "Titan One", 44, "#ffffff", OUTLINE, 9))
    parts.append(outlined_text(W / 2, 330, "Do zore", "Shrikhand", 196, "url(#gold)", OUTLINE, 16))
    parts.append(outlined_text(W / 2, 420, "od birtije do splava", "Titan One", 52, "#ffffff", OUTLINE, 10))
    parts.append(outlined_text(W / 2, 1830, "JOŠ JEDNA PESMA", "Titan One", 38, GOLD, OUTLINE, 9, extra=' letter-spacing="6"'))
    checker_border(parts, 22, 28)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{font_faces()}'
           f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')
    (DESIGN / "key_art.svg").write_text(svg, encoding="utf-8")
    print("key art written")


def icon_layers() -> tuple:
    """App icon as (background, foreground) SVG fragments on a 1024 canvas.

    The foreground keeps inside the central 66% so adaptive-icon masks never clip it."""
    size = 1024
    c = size / 2
    rng = random.Random(7)
    back = ['<radialGradient id="ibg" cx="0.5" cy="0.32" r="0.8"><stop offset="0" stop-color="#2c3f72"/>'
            f'<stop offset="1" stop-color="{NIGHT}"/></radialGradient>',
            f'<rect width="{size}" height="{size}" fill="url(#ibg)"/>']
    for _ in range(70):
        x, y = rng.uniform(20, size - 20), rng.uniform(20, size - 20)
        if math.hypot(x - c, y - c) > 360:
            back.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{rng.choice((2, 2.5, 3.5))}" fill="{CREAM}" opacity="{rng.uniform(0.3, 0.8):.2f}"/>')
    ring = 310
    fore = [f'<linearGradient id="igold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{GOLD_LIGHT}"/>'
            f'<stop offset="0.6" stop-color="{GOLD}"/><stop offset="1" stop-color="#f09a1c"/></linearGradient>',
            f'<radialGradient id="iglow"><stop offset="0" stop-color="{LAMP}" stop-opacity="0.35"/><stop offset="1" stop-color="{LAMP}" stop-opacity="0"/></radialGradient>',
            f'<circle cx="{c}" cy="{c}" r="{ring + 60}" fill="url(#iglow)"/>',
            f'<circle cx="{c}" cy="{c + 14}" r="{ring}" fill="{OUTLINE}" opacity="0.55"/>',
            f'<circle cx="{c}" cy="{c}" r="{ring}" fill="url(#igold)" stroke="{OUTLINE}" stroke-width="12"/>',
            f'<circle cx="{c}" cy="{c}" r="{ring - 36}" fill="{RED}" stroke="{OUTLINE}" stroke-width="9"/>']
    # Tablecloth checks around the inner ring.
    for k in range(32):
        a0, a1 = k * math.tau / 32, (k + 1) * math.tau / 32
        r0, r1 = ring - 36, ring - 70
        pts = [(c + math.cos(a) * r, c + math.sin(a) * r) for a, r in ((a0, r0), (a1, r0), (a1, r1), (a0, r1))]
        fore.append(f'<path d="M{" L".join(f"{x:.1f} {y:.1f}" for x, y in pts)} Z" fill="{CREAM if k % 2 else RED}"/>')
    fore.append(f'<circle cx="{c}" cy="{c}" r="{ring - 70}" fill="#a52a26" stroke="{OUTLINE}" stroke-width="6"/>')
    fore.append(outlined_text(c, c + 100, "Dz", "Shrikhand", 330, "url(#igold)", OUTLINE, 18))
    return back, fore


def write_icons() -> None:
    back, fore = icon_layers()
    head = f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{font_faces()}'
    (DESIGN / "icon.svg").write_text(head + "".join(back) + "".join(fore) + "</svg>\n", encoding="utf-8")
    (DESIGN / "icon_background.svg").write_text(head + "".join(back) + "</svg>\n", encoding="utf-8")
    (DESIGN / "icon_foreground.svg").write_text(head + "".join(fore) + "</svg>\n", encoding="utf-8")


if __name__ == "__main__":
    main()
    write_icons()
