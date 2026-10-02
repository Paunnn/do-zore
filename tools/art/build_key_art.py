"""Key art for Do Zore: the road from birtija to splav, climbing through the night toward dawn.

Writes client/design/key_art.svg (with the font faces referenced from client/assets/fonts) and a
venue vignette per venue to client/assets/world/vignettes/*.svg. Rasterise the key art with any
SVG renderer that loads web fonts, e.g. `node tools/art/render_svg.js` (Playwright Chromium):

    python tools/art/build_key_art.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from isokit import INK, LINE, Canvas, P, shade

ROOT = Path(__file__).resolve().parents[1].parent
FONTS = ROOT / "client/assets/fonts"
DESIGN = ROOT / "client/design"
VIGNETTES = ROOT / "client/assets/world/vignettes"

W, H = 1080, 1920
BRASS = "#d9a531"
BRASS_LIGHT = "#f3d27a"
BRASS_DARK = "#8a5a1c"
CREAM = "#f4ead2"
RED = "#b8302f"
NAVY = "#1f3b5a"
NIGHT = "#0e1428"
WALNUT = "#4a2c1a"
LAMP = "#ffd36a"


# ---------------------------------------------------------------------------------------------
# Buildings, drawn with the same outlined isometric kit as the game
# ---------------------------------------------------------------------------------------------

def glow(c: Canvas, x: float, y: float, r: float, color: str = LAMP, strength: float = 0.55) -> None:
    gid = f"glow{len(c.defs)}"
    c.defs.append(f'<radialGradient id="{gid}"><stop offset="0" stop-color="{color}" stop-opacity="{strength}"/>'
                  f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>')
    c.raw(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="url(#{gid})"/>', [(x - r, y - r), (x + r, y + r)])


def window(c: Canvas, face: str, a: float, z: float, w: float, h: float, x_or_y: float, arched: bool = False) -> None:
    """Lit window on the +y face ('l') or +x face ('r') of a box."""
    if face == "l":
        pts = [P(a, x_or_y, z), P(a + w, x_or_y, z), P(a + w, x_or_y, z + h), P(a, x_or_y, z + h)]
    else:
        pts = [P(x_or_y, a, z), P(x_or_y, a + w, z), P(x_or_y, a + w, z + h), P(x_or_y, a, z + h)]
    cx = sum(p[0] for p in pts) / 4
    cy = sum(p[1] for p in pts) / 4
    glow(c, cx, cy, 34, LAMP, 0.35)
    c.poly(pts, LAMP, INK, 1.6)
    if arched:
        top = [pts[3], ((pts[2][0] + pts[3][0]) / 2, (pts[2][1] + pts[3][1]) / 2 - 8), pts[2]]
        c.raw(f'<path d="M{top[0][0]:.1f} {top[0][1]:.1f} Q{top[1][0]:.1f} {top[1][1] - 6:.1f} {top[2][0]:.1f} {top[2][1]:.1f} Z" fill="{LAMP}" stroke="{INK}" stroke-width="1.6"/>', top)
    mid_a = [((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2), ((pts[2][0] + pts[3][0]) / 2, (pts[2][1] + pts[3][1]) / 2)]
    c.line(mid_a, shade(LAMP, -0.45), 1.2)
    mid_b = [((pts[0][0] + pts[3][0]) / 2, (pts[0][1] + pts[3][1]) / 2), ((pts[1][0] + pts[2][0]) / 2, (pts[1][1] + pts[2][1]) / 2)]
    c.line(mid_b, shade(LAMP, -0.45), 1.2)


def gable_roof(c: Canvas, x: float, y: float, w: float, d: float, z: float, rise: float, color: str) -> None:
    """Roof with its ridge running along x."""
    ridge0, ridge1 = P(x - 0.06, y + d / 2, z + rise), P(x + w + 0.06, y + d / 2, z + rise)
    c.poly([P(x - 0.06, y - 0.08, z), P(x + w + 0.06, y - 0.08, z), ridge1, ridge0], shade(color, -0.12))
    c.poly([P(x - 0.06, y + d + 0.08, z), P(x + w + 0.06, y + d + 0.08, z), ridge1, ridge0], color)
    c.poly([P(x + w + 0.06, y - 0.08, z), P(x + w + 0.06, y + d + 0.08, z), ridge1], shade(color, -0.28))
    for k in range(1, int(w * 6)):
        t = x + k / 6
        c.line([P(t, y + d + 0.08, z), P(t, y + d / 2, z + rise)], shade(color, -0.22), 0.9)


def birtija(c: Canvas) -> None:
    wall = "#d8c3a0"
    c.top_quad(-0.6, -0.4, 0, 2.8, 2.2, "#5a7a3a")
    c.box(0, 0, 0, 1.6, 1.2, 64, wall)
    gable_roof(c, 0, 0, 1.6, 1.2, 64, 44, "#b0532f")
    c.box(1.1, 0.25, 90, 0.18, 0.18, 34, "#8a6a52")
    c.poly([P(0.2, 1.2, 0), P(0.55, 1.2, 0), P(0.55, 1.2, 44), P(0.2, 1.2, 44)], "#6e4528")
    window(c, "l", 0.85, 22, 0.45, 26, 1.2)
    window(c, "r", 0.35, 22, 0.45, 26, 1.6)
    c.box(0.65, 1.45, 0, 0.8, 0.18, 12, "#8a5a32")
    c.box(-0.4, 1.8, 0, 0.05, 0.05, 92, "#3a3a44")
    x, y = P(-0.38, 1.82, 96)
    glow(c, x, y, 46, LAMP, 0.55)
    c.ellipse(x, y, 6, 7, LAMP, INK, 1.4)


def kafana(c: Canvas) -> None:
    wall = "#c98a4a"
    c.top_quad(-0.5, -0.3, 0, 3.2, 2.6, "#6a5a4a")
    c.box(0, 0, 0, 2.2, 1.6, 120, wall)
    c.box(-0.05, -0.05, 120, 2.3, 1.7, 10, "#7a4a2a")
    c.top_quad(0.08, 0.08, 130, 2.04, 1.44, "#a5513a")
    for k in range(1, 9):
        c.line([P(0.08, 0.08 + k * 0.16, 130), P(2.12, 0.08 + k * 0.16, 130)], "#8a3f2c", 1.0)
    for a in (0.2, 0.95, 1.65):
        window(c, "l", a, 70, 0.38, 32, 1.6)
    for a in (0.25, 0.95):
        window(c, "r", a, 70, 0.38, 32, 2.2)
    window(c, "l", 0.2, 14, 0.5, 34, 1.6)
    window(c, "l", 1.45, 14, 0.5, 34, 1.6)
    c.poly([P(0.85, 1.6, 0), P(1.25, 1.6, 0), P(1.25, 1.6, 50), P(0.85, 1.6, 50)], "#5a3a22")
    # Checkered awning over the ground floor.
    for k in range(10):
        a0, a1 = k * 0.22, (k + 1) * 0.22
        color = RED if k % 2 == 0 else CREAM
        c.poly([P(a0, 1.6, 56), P(a1, 1.6, 56), P(a1, 1.85, 44), P(a0, 1.85, 44)], color, INK, 1.2)
    # Blank signboard with a brass rim.
    c.poly([P(0.45, 1.61, 98), P(1.75, 1.61, 98), P(1.75, 1.61, 114), P(0.45, 1.61, 114)], WALNUT, BRASS, 2.2)
    # String of lamps along the cornice.
    for k in range(9):
        a = 0.1 + k * 0.25
        x, y = P(a, 1.62, 126)
        glow(c, x, y + 6, 14, LAMP, 0.6)
        c.ellipse(x, y + 6, 2.6, 3.2, LAMP, INK, 0.8)


def restoran(c: Canvas) -> None:
    wall = "#efe6d2"
    c.top_quad(-0.5, -0.3, 0, 3.6, 2.8, "#4a5a4a")
    c.box(-0.06, -0.06, 0, 2.72, 1.92, 10, "#c9bfae")
    c.box(0, 0, 10, 2.6, 1.8, 112, wall)
    # Flat pilasters between the tall arched windows, brass cornice and a balustrade.
    for k in range(5):
        a = 0.08 + k * 0.6
        c.wall_rect("right", a, 10, 0.1, 112, "#f8f4ea", INK, 1.2, offset=1.8)
    for a in (0.28, 0.88, 1.48, 2.08):
        window(c, "l", a + 0.02, 34, 0.36, 62, 1.8, arched=True)
    for a in (0.36, 1.08):
        window(c, "r", a, 34, 0.36, 62, 2.6, arched=True)
    c.box(-0.08, -0.08, 122, 2.76, 1.96, 12, BRASS, top=BRASS_LIGHT, right=BRASS_DARK)
    c.top_quad(0.06, 0.06, 134, 2.48, 1.68, "#5d6683")
    for k in range(1, 8):
        c.line([P(0.06 + k * 0.31, 0.06, 134), P(0.06 + k * 0.31, 1.74, 134)], "#4d5570", 1.0)
    for k in range(17):
        a = 0.0 + k * 0.1625
        c.box(a, 1.8, 134, 0.05, 0.05, 14, "#f8f4ea", outline=False)
    c.line([P(-0.02, 1.86, 148), P(2.66, 1.86, 148)], INK, 2.2)
    c.line([P(2.66, 1.86, 148), P(2.66, -0.02, 148)], INK, 2.2)
    # Canopy over the entrance.
    c.poly([P(1.05, 1.8, 58), P(1.55, 1.8, 58), P(1.55, 2.2, 48), P(1.05, 2.2, 48)], RED, INK, 1.6)
    c.poly([P(1.1, 1.8, 10), P(1.5, 1.8, 10), P(1.5, 1.8, 50), P(1.1, 1.8, 50)], "#5a3a22", INK, 1.6)


def splav(c: Canvas) -> None:
    c.box(-0.2, -0.2, -8, 3.0, 2.0, 12, "#5a4a3a")
    for k in range(int(3.0 * 5)):
        a = -0.2 + k / 5
        c.line([P(a, 1.8, 4), P(a, -0.2, 4)], "#3a2a1a", 0.8)
    posts = [(0.0, 0.0), (2.4, 0.0), (2.4, 1.4), (0.0, 1.4)]
    for px, py in posts[:2]:
        c.box(px, py, 4, 0.08, 0.08, 74, "#3a2a1a")
    # Striped tent roof.
    apex = P(1.2, 0.7, 120)
    corners = [P(-0.15, -0.15, 78), P(2.55, -0.15, 78), P(2.55, 1.55, 78), P(-0.15, 1.55, 78)]
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        face_color = [RED, shade(RED, -0.2), RED, CREAM][i]
        c.poly([a, b, apex], face_color, INK, 1.6)
    for t in (0.33, 0.66):
        for i in (2, 3):
            a, b = corners[i], corners[(i + 1) % 4]
            pa = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            c.line([pa, apex], CREAM if i == 2 else RED, 3.2)
    # Warm light under the tent and hanging lanterns.
    cx, cy = P(1.2, 0.7, 30)
    glow(c, cx, cy, 120, LAMP, 0.45)
    for px, py in posts[2:]:
        c.box(px, py, 4, 0.08, 0.08, 74, "#3a2a1a")
    for k in range(6):
        a = k * 0.5
        x, y = P(a, 1.55, 70)
        glow(c, x, y, 16, LAMP, 0.6)
        c.ellipse(x, y, 3.2, 4.2, LAMP, INK, 0.9)
    # Railing along the front edge.
    for k in range(13):
        a = -0.2 + k * 0.25
        c.line([P(a, 1.8, 4), P(a, 1.8, 26)], "#3a2a1a", 2.2)
    c.line([P(-0.2, 1.8, 26), P(2.8, 1.8, 26)], "#3a2a1a", 3)


VENUES = [("birtija", birtija, "Birtija"), ("kafana", kafana, "Kafana"), ("restoran", restoran, "Restoran"), ("splav", splav, "Splav")]


def vignette(draw) -> tuple:
    c = Canvas()
    draw(c)
    return c


# ---------------------------------------------------------------------------------------------
# Key art
# ---------------------------------------------------------------------------------------------

def kilim_border(parts: list, inset: float, band: float) -> None:
    x0, y0, x1, y1 = inset, inset, W - inset, H - inset
    parts.append(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="none" stroke="{RED}" stroke-width="{band}"/>')
    parts.append(f'<rect x="{x0 - band / 2}" y="{y0 - band / 2}" width="{x1 - x0 + band}" height="{y1 - y0 + band}" fill="none" stroke="{INK}" stroke-width="3"/>')
    parts.append(f'<rect x="{x0 + band / 2}" y="{y0 + band / 2}" width="{x1 - x0 - band}" height="{y1 - y0 - band}" fill="none" stroke="{BRASS}" stroke-width="3"/>')
    step = band * 1.2

    def motif(cx, cy, s):
        out = ""
        for scale, color in ((1.0, NAVY), (0.62, BRASS), (0.28, CREAM)):
            r = s * scale
            out += f'<path d="M{cx:.1f} {cy - r:.1f} L{cx + r:.1f} {cy:.1f} L{cx:.1f} {cy + r:.1f} L{cx - r:.1f} {cy:.1f} Z" fill="{color}"/>'
        return out

    n = int((x1 - x0) / step)
    for i in range(n + 1):
        cx = x0 + (x1 - x0) * i / n
        parts.append(motif(cx, y0, band * 0.36) + motif(cx, y1, band * 0.36))
    n = int((y1 - y0) / step)
    for i in range(1, n):
        cy = y0 + (y1 - y0) * i / n
        parts.append(motif(x0, cy, band * 0.36) + motif(x1, cy, band * 0.36))


def main() -> None:
    DESIGN.mkdir(parents=True, exist_ok=True)
    VIGNETTES.mkdir(parents=True, exist_ok=True)
    rng = random.Random(1912)
    parts: list[str] = []
    defs = [
        '<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#f0a86a"/><stop offset="0.07" stop-color="#c97a6a"/><stop offset="0.2" stop-color="#4a3f6e"/>'
        f'<stop offset="0.45" stop-color="#1d2a52"/><stop offset="1" stop-color="{NIGHT}"/></linearGradient>',
        f'<linearGradient id="river" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a4a78"/><stop offset="1" stop-color="#14264a"/></linearGradient>',
        f'<linearGradient id="brass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BRASS_LIGHT}"/><stop offset="0.55" stop-color="{BRASS}"/><stop offset="1" stop-color="{BRASS_DARK}"/></linearGradient>',
        '<radialGradient id="dawn" cx="0.5" cy="0" r="0.7"><stop offset="0" stop-color="#ffd9a0" stop-opacity="0.55"/><stop offset="1" stop-color="#ffd9a0" stop-opacity="0"/></radialGradient>',
    ]
    parts.append(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
    parts.append(f'<rect width="{W}" height="{H * 0.5}" fill="url(#dawn)"/>')
    # Stars: a measured field, thinning out where the dawn reaches.
    for gy in range(0, 64):
        for gx in range(0, 34):
            y = 60 + gy * 28 + rng.uniform(-10, 10)
            x = 40 + gx * 30 + rng.uniform(-12, 12)
            density = min(1.0, max(0.0, (y - 220) / 900))
            if rng.random() < 0.28 * density:
                r = rng.choice((0.9, 1.1, 1.3, 1.8)) if rng.random() < 0.92 else 2.6
                parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{CREAM}" opacity="{rng.uniform(0.35, 0.9):.2f}"/>')
    # Distant hills and the river near the top, where the splav waits.
    parts.append('<path d="M0 668 Q160 628 300 656 T600 646 T880 628 T1080 640 L1080 720 L0 720 Z" fill="#2a2f55" opacity="0.9"/>')
    parts.append('<path d="M0 700 C220 676 420 716 640 694 S960 678 1080 690 L1080 1004 C900 1024 700 990 520 1012 S180 1034 0 1016 Z" fill="url(#river)"/>')
    for k in range(30):
        x = rng.uniform(70, 1010)
        y = rng.uniform(724, 990)
        w = rng.uniform(18, 46)
        parts.append(f'<path d="M{x:.1f} {y:.1f} l{w:.1f} 0" stroke="#5a7ab0" stroke-width="2" stroke-linecap="round" opacity="0.55"/>')
    # Lamp reflections under the splav.
    for k in range(7):
        x = 610 + k * 34
        parts.append(f'<path d="M{x} {930 + (k % 3) * 9} l14 0 M{x + 6} {948 + (k % 2) * 11} l10 0" stroke="{LAMP}" stroke-width="2.4" stroke-linecap="round" opacity="0.5"/>')
    # Venues zig-zag up the frame; the road runs door to door and ends on the splav gangway.
    stops = {"birtija": (330, 1640, 0.95), "kafana": (730, 1370, 0.95), "restoran": (330, 1090, 0.9), "splav": (720, 820, 0.95)}
    doors = {"birtija": (0.375, 1.2), "kafana": (1.05, 1.6), "restoran": (1.3, 2.2), "splav": (1.2, 1.8)}
    ends = []
    for key, (x, y, s) in stops.items():
        dx, dy = P(*doors[key])
        ends.append((x + dx * s, y + dy * s + 14))
    d = f"M{ends[0][0]:.0f} {ends[0][1]:.0f}"
    for a, b in zip(ends, ends[1:]):
        mx = (a[0] + b[0]) / 2
        d += f" C{mx:.0f} {a[1] + 40:.0f} {mx:.0f} {b[1] + 120:.0f} {b[0]:.0f} {b[1]:.0f}"
    parts.append(f'<path d="{d}" fill="none" stroke="{BRASS}" stroke-width="3" stroke-dasharray="2 22" stroke-linecap="round" opacity="0.95"/>')
    parts.append(f'<path d="{d}" fill="none" stroke="{LAMP}" stroke-width="10" stroke-dasharray="2 94" stroke-dashoffset="-46" stroke-linecap="round" opacity="0.85"/>')
    canvas_defs: list[str] = []
    for key, draw, label in VENUES:
        vc = vignette(draw)
        text, info = vc.svg(P(0, 0), pad=8, scale=2.0)
        (VIGNETTES / f"{key}.svg").write_text(text, encoding="utf-8")
        x, y, s = stops[key]
        inner = "".join(vc.items)
        canvas_defs.extend(d.replace('id="', f'id="{key}_').replace('url(#', f'url(#{key}_') for d in vc.defs)
        inner = inner.replace('url(#', f'url(#{key}_')
        parts.append(f'<g transform="translate({x} {y}) scale({s})">{inner}</g>')
    defs.extend(canvas_defs)
    # Venue labels: numeral and name in small capitals, set beside each stop.
    labels = {"birtija": (610, 1700, "start", "I"), "kafana": (470, 1430, "end", "II"), "restoran": (610, 1150, "start", "III"), "splav": (470, 880, "end", "IV")}
    for key, _, label in VENUES:
        x, y, anchor, numeral = labels[key]
        parts.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="Alegreya SC" font-weight="800" font-size="40" letter-spacing="4" fill="{CREAM}">'
                     f'<tspan fill="{BRASS}" font-size="30">{numeral}  </tspan>{label}</text>')
    # Title and the chalk line under it.
    parts.append(f'<text x="{W / 2}" y="330" text-anchor="middle" font-family="Yeseva One" font-size="200" fill="{INK}" opacity="0.55" transform="translate(0 8)">Do zore</text>')
    parts.append(f'<text x="{W / 2}" y="330" text-anchor="middle" font-family="Yeseva One" font-size="200" fill="url(#brass)" stroke="{INK}" stroke-width="3" paint-order="stroke">Do zore</text>')
    parts.append(f'<text x="{W / 2}" y="420" text-anchor="middle" font-family="Marck Script" font-size="58" fill="{CREAM}">od birtije do splava</text>')
    parts.append(f'<path d="M{W / 2 - 150} 456 L{W / 2 + 150} 456" stroke="{BRASS}" stroke-width="2"/>')
    parts.append(f'<path d="M{W / 2} 446 l10 10 l-10 10 l-10 -10 Z" fill="{RED}" stroke="{BRASS}" stroke-width="2"/>')
    parts.append(f'<text x="{W / 2}" y="1812" text-anchor="middle" font-family="Alegreya SC" font-weight="800" font-size="30" letter-spacing="10" fill="{BRASS}">JOŠ JEDNA PESMA</text>')
    kilim_border(parts, 30, 26)
    fonts = font_faces()
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{fonts}'
           f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')
    (DESIGN / "key_art.svg").write_text(svg, encoding="utf-8")
    print(f"key art and {len(VENUES)} vignettes written")


def font_faces() -> str:
    return (f'<style>@font-face{{font-family:"Yeseva One";src:url("{FONTS / "YesevaOne.ttf"}")}}'
            f'@font-face{{font-family:"Alegreya SC";font-weight:800;src:url("{FONTS / "AlegreyaSC-ExtraBold.ttf"}")}}'
            f'@font-face{{font-family:"Marck Script";src:url("{FONTS / "MarckScript.ttf"}")}}</style>')


def icon_layers() -> tuple:
    """App icon as (background, foreground) SVG fragments on a 1024 canvas.

    The foreground keeps inside the central 66% so adaptive-icon masks never clip it."""
    size = 1024
    c = size / 2
    rng = random.Random(7)
    back = ['<radialGradient id="ibg" cx="0.5" cy="0.32" r="0.8"><stop offset="0" stop-color="#2c3f72"/>'
            f'<stop offset="1" stop-color="{NIGHT}"/></radialGradient>',
            f'<rect width="{size}" height="{size}" fill="url(#ibg)"/>']
    for k in range(70):
        x, y = rng.uniform(20, size - 20), rng.uniform(20, size - 20)
        if math.hypot(x - c, y - c) > 360:
            back.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{rng.choice((2, 2.5, 3.5))}" fill="{CREAM}" opacity="{rng.uniform(0.3, 0.8):.2f}"/>')
    ring = 300
    fore = [f'<linearGradient id="ibrass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BRASS_LIGHT}"/>'
            f'<stop offset="0.55" stop-color="{BRASS}"/><stop offset="1" stop-color="{BRASS_DARK}"/></linearGradient>',
            f'<radialGradient id="iglow"><stop offset="0" stop-color="{LAMP}" stop-opacity="0.35"/><stop offset="1" stop-color="{LAMP}" stop-opacity="0"/></radialGradient>',
            f'<circle cx="{c}" cy="{c}" r="{ring + 60}" fill="url(#iglow)"/>',
            f'<circle cx="{c}" cy="{c + 10}" r="{ring}" fill="{INK}" opacity="0.5"/>',
            f'<circle cx="{c}" cy="{c}" r="{ring}" fill="url(#ibrass)" stroke="{INK}" stroke-width="10"/>',
            f'<circle cx="{c}" cy="{c}" r="{ring - 34}" fill="{RED}" stroke="{INK}" stroke-width="8"/>']
    # Brass studs around the rim, sixteen of them.
    for k in range(16):
        a = k * math.tau / 16
        fore.append(f'<circle cx="{c + math.cos(a) * (ring - 17):.1f}" cy="{c + math.sin(a) * (ring - 17):.1f}" r="7" fill="{BRASS_DARK}"/>')
    # Kilim diamond behind the letters.
    for scale, color in ((205, NAVY), (150, "#2f5680"), (95, NAVY)):
        fore.append(f'<path d="M{c} {c - scale} L{c + scale} {c} L{c} {c + scale} L{c - scale} {c} Z" fill="{color}" opacity="0.9"/>')
    fore.append(f'<text x="{c}" y="{c + 118}" text-anchor="middle" font-family="Yeseva One" font-size="340" fill="{INK}" opacity="0.6" transform="translate(0 10)">Dz</text>')
    fore.append(f'<text x="{c}" y="{c + 118}" text-anchor="middle" font-family="Yeseva One" font-size="340" fill="url(#ibrass)" stroke="{INK}" stroke-width="7" paint-order="stroke">Dz</text>')
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
