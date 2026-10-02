"""Modern-kafana UI kit: floating HUD pills, glossy round and lipped buttons, cream cards with a
red header and a tablecloth trim, and the icon set.

Every texture is drawn at 1x design pixels for a 1080-wide screen. The nine-patch margins that
client/scripts/ui/ui_kit.gd uses are listed beside each piece in PIECES; keep them in sync.

    python tools/art/build_ui.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from isokit import Canvas, P, shade

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/ui"

INK = "#2b1d14"
BRASS = "#d9a531"
BRASS_LIGHT = "#f6dc8e"
BRASS_DARK = "#8a5a1c"
CREAM = "#f3e8cf"
PAPER = "#fbf5e6"
RED = "#b8302f"
NAVY = "#1f3b5a"
NIGHT = "#0e1428"


def svg(w: float, h: float, body: str, defs: str = "") -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" viewBox="0 0 {w:g} {h:g}">'
            f'<defs>{defs}</defs>{body}</svg>\n')


def vgrad(gid: str, stops: list) -> str:
    inner = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">{inner}</linearGradient>'


def rrect(x, y, w, h, r, fill, stroke="none", width=0, extra="") -> str:
    s = f' stroke="{stroke}" stroke-width="{width}"' if stroke != "none" else ""
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{r:g}" fill="{fill}"{s}{extra}/>'


BUTTONS = {
    # name: (face gradient, lip, border, highlight)
    "gold": ([(0, "#ffd95a"), (0.5, "#ffbf2e"), (1, "#f0a01c")], "#a8620c", INK, 0.55),
    "red": ([(0, "#de5246"), (0.55, RED), (1, "#962521")], "#6a1916", INK, 0.35),
    "paper": ([(0, "#fffaf0"), (1, "#efe2c6")], "#a88c64", INK, 0.8),
}


def button(name: str, pressed: bool = False) -> str:
    stops, lip, border, glint = BUTTONS[name]
    w, h, r, depth = 96, 92, 22, 7
    drop = depth if pressed else 0
    body = rrect(1.5, depth + 1.5, w - 3, h - depth - 3, r, lip, border, 3)
    body += rrect(1.5, 1.5 + drop, w - 3, h - depth - 3, r, "url(#face)", border, 3)
    body += f'<path d="M{r} {9 + drop} L{w - r} {9 + drop}" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="{glint}"/>'
    return svg(w, h, body, vgrad("face", stops))


def button_disabled() -> str:
    """Greyed glossy face, pressed flat: still a button, clearly not yet available."""
    w, h, r, depth = 96, 92, 22, 7
    body = rrect(1.5, depth + 1.5, w - 3, h - depth - 3, r, "url(#off)", "#6e6458", 3)
    body += f'<path d="M{r} {9 + depth} L{w - r} {9 + depth}" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.35"/>'
    return svg(w, h, body, vgrad("off", [(0, "#cfc6b6"), (1, "#a89e8c")]))


def bar_back() -> str:
    return svg(48, 26, rrect(1.5, 1.5, 45, 23, 11.5, "#24140a", INK, 3) + '<path d="M12 6 L36 6" stroke="#000" stroke-width="2.5" opacity="0.3" stroke-linecap="round"/>')


def bar_back_light() -> str:
    """The same track printed on paper: a pressed groove instead of a dark slot."""
    return svg(48, 26, rrect(1.5, 1.5, 45, 23, 11.5, "#e8dabb", "#8a6a4a", 2.5) + '<path d="M12 6 L36 6" stroke="#6b4a30" stroke-width="2" opacity="0.2" stroke-linecap="round"/>')


def bar_fill() -> str:
    body = rrect(0, 0, 48, 26, 13, "url(#fill)") + '<path d="M10 7 L38 7" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity="0.6"/>'
    return svg(48, 26, body, vgrad("fill", [(0, "#ffffff"), (1, "#c9c9c9")]))


def night_tile() -> str:
    """Seamless star field for night panels."""
    rng = random.Random(21)
    w = h = 256
    body = ""
    for _ in range(46):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.choice((0.8, 1.0, 1.2, 1.6)) if rng.random() < 0.93 else 2.2
        for dx in (-w, 0, w):
            for dy in (-h, 0, h):
                if -4 < x + dx < w + 4 and -4 < y + dy < h + 4:
                    body += f'<circle cx="{x + dx:.1f}" cy="{y + dy:.1f}" r="{r}" fill="{CREAM}" opacity="{rng.uniform(0.25, 0.8):.2f}"/>'
    return svg(w, h, body)


def divider() -> str:
    w, h = 360, 24
    body = (f'<path d="M8 12 L{w / 2 - 18} 12 M{w / 2 + 18} 12 L{w - 8} 12" stroke="{BRASS}" stroke-width="2.5" stroke-linecap="round"/>'
            f'<path d="M{w / 2} 2 L{w / 2 + 10} 12 L{w / 2} 22 L{w / 2 - 10} 12 Z" fill="{RED}" stroke="{BRASS_DARK}" stroke-width="2"/>'
            f'<circle cx="{w / 2 - 26}" cy="12" r="3" fill="{BRASS}"/><circle cx="{w / 2 + 26}" cy="12" r="3" fill="{BRASS}"/>')
    return svg(w, h, body)


def ring(state: str) -> str:
    """Round frame for icons and portraits: paper for owned things, dark for locked ones."""
    w = 132
    c = w / 2
    fill = {"paper": PAPER, "dark": "#2a1a10", "night": "#1d2c52"}[state]
    edge = {"paper": BRASS, "dark": "#6b5440", "night": BRASS}[state]
    body = (f'<circle cx="{c}" cy="{c + 4}" r="{c - 4}" fill="{INK}" opacity="0.3"/>'
            f'<circle cx="{c}" cy="{c}" r="{c - 4}" fill="{edge}" stroke="{INK}" stroke-width="3.5"/>'
            f'<circle cx="{c}" cy="{c}" r="{c - 13}" fill="{fill}" stroke="{INK}" stroke-width="2.5"/>')
    return svg(w, w, body)


def toggle(on: bool) -> str:
    fill = "#3d8a4f" if on else "#cdbb98"
    knob = 64 if on else 28
    body = (rrect(4, 8, 84, 44, 22, fill, INK, 3.5)
            + f'<circle cx="{knob}" cy="{30 + 3}" r="18" fill="{INK}" opacity="0.3"/>'
            + f'<circle cx="{knob}" cy="30" r="18" fill="url(#kn)" stroke="{INK}" stroke-width="3"/>')
    return svg(92, 60, body, vgrad("kn", [(0, "#f8de92"), (1, "#c99232")]))


# ---------------------------------------------------------------------------------------------
# Glyphs: white so Godot can tint them (navigation, HUD buttons)
# ---------------------------------------------------------------------------------------------

GLYPHS = {
    # A table under a checkered cloth.
    "nav_floor": """<path d="M8 24 L56 24 L52 40 L12 40 Z" fill="#fff"/>
