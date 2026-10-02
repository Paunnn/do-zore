"""Night scenery behind each venue: what you would see around the room at night.

birtija: village hills, poplars and a few lit houses over dark grass.
kafana:  a row of town roofs and a bell tower over a cobbled street.
restoran: a city skyline over a paved square with lamp posts.
splav:   the far bank and a lit bridge over the river the raft floats on.

Each backdrop is 1080x1920 (portrait design size); the floor view covers the screen with it and
moves it slightly against the camera for depth.

    python tools/art/build_backdrops.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/world/backdrops"
W, H = 1080, 1920
HORIZON = 760
CREAM = "#f3e8cf"
LAMP = "#ffd36a"
INK = "#120c08"


def sky(parts: list, defs: list, top: str, mid: str, low: str, rng: random.Random) -> None:
    defs.append(f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
                f'<stop offset="0.6" stop-color="{mid}"/><stop offset="1" stop-color="{low}"/></linearGradient>')
    parts.append(f'<rect width="{W}" height="{HORIZON + 40}" fill="url(#sky)"/>')
    for _ in range(170):
        x, y = rng.uniform(0, W), rng.uniform(0, HORIZON - 120)
        r = rng.choice((0.9, 1.1, 1.4, 1.8)) if rng.random() < 0.94 else 2.6
        parts.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{CREAM}" opacity="{rng.uniform(0.25, 0.85) * (1 - y / HORIZON * 0.6):.2f}"/>')
    # Full moon with a soft halo.
    defs.append('<radialGradient id="halo"><stop offset="0" stop-color="#fff4d0" stop-opacity="0.35"/><stop offset="1" stop-color="#fff4d0" stop-opacity="0"/></radialGradient>')
    parts.append('<circle cx="870" cy="350" r="150" fill="url(#halo)"/>')
    parts.append('<circle cx="870" cy="350" r="46" fill="#fbf0cf"/>')
    for cx, cy, r in ((854, 336, 9), (884, 364, 12), (878, 328, 5), (858, 370, 6)):
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#e6d6a8" opacity="0.7"/>')


def ground(parts: list, defs: list, near: str, far: str) -> None:
    defs.append(f'<linearGradient id="ground" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{far}"/>'
                f'<stop offset="1" stop-color="{near}"/></linearGradient>')
    parts.append(f'<rect y="{HORIZON}" width="{W}" height="{H - HORIZON}" fill="url(#ground)"/>')


def glow(parts: list, x: float, y: float, r: float, opacity: float = 0.45) -> None:
    parts.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.0f}" fill="url(#lampglow)" opacity="{opacity}"/>')


def windows(parts: list, rng: random.Random, x0: float, y0: float, cols: int, rows: int, w: float, h: float, gx: float, gy: float, lit: float) -> None:
    for i in range(cols):
        for j in range(rows):
            if rng.random() < lit:
                parts.append(f'<rect x="{x0 + i * gx:.1f}" y="{y0 + j * gy:.1f}" width="{w}" height="{h}" fill="{LAMP}" opacity="{rng.uniform(0.55, 0.95):.2f}"/>')


def lamp_post(parts: list, x: float, y: float, height: float = 120) -> None:
    glow(parts, x, y - height, 70, 0.55)
    parts.append(f'<rect x="{x - 3:.0f}" y="{y - height:.0f}" width="6" height="{height:.0f}" fill="{INK}"/>')
    parts.append(f'<rect x="{x - 9:.0f}" y="{y - height - 14:.0f}" width="18" height="16" rx="3" fill="{LAMP}" stroke="{INK}" stroke-width="3"/>')


# ---------------------------------------------------------------------------------------------

def birtija(parts: list, defs: list, rng: random.Random) -> None:
    sky(parts, defs, "#0c1430", "#1b2d55", "#33426e", rng)
    parts.append(f'<path d="M0 640 Q140 560 300 610 T620 590 T900 560 T1080 600 L1080 {HORIZON + 30} L0 {HORIZON + 30} Z" fill="#1d2b48"/>')
    for x, y in ((160, 600), (420, 606), (880, 572)):
        parts.append(f'<rect x="{x}" y="{y - 22}" width="40" height="24" fill="#141d33"/><path d="M{x - 6} {y - 22} L{x + 20} {y - 40} L{x + 46} {y - 22} Z" fill="#141d33"/>')
        parts.append(f'<rect x="{x + 8}" y="{y - 14}" width="8" height="8" fill="{LAMP}" opacity="0.9"/><rect x="{x + 24}" y="{y - 14}" width="8" height="8" fill="{LAMP}" opacity="0.6"/>')
    parts.append(f'<path d="M0 700 Q200 650 420 690 T840 670 T1080 690 L1080 {HORIZON + 40} L0 {HORIZON + 40} Z" fill="#17233a"/>')
    for x in (60, 110, 250, 720, 790, 1010):
        h = rng.uniform(140, 210)
        parts.append(f'<ellipse cx="{x}" cy="{690 - h / 2:.0f}" rx="{rng.uniform(16, 22):.0f}" ry="{h / 2:.0f}" fill="#101a2c"/>')
    ground(parts, defs, "#13251b", "#1c3326")
    # Grass tufts, a dirt path and fireflies.
    for _ in range(260):
        x, y = rng.uniform(0, W), rng.uniform(HORIZON + 20, H)
        s = 4 + (y - HORIZON) / 120
        parts.append(f'<path d="M{x:.0f} {y:.0f} l{-s * 0.6:.1f} {-s * 2:.1f} M{x:.0f} {y:.0f} l{s * 0.2:.1f} {-s * 2.4:.1f} M{x:.0f} {y:.0f} l{s:.1f} {-s * 1.8:.1f}" stroke="#2c4a33" stroke-width="2" stroke-linecap="round"/>')
    parts.append('<path d="M-40 1920 C200 1700 160 1500 380 1300 L470 1300 C300 1500 360 1700 200 1920 Z" fill="#3a2e22" opacity="0.6"/>')
    parts.append(f'<path d="M40 {HORIZON + 60} L1040 {HORIZON + 60}" stroke="#0e1810" stroke-width="5" stroke-dasharray="4 28" opacity="0.8"/>')
    for _ in range(36):
        x, y = rng.uniform(0, W), rng.uniform(HORIZON - 80, H)
        glow(parts, x, y, 18, 0.5)
        parts.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="2.6" fill="#f6f09a"/>')


def kafana(parts: list, defs: list, rng: random.Random) -> None:
    sky(parts, defs, "#0d1430", "#1d2b55", "#3d3a66", rng)
    # Bell tower with an onion dome behind the roofs.
    parts.append('<rect x="640" y="380" width="70" height="320" fill="#141b31"/><path d="M630 384 Q675 300 720 384 Z" fill="#141b31"/>'
                 '<rect x="672" y="270" width="6" height="50" fill="#141b31"/><rect x="664" y="282" width="22" height="5" fill="#141b31"/>'
                 f'<rect x="662" y="430" width="26" height="40" rx="13" fill="{LAMP}" opacity="0.45"/>')
    x = -20
    while x < W:
        w = rng.uniform(110, 170)
        h = rng.uniform(70, 150)
        top = HORIZON - h
        roof = rng.uniform(40, 70)
        parts.append(f'<rect x="{x:.0f}" y="{top:.0f}" width="{w:.0f}" height="{h + 40:.0f}" fill="#1a2034"/>')
        parts.append(f'<path d="M{x - 8:.0f} {top:.0f} L{x + w / 2:.0f} {top - roof:.0f} L{x + w + 8:.0f} {top:.0f} Z" fill="#2a1e22"/>')
        if rng.random() < 0.6:
            parts.append(f'<rect x="{x + w * 0.7:.0f}" y="{top - roof * 0.7:.0f}" width="14" height="{roof * 0.5:.0f}" fill="#2a1e22"/>')
        windows(parts, rng, x + 14, top + 16, int(w // 34), int(h // 44), 14, 20, 32, 42, 0.45)
        x += w + rng.uniform(4, 18)
    ground(parts, defs, "#1b1a22", "#2a2732")
    # Cobblestones: staggered rounded stones that shrink toward the horizon.
    y = HORIZON + 30
    row = 0
    while y < H:
        size = 10 + (y - HORIZON) / 40
        x = -size if row % 2 else -size * 0.5
        while x < W + size:
            parts.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{size * 1.6:.0f}" height="{size * 0.8:.0f}" rx="{size * 0.35:.0f}" fill="#34313d" opacity="{rng.uniform(0.6, 1):.2f}"/>')
            x += size * 1.9
        y += size * 1.05
        row += 1
    for lx, ly in ((90, 1180), (990, 1180), (130, 1760), (960, 1760)):
        lamp_post(parts, lx, ly, 150)


def restoran(parts: list, defs: list, rng: random.Random) -> None:
    sky(parts, defs, "#0b1230", "#1c2958", "#433d70", rng)
    # Far skyline, then nearer and taller blocks with grids of windows.
    for layer, color, lit, low, high in ((0, "#1a2240", 0.25, 80, 200), (1, "#131a31", 0.4, 120, 330)):
        x = -10
        while x < W:
            w = rng.uniform(70, 140)
            h = rng.uniform(low, high)
            parts.append(f'<rect x="{x:.0f}" y="{HORIZON - h:.0f}" width="{w:.0f}" height="{h + 40:.0f}" fill="{color}"/>')
            windows(parts, rng, x + 10, HORIZON - h + 14, int(w // 22), int(h // 26), 10, 12, 20, 24, lit * (0.6 + layer * 0.4))
            x += w + rng.uniform(2, 10)
    # A tower with an antenna, the city's landmark.
    parts.append(f'<path d="M470 {HORIZON} L486 330 L594 330 L610 {HORIZON} Z" fill="#0f1529"/><rect x="536" y="250" width="8" height="84" fill="#0f1529"/>'
                 f'<circle cx="540" cy="248" r="5" fill="#ff5a4a"/>')
    windows(parts, rng, 500, 350, 4, 15, 12, 10, 26, 26, 0.5)
    ground(parts, defs, "#1d1c26", "#2c2a38")
    # Large square pavers with a perspective feel.
    for k in range(14):
        y = HORIZON + 40 + (k ** 1.55) * 9
        parts.append(f'<path d="M0 {y:.0f} L{W} {y:.0f}" stroke="#3b3848" stroke-width="2"/>')
    for k in range(-8, 9):
        parts.append(f'<path d="M{540 + k * 40} {HORIZON + 40} L{540 + k * 220} {H}" stroke="#3b3848" stroke-width="2"/>')
    for px, py in ((80, 1250), (1000, 1250), (70, 1800), (1010, 1800)):
        parts.append(f'<rect x="{px - 40}" y="{py - 30}" width="80" height="40" rx="6" fill="#4a3a2e" stroke="{INK}" stroke-width="3"/>'
                     f'<circle cx="{px - 18}" cy="{py - 40}" r="22" fill="#24402c"/><circle cx="{px + 14}" cy="{py - 46}" r="26" fill="#2c4a33"/>')
    for lx, ly in ((180, 1100), (900, 1100), (250, 1650), (830, 1650)):
        lamp_post(parts, lx, ly, 170)


def splav(parts: list, defs: list, rng: random.Random) -> None:
    sky(parts, defs, "#0b1330", "#1b2c5a", "#3d4a7e", rng)
    # Far bank: low city lights.
    x = -10
    while x < W:
        w = rng.uniform(40, 90)
        h = rng.uniform(30, 110)
        parts.append(f'<rect x="{x:.0f}" y="{HORIZON - 120 - h:.0f}" width="{w:.0f}" height="{h + 10:.0f}" fill="#172242"/>')
        windows(parts, rng, x + 6, HORIZON - 114 - h, int(w // 16), int(h // 18), 6, 7, 14, 16, 0.4)
        x += w + rng.uniform(0, 8)
    parts.append(f'<rect y="{HORIZON - 120}" width="{W}" height="20" fill="#121a33"/>')
    # The bridge: a deck on arches with a string of lamps.
    deck = HORIZON - 64
    parts.append(f'<rect y="{deck}" width="{W}" height="18" fill="#0f1529"/>')
    for k in range(6):
        cx = 90 + k * 180
        parts.append(f'<path d="M{cx - 90} {deck + 18} Q{cx} {deck - 30} {cx + 90} {deck + 18} L{cx + 90} {deck + 28} Q{cx} {deck - 18} {cx - 90} {deck + 28} Z" fill="#0f1529"/>')
        parts.append(f'<rect x="{cx - 96}" y="{deck + 18}" width="12" height="{HORIZON - deck - 10}" fill="#0f1529"/>')
    for k in range(28):
        lx = 20 + k * 38
        glow(parts, lx, deck - 6, 16, 0.5)
        parts.append(f'<circle cx="{lx}" cy="{deck - 6}" r="3" fill="{LAMP}"/>')
    # The river: deep water with long reflections of the bridge lamps and the moon.
    defs.append('<linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#25407a"/><stop offset="1" stop-color="#0f1d3a"/></linearGradient>')
    parts.append(f'<rect y="{HORIZON - 30}" width="{W}" height="{H - HORIZON + 30}" fill="url(#water)"/>')
    for k in range(28):
        lx = 20 + k * 38
        for j in range(4):
            y = HORIZON + j * 26 + rng.uniform(-4, 4)
            parts.append(f'<path d="M{lx - 8 + rng.uniform(-4, 4):.0f} {y:.0f} l{rng.uniform(10, 20):.0f} 0" stroke="{LAMP}" stroke-width="2.4" stroke-linecap="round" opacity="{0.55 - j * 0.12:.2f}"/>')
    for j in range(16):
        y = HORIZON + 10 + j * 22
        parts.append(f'<path d="M{870 - 30 + rng.uniform(-10, 10):.0f} {y:.0f} l{rng.uniform(40, 70):.0f} 0" stroke="#fbf0cf" stroke-width="3" stroke-linecap="round" opacity="{0.5 - j * 0.028:.2f}"/>')
    for _ in range(140):
        x, y = rng.uniform(0, W), rng.uniform(HORIZON + 60, H)
        w = 14 + (y - HORIZON) / 18
        parts.append(f'<path d="M{x:.0f} {y:.0f} q{w / 2:.0f} -5 {w:.0f} 0" stroke="#5b7fbf" stroke-width="2.2" fill="none" stroke-linecap="round" opacity="{rng.uniform(0.25, 0.55):.2f}"/>')


VENUES = {"birtija": birtija, "kafana": kafana, "restoran": restoran, "splav": splav}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in VENUES.items():
        rng = random.Random(name)
        parts: list[str] = []
        defs = [f'<radialGradient id="lampglow"><stop offset="0" stop-color="{LAMP}" stop-opacity="0.8"/><stop offset="1" stop-color="{LAMP}" stop-opacity="0"/></radialGradient>']
        draw(parts, defs, rng)
        (OUT / f"{name}.svg").write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n',
            encoding="utf-8")
    print(f"{len(VENUES)} backdrops written to {OUT}")


if __name__ == "__main__":
    main()