<g fill="#000" opacity="0.38"><rect x="16" y="24" width="8" height="8"/><rect x="32" y="24" width="8" height="8"/><rect x="48" y="24" width="7" height="8"/>
<rect x="24" y="32" width="8" height="8"/><rect x="40" y="32" width="8" height="8"/><rect x="13" y="32" width="3" height="8"/></g>
<rect x="18" y="40" width="5" height="18" rx="2" fill="#fff"/><rect x="41" y="40" width="5" height="18" rx="2" fill="#fff"/>
<path d="M28 8 L36 8 L35 20 L29 20 Z" fill="#fff"/>""",
    # Accordion with bellows.
    "nav_band": """<rect x="5" y="12" width="13" height="42" rx="3" fill="#fff"/><rect x="46" y="12" width="13" height="42" rx="3" fill="#fff"/>
<path d="M18 16 L46 16 L46 50 L18 50 Z" fill="#fff" opacity="0.8"/>
<g stroke="#000" stroke-width="2.4" opacity="0.4"><path d="M23 16 L23 50 M28.5 16 L28.5 50 M34 16 L34 50 M39.5 16 L39.5 50"/></g>
<g fill="#000" opacity="0.4"><circle cx="11.5" cy="20" r="2.4"/><circle cx="11.5" cy="28" r="2.4"/><circle cx="11.5" cy="36" r="2.4"/><circle cx="11.5" cy="44" r="2.4"/>
<rect x="49" y="18" width="7" height="3" rx="1"/><rect x="49" y="25" width="7" height="3" rx="1"/><rect x="49" y="32" width="7" height="3" rx="1"/><rect x="49" y="39" width="7" height="3" rx="1"/><rect x="49" y="46" width="7" height="3" rx="1"/></g>""",
    # Rakija bottle and a čokanj.
    "nav_menu": """<path d="M17 6 L25 6 L25 18 Q33 24 33 34 L33 56 Q33 59 30 59 L12 59 Q9 59 9 56 L9 34 Q9 24 17 18 Z" fill="#fff"/>
<rect x="12" y="38" width="18" height="11" rx="1.5" fill="#000" opacity="0.38"/>
<path d="M40 34 L56 34 L54 58 L42 58 Z" fill="#fff"/><path d="M41.5 44 L54.5 44 L54 50 L42 50 Z" fill="#000" opacity="0.3"/>""",
    # Hammer over a plank: building the place up.
    "nav_upgrades": """<rect x="6" y="46" width="52" height="10" rx="3" fill="#fff" opacity="0.75"/>
<g transform="rotate(-35 32 30)"><rect x="29" y="18" width="7" height="34" rx="3" fill="#fff"/>
<path d="M16 8 L46 8 Q50 8 50 12 L50 20 L16 20 Q12 14 16 8 Z" fill="#fff"/></g>""",
    # Signpost with two arrow boards: the road onwards.
    "nav_venues": """<rect x="29" y="8" width="6" height="52" rx="2" fill="#fff"/><rect x="22" y="56" width="20" height="5" rx="2.5" fill="#fff"/>
<path d="M10 12 L46 12 L54 19 L46 26 L10 26 Z" fill="#fff"/><path d="M54 32 L18 32 L10 39 L18 46 L54 46 Z" fill="#fff"/>
<g fill="#000" opacity="0.35"><rect x="16" y="17" width="22" height="4" rx="2"/><rect x="24" y="37" width="24" height="4" rx="2"/></g>""",
    "map": """<path d="M6 14 L22 8 L42 14 L58 8 L58 52 L42 58 L22 52 L6 58 Z" fill="#fff"/>
<path d="M22 8 L22 52 M42 14 L42 58" stroke="#000" stroke-width="2.5" opacity="0.35"/>
<path d="M32 22 C26 22 23 27 25 31 L32 42 L39 31 C41 27 38 22 32 22 Z" fill="#000" opacity="0.4"/><circle cx="32" cy="28" r="3.5" fill="#fff"/>""",
    "gear": """<g transform="translate(32 32)"><path d="M-5 -27 L5 -27 L6.5 -19 L12 -16.5 L19 -21 L25 -14.5 L20 -8 L22.5 -2.5 L30 -1 L30 7 L22 8.5 L19.5 14 L24 21 L17.5 27 L11 22 L5 24.5 L4 32 L-5 32 L-6 24 L-12 21.5 L-19 26 L-25 19.5 L-20 13 L-22.5 7 L-30 6 L-30 -3 L-22 -4.5 L-19.5 -10.5 L-24 -17 L-17.5 -23 L-11 -18 L-6 -20 Z" fill="#fff"/>
<circle r="8.5" fill="#000" opacity="0.45"/></g>""",
    "trophy": """<path d="M17 8 L47 8 L47 24 Q47 40 32 42 Q17 40 17 24 Z" fill="#fff"/>
<path d="M17 13 L8 13 Q8 29 19 31 M47 13 L56 13 Q56 29 45 31" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round"/>
<rect x="28" y="42" width="8" height="8" fill="#fff"/><rect x="17" y="50" width="30" height="8" rx="2.5" fill="#fff"/>
<path d="M32 15 L34.5 21 L41 21 L36 25 L38 31 L32 27.5 L26 31 L28 25 L23 21 L29.5 21 Z" fill="#000" opacity="0.35"/>""",
    "note": """<path d="M26 12 L52 6 L52 42" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/>
<path d="M26 12 L26 48" stroke="#fff" stroke-width="5"/>
<ellipse cx="19" cy="49" rx="9" ry="7" fill="#fff" transform="rotate(-20 19 49)"/><ellipse cx="45" cy="43" rx="9" ry="7" fill="#fff" transform="rotate(-20 45 43)"/>""",
    "close": """<path d="M16 16 L48 48 M48 16 L16 48" stroke="#fff" stroke-width="8" stroke-linecap="round"/>""",
    "lock": """<path d="M20 30 L20 21 Q20 9 32 9 Q44 9 44 21 L44 30" fill="none" stroke="#fff" stroke-width="6"/>
<rect x="12" y="28" width="40" height="30" rx="6" fill="#fff"/><circle cx="32" cy="41" r="4.5" fill="#000" opacity="0.45"/><rect x="30" y="42" width="4" height="9" fill="#000" opacity="0.45"/>""",
    "check": """<path d="M12 34 L26 48 L52 18" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>""",
    "clock": """<circle cx="32" cy="32" r="24" fill="none" stroke="#fff" stroke-width="6"/><path d="M32 18 L32 33 L42 39" fill="none" stroke="#fff" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>""",
    "people": """<circle cx="23" cy="20" r="9" fill="#fff"/><path d="M7 52 Q7 33 23 33 Q39 33 39 52 Z" fill="#fff"/>
<circle cx="44" cy="23" r="8" fill="#fff" opacity="0.8"/><path d="M33 52 Q35 36 44 36 Q57 36 57 52 Z" fill="#fff" opacity="0.8"/>""",
    "arrow": """<path d="M14 32 L48 32 M34 18 L48 32 L34 46" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>""",
}


# ---------------------------------------------------------------------------------------------
# Upgrade and event pictures: small outlined isometric objects in the world's style
# ---------------------------------------------------------------------------------------------

def picture(draw, size: float = 120) -> str:
    c = Canvas()
    draw(c)
    w, h = c.x1 - c.x0, c.y1 - c.y0
    side = max(w, h) + 10
    cx, cy = (c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2
    defs = f"<defs>{''.join(c.defs)}</defs>" if c.defs else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size * 2:g}" height="{size * 2:g}" '
            f'viewBox="{cx - side / 2:.1f} {cy - side / 2:.1f} {side:.1f} {side:.1f}">{defs}{"".join(c.items)}</svg>\n')


def p_table(c: Canvas) -> None:
    c.cylinder(0.5, 0.5, 0, 0.06, 40, "#5a3a22")
    c.box(0.12, 0.12, 40, 0.76, 0.76, 6, RED)
    for i in range(4):
        for j in range(4):
            if (i + j) % 2:
                c.poly([P(0.12 + i * 0.19, 0.12 + j * 0.19, 46), P(0.31 + i * 0.19, 0.12 + j * 0.19, 46),
                        P(0.31 + i * 0.19, 0.31 + j * 0.19, 46), P(0.12 + i * 0.19, 0.31 + j * 0.19, 46)], CREAM, None)
    c.top_quad(0.12, 0.12, 46, 0.76, 0.76, "none")
    c.box(0.42, 0.42, 46, 0.12, 0.12, 18, "#dfeff0")
    c.box(0.62, 0.3, 46, 0.1, 0.1, 12, "#f2c14e")


def p_waiter(c: Canvas) -> None:
    # Bow tie, white shirt and a tray with a glass: the waiter reduced to his uniform.
    c.poly([(-26, 20), (26, 20), (30, 64), (-30, 64)], "#f8f4ea")
    c.poly([(-30, 20), (-12, 20), (-4, 64), (-34, 64)], "#2b2b33")
    c.poly([(30, 20), (12, 20), (4, 64), (34, 64)], "#2b2b33")
    c.poly([(-12, 16), (0, 22), (12, 16), (12, 28), (0, 22), (-12, 28)], RED)
    c.ellipse(0, -8, 22, 24, "#f2cfae")
    c.raw(f'<path d="M-22 -14 Q-20 -36 0 -36 Q20 -36 22 -14 Q12 -24 0 -22 Q-12 -24 -22 -14 Z" fill="#3a2a1a" stroke="{INK}" stroke-width="1.7"/>', [(-22, -36), (22, -14)])
    c.raw(f'<path d="M-8 -6 Q-8 -9 -6 -9 M8 -6 Q8 -9 6 -9" stroke="{INK}" stroke-width="2.4" fill="none" stroke-linecap="round"/>'
          f'<path d="M-6 4 Q0 9 6 4" stroke="{INK}" stroke-width="2.2" fill="none" stroke-linecap="round"/>'
          f'<path d="M-12 -2 Q0 -1 12 -2" stroke="#3a2a1a" stroke-width="3" fill="none" stroke-linecap="round"/>')
    c.ellipse(46, 10, 22, 7, "#c9ced6")
    c.poly([(40, 10), (52, 10), (50, -10), (42, -10)], "#dfeff0")
    c.poly([(41, 2), (51, 2), (50, -6), (42, -6)], "#f2c14e", None)


def p_bar(c: Canvas) -> None:
    c.box(0, 0, 0, 1.2, 0.5, 52, "#7a4a2c", top="#a8754a")
    c.box(0.02, 0.48, 6, 1.16, 0.04, 40, "#5a3620", outline=False)
    colors = ["#3d8a4f", "#c9a24a", "#b8302f", "#e8e2c8", "#7a3b5a"]
    for k, color in enumerate(colors):
        x = 0.12 + k * 0.2
        c.box(x, 0.12, 52, 0.12, 0.12, 30, color)
        c.box(x + 0.035, 0.155, 82, 0.05, 0.05, 12, color)


def p_speaker(c: Canvas) -> None:
    c.box(0, 0, 0, 0.6, 0.45, 96, "#2e2e36")
    for z, r in ((26, 15), (70, 10)):
        x, y = P(0.3, 0.45, z)
        c.ellipse(x, y, r, r * 0.95, "#4a4a55")
        c.ellipse(x, y, r * 0.45, r * 0.43, "#15151a")


def p_plant(c: Canvas) -> None:
    c.cylinder(0.5, 0.5, 0, 0.24, 34, "#b0532f")
    rng = random.Random(3)
    for k in range(9):
        a = k * math.tau / 9
        x0, y0 = P(0.5, 0.5, 34)
        x1, y1 = x0 + math.cos(a) * 30, y0 - 26 - math.sin(a) * 14 - rng.uniform(0, 14)
        c.raw(f'<path d="M{x0:.1f} {y0:.1f} Q{(x0 + x1) / 2 + 8:.1f} {y1 - 10:.1f} {x1:.1f} {y1:.1f} Q{(x0 + x1) / 2 - 6:.1f} {(y0 + y1) / 2:.1f} {x0:.1f} {y0:.1f} Z" '
              f'fill="{"#4f9a4a" if k % 2 else "#3d7f3b"}" stroke="{INK}" stroke-width="1.6"/>', [(x0, y0), (x1, y1 - 12)])


def p_sign(c: Canvas) -> None:
    # Sandwich chalkboard on the pavement, seen from the front.
    c.raw(f'<path d="M-30 -48 L30 -48 L44 52 L34 52 L28 8 L-28 8 L-34 52 L-44 52 Z" fill="#6b4128" stroke="{INK}" stroke-width="1.8" stroke-linejoin="round"/>'
          f'<path d="M-27 -42 L27 -42 L31 4 L-31 4 Z" fill="#2c3a33" stroke="{INK}" stroke-width="1.5"/>'
          f'<rect x="-34" y="-58" width="68" height="14" rx="4" fill="{RED}" stroke="{INK}" stroke-width="1.8"/>'
          f'<path d="M-16 -30 L16 -30 M-20 -18 L20 -18 M-18 -6 L12 -6" stroke="{CREAM}" stroke-width="3" stroke-linecap="round"/>'
          f'<circle cx="20" cy="-6" r="3.5" fill="#ffd36a"/>'
          f'<path d="M-36 52 L-26 52 M26 52 L36 52" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>', [(-44, -58), (44, 54)])


def p_safe(c: Canvas) -> None:
    c.box(0, 0, 0, 0.7, 0.6, 72, "#4a5560", top="#66727e")
    x, y = P(0.35, 0.6, 38)
    c.ellipse(x, y, 13, 12, "#c9a24a")
    c.ellipse(x, y, 5, 5, "#8a6a2a")
    c.line([P(0.08, 0.6, 8), P(0.08, 0.6, 64)], "#2b333b", 2)


def p_grill(c: Canvas) -> None:
    for (x, y) in ((0.05, 0.05), (0.85, 0.05), (0.85, 0.55), (0.05, 0.55)):
        c.box(x, y, 0, 0.06, 0.06, 40, "#333333")
    c.box(0, 0, 40, 0.96, 0.66, 18, "#3a3a40")
    c.top_quad(0.06, 0.06, 58, 0.84, 0.54, "#e0653a")
    for k in range(6):
        a = 0.12 + k * 0.14
        c.line([P(a, 0.08, 59), P(a, 0.58, 59)], "#2a2a2a", 2.2)
    for x, y in ((0.3, 0.25), (0.55, 0.4), (0.7, 0.2)):
        px, py = P(x, y, 62)
        c.raw(f'<rect x="{px - 12:.1f}" y="{py - 4:.1f}" width="24" height="8" rx="4" fill="#7a3f22" stroke="{INK}" stroke-width="1.4" transform="rotate(-26 {px:.1f} {py:.1f})"/>', [(px - 12, py - 6), (px + 12, py + 6)])
    for k in range(3):
        sx, sy = P(0.3 + k * 0.2, 0.3, 80)
        c.raw(f'<path d="M{sx:.1f} {sy:.1f} q-8 -12 0 -24 q8 -12 0 -24" stroke="#d8d8e0" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.8"/>', [(sx - 8, sy - 48), (sx + 8, sy)])


def p_bouncer(c: Canvas) -> None:
    # Broad black jacket, sunglasses and an earpiece.
    c.poly([(-40, 18), (40, 18), (46, 70), (-46, 70)], "#22222a")
    c.poly([(-10, 18), (10, 18), (4, 46), (-4, 46)], "#f8f4ea")
    c.poly([(-3, 22), (3, 22), (2, 44), (-2, 44)], "#22222a", None)
    c.ellipse(0, -10, 24, 26, "#d9a37e")
    c.raw(f'<path d="M-24 -18 Q-22 -38 0 -38 Q22 -38 24 -18 Q12 -30 0 -28 Q-12 -30 -24 -18 Z" fill="#1e1e22" stroke="{INK}" stroke-width="1.7"/>', [(-24, -38), (24, -18)])
    c.raw(f'<rect x="-17" y="-14" width="14" height="9" rx="3" fill="#15151a"/><rect x="3" y="-14" width="14" height="9" rx="3" fill="#15151a"/>'
          f'<path d="M-3 -10 L3 -10" stroke="#15151a" stroke-width="2.5"/><path d="M-6 6 L6 6" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>'
          f'<path d="M24 -6 Q30 4 22 14" stroke="#c9ced6" stroke-width="2" fill="none"/>')


def p_lantern(c: Canvas) -> None:
    c.box(0.45, 0.45, 0, 0.1, 0.1, 120, "#3a2a1a")
    x, y = P(0.5, 0.5, 120)
    c.raw(f'<path d="M{x - 40:.1f} {y + 6:.1f} Q{x:.1f} {y + 26:.1f} {x + 40:.1f} {y + 6:.1f}" stroke="#3a2a1a" stroke-width="2" fill="none"/>', [(x - 40, y), (x + 40, y + 26)])
    for k, t in enumerate((0.15, 0.5, 0.85)):
        lx = x - 40 + 80 * t
        ly = y + 6 + 20 * (1 - (2 * t - 1) ** 2)
        c.raw(f'<circle cx="{lx:.1f}" cy="{ly + 8:.1f}" r="16" fill="#ffd36a" opacity="0.35"/>')
        c.ellipse(lx, ly + 8, 6, 8, "#ffd36a")
    c.top_quad(0.1, 0.1, 0, 0.8, 0.8, "#4f8a45")
    c.box(0.45, 0.45, 0, 0.1, 0.1, 120, "#3a2a1a")


def p_ledger(c: Canvas) -> None:
    c.box(0, 0, 0, 0.9, 0.62, 10, "#6b2f2a")
    c.poly([P(0.04, 0.04, 10), P(0.44, 0.04, 14), P(0.44, 0.58, 14), P(0.04, 0.58, 10)], PAPER)
    c.poly([P(0.46, 0.04, 14), P(0.86, 0.04, 10), P(0.86, 0.58, 10), P(0.46, 0.58, 14)], "#f1e6cc")
    for k in range(5):
        y = 0.12 + k * 0.09
        c.line([P(0.1, y, 12), P(0.38, y, 13.5)], "#9a8a72", 1.4)
        c.line([P(0.52, y, 13.5), P(0.8, y, 11)], "#9a8a72", 1.4)
    # A pen and a stack of coins.
    c.line([P(0.6, 0.7, 14), P(0.95, 0.4, 16)], "#2b2b33", 4)
    for k in range(4):
        c.cylinder(1.12, 0.25, k * 7, 0.12, 7, "#d9a531", top="#f3d27a")


def p_fight(c: Canvas) -> None:
    # A broken glass and flying shards.
    c.poly([(-22, -30), (22, -30), (16, 34), (-16, 34)], "#dfeff0")
    c.poly([(-22, -30), (-6, -30), (-12, -14), (2, -8), (-8, 6), (-18, 4)], "#ffffff", INK, 1.2)
    for x, y, a in ((-44, -36, 20), (40, -40, -30), (46, 6, 45), (-46, 14, -15)):
        c.raw(f'<path d="M{x} {y} l10 -4 l-3 12 Z" fill="#dfeff0" stroke="{INK}" stroke-width="1.6" transform="rotate({a} {x} {y})"/>', [(x - 10, y - 10), (x + 12, y + 12)])
    c.raw(f'<path d="M-30 -48 L-22 -40 M30 -50 L24 -42 M0 -56 L0 -46" stroke="{RED}" stroke-width="4" stroke-linecap="round"/>', [(-30, -56), (30, -40)])


def p_clipboard(c: Canvas) -> None:
    c.raw(f'<rect x="-30" y="-40" width="60" height="80" rx="6" fill="#a8754a" stroke="{INK}" stroke-width="1.7"/>'
          f'<rect x="-24" y="-30" width="48" height="64" rx="2" fill="{PAPER}" stroke="{INK}" stroke-width="1.4"/>'
          f'<rect x="-12" y="-46" width="24" height="12" rx="3" fill="#8a8f98" stroke="{INK}" stroke-width="1.6"/>'
          + "".join(f'<path d="M-16 {y} l6 6 l10 -12" stroke="#3d8a4f" stroke-width="3" fill="none" stroke-linecap="round"/><path d="M4 {y + 2} L18 {y + 2}" stroke="#9a8a72" stroke-width="2.4" stroke-linecap="round"/>' for y in (-18, -2))
          + f'<path d="M-16 16 l12 12 M-4 16 l-12 12" stroke="{RED}" stroke-width="3.5" stroke-linecap="round"/><path d="M4 22 L18 22" stroke="#9a8a72" stroke-width="2.4" stroke-linecap="round"/>',
          [(-30, -46), (30, 40)])


def p_rings(c: Canvas) -> None:
    c.raw(f'<circle cx="-12" cy="6" r="22" fill="none" stroke="{INK}" stroke-width="12"/><circle cx="-12" cy="6" r="22" fill="none" stroke="#e8b84a" stroke-width="7"/>'
          f'<circle cx="14" cy="-2" r="22" fill="none" stroke="{INK}" stroke-width="12"/><circle cx="14" cy="-2" r="22" fill="none" stroke="#f3d27a" stroke-width="7"/>'
          f'<path d="M14 -30 l7 -9 l7 9 l-7 6 Z" fill="#dff2f8" stroke="{INK}" stroke-width="1.6"/>', [(-40, -40), (40, 32)])


def p_candle(c: Canvas) -> None:
    c.raw(f'<circle cx="0" cy="-34" r="28" fill="#ffd36a" opacity="0.3"/>'
          f'<ellipse cx="0" cy="40" rx="30" ry="9" fill="#c9a24a" stroke="{INK}" stroke-width="1.7"/>'
          f'<rect x="-11" y="-14" width="22" height="54" rx="3" fill="#f4ead2" stroke="{INK}" stroke-width="1.7"/>'
          f'<path d="M-11 -10 q5 6 0 12" stroke="#e3d2ae" stroke-width="3" fill="none"/>'
          f'<path d="M0 -44 Q10 -30 0 -20 Q-10 -30 0 -44 Z" fill="#ffb43d" stroke="{INK}" stroke-width="1.5"/>'
          f'<path d="M0 -36 Q4 -29 0 -24 Q-4 -29 0 -36 Z" fill="#fff4c2"/>', [(-30, -62), (30, 49)])


def p_crown(c: Canvas) -> None:
    c.raw(f'<path d="M-38 24 L-44 -22 L-20 0 L0 -34 L20 0 L44 -22 L38 24 Z" fill="url(#cr)" stroke="{INK}" stroke-width="2"/>'
          f'<rect x="-40" y="22" width="80" height="14" rx="3" fill="#c99232" stroke="{INK}" stroke-width="2"/>'
          f'<circle cx="0" cy="8" r="7" fill="{RED}" stroke="{INK}" stroke-width="1.6"/><circle cx="-24" cy="12" r="5" fill="#3d8a4f" stroke="{INK}" stroke-width="1.4"/><circle cx="24" cy="12" r="5" fill="{NAVY}" stroke="{INK}" stroke-width="1.4"/>'
          + "".join(f'<circle cx="{x}" cy="{y}" r="4.5" fill="#f3d27a" stroke="{INK}" stroke-width="1.4"/>' for x, y in ((-44, -22), (0, -34), (44, -22))),
          [(-48, -40), (48, 36)])
    c.defs.append(vgrad("cr", [(0, "#f8de92"), (1, "#d9a531")]))


PICTURES = {
    "upgrades/dodatni_sto": p_table, "upgrades/konobar": p_waiter, "upgrades/bolji_sank": p_bar,
    "upgrades/ozvucenje": p_speaker, "upgrades/dekor": p_plant, "upgrades/oglas": p_sign, "upgrades/sef": p_safe,
    "upgrades/kuhinja": p_grill, "upgrades/izbacivac": p_bouncer, "upgrades/basta": p_lantern,
    "upgrades/knjigovodja": p_ledger,
    "events/tuca": p_fight, "events/inspekcija": p_clipboard, "events/svadba": p_rings,
    "events/nestanak_struje": p_candle, "events/vip_gost": p_crown,
}

# ---------------------------------------------------------------------------------------------
# Modern-kafana pieces: floating HUD pills, glossy round buttons, cards with a cloth trim
# ---------------------------------------------------------------------------------------------

def pill_dark() -> str:
    """Translucent dark pill for HUD counters, with a soft top sheen."""
    w, h, r = 96, 76, 34
    body = (rrect(0, 4, w, h - 4, r, "#000000", extra=' opacity="0.28"')
            + rrect(2, 2, w - 4, h - 8, r - 2, "#1a1428", "#0b0814", 2.5, ' fill-opacity="0.72"')
            + f'<path d="M{r} 9 L{w - r} 9" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.18"/>')
    return svg(w, h, body)


def round_button(fill_top: str, fill_bottom: str, lip: str, pressed: bool = False, size: int = 120) -> str:
    """Glossy round button with a darker lip and a highlight, like a polished enamel badge."""
    c = size / 2
    depth = 8
    drop = depth if pressed else 0
    r = c - 4
    body = (f'<ellipse cx="{c}" cy="{c + depth + 3}" rx="{r}" ry="{r * 0.96}" fill="#000" opacity="0.25"/>'
            f'<circle cx="{c}" cy="{c + depth}" r="{r}" fill="{lip}" stroke="#2b1d14" stroke-width="4"/>'
            f'<circle cx="{c}" cy="{c + drop}" r="{r}" fill="url(#rb)" stroke="#2b1d14" stroke-width="4"/>'
            f'<ellipse cx="{c}" cy="{c + drop - r * 0.42}" rx="{r * 0.62}" ry="{r * 0.28}" fill="#ffffff" opacity="0.32"/>')
    return svg(size, size + depth + 6, body, vgrad("rb", [(0, fill_top), (1, fill_bottom)]))


def card() -> str:
    """Cream card with a soft shadow and a fine warm edge."""
    w, h, r = 120, 120, 30
    body = (rrect(0, 8, w, h - 8, r, "#000000", extra=' opacity="0.3"')
            + rrect(2, 2, w - 4, h - 12, r - 2, "#fbf3e2", "#2b1d14", 3.5)
            + rrect(8, 8, w - 16, h - 24, r - 8, "none", "#ead9b6", 2))
    return svg(w, h, body)


def row() -> str:
    """List row inside a card: white with a light edge and a little depth."""
    w, h, r = 96, 96, 22
    body = (rrect(0, 4, w, h - 4, r, "#c9b48c", extra=' opacity="0.55"')
            + rrect(1.5, 1.5, w - 3, h - 7, r - 1, "#ffffff", "#e3d2ae", 2.5))
    return svg(w, h, body)


def header() -> str:
    """The card header: a red band with folded ends and a gold edge."""
    w, h = 220, 92
    tail = 30
    body = (f'<path d="M0 22 L{tail + 6} 22 L{tail + 6} 80 L0 80 L12 51 Z" fill="#8f2422" stroke="#2b1d14" stroke-width="3.5" stroke-linejoin="round"/>'
            f'<path d="M{w} 22 L{w - tail - 6} 22 L{w - tail - 6} 80 L{w} 80 L{w - 12} 51 Z" fill="#8f2422" stroke="#2b1d14" stroke-width="3.5" stroke-linejoin="round"/>'
            + rrect(tail - 6, 4, w - 2 * tail + 12, 68, 10, "url(#hd)", "#2b1d14", 4)
            + f'<path d="M{tail + 6} 12 L{w - tail - 6} 12" stroke="#ffffff" stroke-width="3" opacity="0.25" stroke-linecap="round"/>')
    return svg(w, h, body, vgrad("hd", [(0, "#e5574b"), (1, "#b52f2b")]))


def checker_strip() -> str:
    """Tablecloth trim: two rows of red and cream checks, tileable."""
    w, h = 32, 16
    body = ""
    for row_ in range(2):
        for col in range(4):
            colour = "#c0322c" if (row_ + col) % 2 == 0 else "#f6eedc"
            body += f'<rect x="{col * 8}" y="{row_ * 8}" width="8" height="8" fill="{colour}"/>'
    return svg(w, h, body)


def close_button(pressed: bool = False) -> str:
    size = 88
    c = size / 2
    drop = 5 if pressed else 0
    body = (f'<circle cx="{c}" cy="{c + 5}" r="{c - 4}" fill="#7a1a17" stroke="#2b1d14" stroke-width="4"/>'
            f'<circle cx="{c}" cy="{c + drop}" r="{c - 4}" fill="url(#cl)" stroke="#2b1d14" stroke-width="4"/>'
            f'<path d="M{c - 13} {c - 13 + drop} L{c + 13} {c + 13 + drop} M{c + 13} {c - 13 + drop} L{c - 13} {c + 13 + drop}" stroke="#ffffff" stroke-width="8" stroke-linecap="round"/>')
    return svg(size, size + 6, body, vgrad("cl", [(0, "#ef6a5c"), (1, "#c0322c")]))


def badge() -> str:
    size = 44
    c = size / 2
    body = (f'<circle cx="{c}" cy="{c}" r="{c - 3}" fill="#e23b2e" stroke="#ffffff" stroke-width="3.5"/>'
            f'<path d="M{c} {c - 10} L{c} {c + 3}" stroke="#fff" stroke-width="5" stroke-linecap="round"/><circle cx="{c}" cy="{c + 10}" r="3" fill="#fff"/>')
    return svg(size, size, body)


PIECES = {
    "bar_back": bar_back, "bar_back_light": bar_back_light, "bar_fill": bar_fill,
    "night_tile": night_tile, "divider": divider, "button_disabled": button_disabled,
    "ring_paper": lambda: ring("paper"), "ring_dark": lambda: ring("dark"),
    "toggle_on": lambda: toggle(True), "toggle_off": lambda: toggle(False),
    "pill_dark": pill_dark, "card": card, "row": row, "header": header, "checker_strip": checker_strip, "badge": badge,
    "close": close_button, "close_pressed": lambda: close_button(True),
    "round_cream": lambda: round_button("#fffaf0", "#efdcb4", "#b8955a"),
    "round_cream_pressed": lambda: round_button("#fffaf0", "#efdcb4", "#b8955a", True),
    "round_red": lambda: round_button("#ef6a5c", "#c0322c", "#7a1a17", False, 168),
    "round_red_pressed": lambda: round_button("#ef6a5c", "#c0322c", "#7a1a17", True, 168),
    "round_gold": lambda: round_button("#ffd95a", "#f0a01c", "#a8620c", False, 150),
    "round_gold_pressed": lambda: round_button("#ffd95a", "#f0a01c", "#a8620c", True, 150),
}


def main() -> None:
    for folder in ("", "glyphs", "upgrades", "events"):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    for name, make in PIECES.items():
        (OUT / f"{name}.svg").write_text(make(), encoding="utf-8")
    for name in BUTTONS:
        (OUT / f"button_{name}.svg").write_text(button(name), encoding="utf-8")
        (OUT / f"button_{name}_pressed.svg").write_text(button(name, True), encoding="utf-8")
    for name, body in GLYPHS.items():
        (OUT / "glyphs" / f"{name}.svg").write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64">{body}</svg>\n', encoding="utf-8")
    for name, draw in PICTURES.items():
        (OUT / f"{name}.svg").write_text(picture(draw), encoding="utf-8")
    print(f"UI kit: {len(PIECES) + 2 * len(BUTTONS)} pieces, {len(GLYPHS)} glyphs, {len(PICTURES)} pictures in {OUT}")


if __name__ == "__main__":
    main()
