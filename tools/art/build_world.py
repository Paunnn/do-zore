"""Build the isometric kafana: room backgrounds, furniture, decor and emotes for every venue.

Writes SVG sprites to client/assets/world and the layout/anchor data to world.json.

    python tools/art/build_world.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

from isokit import INK, LINE, TH, TW, Canvas, P, mix, shade

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/world"
WALL_H = 236.0
TOP_ROWS = 4          # rows reserved at the back for the stage and the bar
PITCH = 4             # tiles between table centres
STAGE_W, STAGE_D, STAGE_Z = 4, 3, 20.0

THEMES = {
    "birtija": dict(cols=3, rows=2, floor="#8f6a46", floor2="#83603e", floor_style="planks", wall="#cdb07a", wall_pattern="stripes",
                    wainscot="#6e4a2e", trim="#4f3420", table="bare", cloth="#a0703f", cloth2="#a0703f", chair="#8a5a32", cushion="",
                    stage="#7a5232", skirt="#5a3a22", bar="#7a5232", bar_top="#9a6a3a", curtain="#6a5a3a", lights="bulbs", open=False),
    "kafana": dict(cols=4, rows=4, floor="#b9834e", floor2="#ad7746", floor_style="planks", wall="#2f6b6a", wall_pattern="diamonds",
                   wainscot="#5a3a24", trim="#3f2716", table="cloth", cloth="#f4efe4", cloth2="#cf4b42", chair="#8a5a32", cushion="#b8302f",
                   stage="#8a5a32", skirt="#a32a2a", bar="#6a4228", bar_top="#a8743c", curtain="#9a2a2a", lights="string", open=False),
    "restoran": dict(cols=5, rows=5, floor="#e9e1d0", floor2="#c9bfae", floor_style="marble", wall="#efe3c8", wall_pattern="panels",
                     wainscot="#2f5b47", trim="#c9a24a", table="cloth", cloth="#fbf9f4", cloth2="#fbf9f4", chair="#5a3a2a", cushion="#7a2236",
                     stage="#3a2a22", skirt="#2f5b47", bar="#3a2a22", bar_top="#c9a24a", curtain="#7a2236", lights="chandelier", open=False),
    "splav": dict(cols=6, rows=5, floor="#b39874", floor2="#a58a66", floor_style="deck", wall="#1b3b5a", wall_pattern="water",
                  wainscot="#6a4a30", trim="#4a3220", table="cloth", cloth="#f4f6f8", cloth2="#2f6fb0", chair="#f2f2ee", cushion="#2f6fb0",
                  stage="#2a2a33", skirt="#2f6fb0", bar="#6a4a30", bar_top="#c9a24a", curtain="#2f6fb0", lights="lanterns", open=True),
}


def write(name: str, canvas: Canvas, anchor, manifest: dict, scale: float = 2.0, fixed=None) -> None:
    text, info = canvas.svg(anchor, scale=scale, fixed=fixed)
    path = OUT / f"{name}.svg"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    manifest[name] = info


# ---------------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------------

def layout(theme: dict) -> dict:
    cols, rows = theme["cols"], theme["rows"]
    W = PITCH * cols
    D = TOP_ROWS + PITCH * rows + 1
    tables = []
    for j in range(rows):
        for i in range(cols):
            tables.append([2 + PITCH * i, TOP_ROWS + 1 + PITCH * j])
    bar_x0 = STAGE_W + 2
    musicians = []
    for n in range(1, 7):
        spots = []
        for k in range(n):
            t = (k + 0.5) / n
            spots.append([round(0.55 + t * 3.0, 2), round(2.45 - t * 2.0, 2)])
        musicians.append(spots)
    door = [0.0, D - 3.0]
    blocked = []
    for x in range(W):
        for y in range(D):
            if (x < STAGE_W and y < STAGE_D) or (x >= bar_x0 and y < 2):
                blocked.append([x, y])
    for tx, ty in tables:
        blocked.append([tx, ty])
    plants = [[W - 1, 2], [STAGE_W, 0]] if not theme["open"] else []
    for p in plants:
        blocked.append(p)
    return {
        "w": W, "d": D, "tables": tables, "stage": [0, 0, STAGE_W, STAGE_D, STAGE_Z], "musicians": musicians,
        "bar": [bar_x0, 1.0, W - bar_x0 - 0.6, 0.7], "bartender": [bar_x0 + (W - bar_x0) / 2, 0.45],
        "waiter_home": [bar_x0 - 0.5, 2.6], "door": door, "entry": [0.5, D - 2.4], "bouncer": [0.6, D - 1.3],
        "blocked": blocked, "plants": plants, "stools": [[bar_x0 + 0.6 + 1.2 * k, 2.15] for k in range(int((W - bar_x0 - 1) / 1.2))],
    }


# ---------------------------------------------------------------------------------------------
# Room background (floor, walls and everything flat on them)
# ---------------------------------------------------------------------------------------------

def floor(c: Canvas, theme: dict, W: int, D: int, rng: random.Random) -> None:
    style = theme["floor_style"]
    base, alt = theme["floor"], theme["floor2"]
    c.poly([P(0, 0), P(W, 0), P(W, D), P(0, D)], base, INK, 2.2)
    if style in ("planks", "deck"):
        # Planks run along x; each row of planks is a third of a tile wide.
        step = 1 / 3
        y = 0.0
        row = 0
        while y < D - 1e-6:
            x = -rng.random() * 2.5
            while x < W:
                length = rng.uniform(1.6, 3.2)
                xa, xb = max(0.0, x), min(W, x + length)
                if xb - xa > 0.05:
                    tone = shade(base if (row + int(x * 7)) % 3 else alt, rng.uniform(-0.05, 0.04))
                    c.poly([P(xa, y), P(xb, y), P(xb, y + step), P(xa, y + step)], tone, shade(base, -0.32), 0.9)
                    if style == "planks" and rng.random() < 0.35:
                        gx, gy = P(rng.uniform(xa, xb), y + step * 0.5)
                        c.ellipse(gx, gy, 3.2, 1.3, "none", shade(base, -0.25), 0.7)
                x += length
            y += step
            row += 1
    elif style == "marble":
        for x in range(W):
            for y in range(D):
                tone = base if (x + y) % 2 == 0 else alt
                c.poly([P(x, y), P(x + 1, y), P(x + 1, y + 1), P(x, y + 1)], tone, shade(alt, -0.25), 0.8)
                if rng.random() < 0.3:
                    a, b = P(x + rng.random(), y + rng.random()), P(x + rng.random(), y + rng.random())
                    c.line([a, b], shade(tone, -0.12), 0.7)
    c.poly([P(0, 0), P(W, 0), P(W, D), P(0, D)], "none", INK, 2.4)
    # Front edge of the floor (a thick slab so the room reads as a cut-away).
    c.poly([P(W, 0), P(W, D), P(W, D, -14), P(W, 0, -14)], shade(theme["trim"], -0.1), INK, 2)
    c.poly([P(0, D), P(W, D), P(W, D, -14), P(0, D, -14)], theme["trim"], INK, 2)


def wall_pattern(c: Canvas, theme: dict, wall: str, length: float, z0: float, z1: float, rng: random.Random) -> None:
    pattern = theme["wall_pattern"]
    base = theme["wall"]
    if pattern == "diamonds":
        n = int(length * 2)
        for i in range(n):
            a = (i + 0.5) / 2
            for zz in range(int(z0) + 26, int(z1) - 10, 34):
                pts = [c.wall_point(wall, a, zz - 9), c.wall_point(wall, a + 0.12, zz), c.wall_point(wall, a, zz + 9), c.wall_point(wall, a - 0.12, zz)]
                c.poly(pts, shade(base, 0.12), None)
    elif pattern == "stripes":
        n = int(length * 3)
        for i in range(n):
            a = i / 3
            pts = [c.wall_point(wall, a, z0), c.wall_point(wall, a + 0.12, z0), c.wall_point(wall, a + 0.12, z1), c.wall_point(wall, a, z1)]
            c.poly(pts, shade(base, -0.06), None)
        for _ in range(int(length / 3)):
            a, zz = rng.uniform(0.5, length - 0.5), rng.uniform(z0 + 20, z1 - 30)
            x, y = c.wall_point(wall, a, zz)
            c.ellipse(x, y, rng.uniform(8, 16), rng.uniform(5, 9), shade(base, -0.12), None, 0, ' opacity="0.6"')
    elif pattern == "panels":
        for i in range(int(length)):
            a = i + 0.15
            pts = [c.wall_point(wall, a, z0 + 18), c.wall_point(wall, a + 0.7, z0 + 18), c.wall_point(wall, a + 0.7, z1 - 22), c.wall_point(wall, a, z1 - 22)]
            c.poly(pts, shade(base, 0.05), theme["trim"], 1.4)


def wall(c: Canvas, theme: dict, side: str, length: float, rng: random.Random) -> None:
    trim, wain = theme["trim"], theme["wainscot"]
    base = theme["wall"] if side == "right" else shade(theme["wall"], -0.08)
    c.wall_rect(side, 0, 0, length, WALL_H, base, INK, 2.2)
    wall_pattern(c, theme, side, length, 86, WALL_H, rng)
    c.wall_rect(side, 0, 0, length, 78, wain if side == "right" else shade(wain, -0.08), INK, 1.8)
    for i in range(int(length * 2)):
        a = i / 2 + 0.06
        c.wall_rect(side, a, 12, 0.38, 54, shade(wain, 0.08), shade(wain, -0.35), 1.1)
    c.wall_rect(side, 0, 78, length, 8, trim, INK, 1.4)
    c.wall_rect(side, 0, WALL_H - 14, length, 14, trim, INK, 1.6)
    # Wall thickness on the top edge.
    if side == "left":
        c.poly([P(0, 0, WALL_H), P(0, length, WALL_H), P(-0.12, length, WALL_H), P(-0.12, -0.12, WALL_H)], shade(trim, 0.2), INK, 1.6)
    else:
        c.poly([P(0, 0, WALL_H), P(length, 0, WALL_H), P(length, -0.12, WALL_H), P(-0.12, -0.12, WALL_H)], shade(trim, 0.25), INK, 1.6)


def window(c: Canvas, side: str, a: float, z: float, frame: str, wide: float = 1.3) -> None:
    h = 96
    c.wall_rect(side, a - 0.08, z - 8, wide + 0.16, h + 16, frame, INK, 1.8)
    c.wall_rect(side, a, z, wide, h, "#1d2a4a", INK, 1.4)
    # Moon, stars and the town's lights through the glass.
    mx, my = c.wall_point(side, a + wide * 0.7, z + h - 26)
    c.ellipse(mx, my, 9, 9, "#f3e6b0", None)
    c.ellipse(mx + 4, my - 2, 8, 8, "#1d2a4a", None)
    for k in range(5):
        sx, sy = c.wall_point(side, a + 0.1 + k * wide / 5, z + h - 12 - (k * 17) % 30)
        c.ellipse(sx, sy, 1.3, 1.3, "#f3e6b0", None)
    roofs = [c.wall_point(side, a, z), c.wall_point(side, a, z + 22), c.wall_point(side, a + wide * 0.3, z + 34),
             c.wall_point(side, a + wide * 0.5, z + 20), c.wall_point(side, a + wide * 0.8, z + 30), c.wall_point(side, a + wide, z + 18), c.wall_point(side, a + wide, z)]
    c.poly(roofs, "#13182c", None)
    for k in range(3):
        wx, wy = c.wall_point(side, a + 0.2 + k * wide * 0.3, z + 10 + (k % 2) * 8)
        c.ellipse(wx, wy, 2.2, 2.6, "#f0c040", None)
    c.raw(f'<path d="M{c.wall_point(side, a + wide / 2, z)[0]:.1f} {c.wall_point(side, a + wide / 2, z)[1]:.1f} L{c.wall_point(side, a + wide / 2, z + h)[0]:.1f} {c.wall_point(side, a + wide / 2, z + h)[1]:.1f}" stroke="{frame}" stroke-width="4"/>')
    c.wall_rect(side, a - 0.14, z - 14, wide + 0.28, 8, shade(frame, 0.15), INK, 1.4)
    # Curtains.
    for edge in (a - 0.1, a + wide - 0.18):
        c.wall_rect(side, edge, z - 4, 0.28, h + 10, "#a8433a", INK, 1.2)


def picture(c: Canvas, side: str, a: float, z: float, kind: str, rng: random.Random, gold: bool = False) -> None:
    frame = "#c9a24a" if gold else "#5a3a22"
    w, h = (0.62, 64) if kind != "landscape" else (0.95, 56)
    c.wall_rect(side, a - 0.06, z - 7, w + 0.12, h + 14, frame, INK, 1.6)
    if kind == "landscape":
        c.wall_rect(side, a, z, w, h, "#8fc0d8", INK, 1)
        hill = [c.wall_point(side, a, z), c.wall_point(side, a, z + 22), c.wall_point(side, a + w * 0.35, z + 36), c.wall_point(side, a + w * 0.7, z + 24), c.wall_point(side, a + w, z + 30), c.wall_point(side, a + w, z)]
        c.poly(hill, "#5f9a4a", None)
        sx, sy = c.wall_point(side, a + w * 0.75, z + h - 14)
        c.ellipse(sx, sy, 6, 6, "#f3d36a", None)
        hx, hy = c.wall_point(side, a + w * 0.3, z + 20)
        c.poly([(hx - 6, hy + 4), (hx - 6, hy - 6), (hx, hy - 12), (hx + 6, hy - 6), (hx + 6, hy + 4)], "#f4efe4", INK, 0.8)
    elif kind == "portrait":
        c.wall_rect(side, a, z, w, h, "#c8b490", INK, 1)
        px, py = c.wall_point(side, a + w / 2, z + 36)
        c.ellipse(px, py + 10, 13, 9, "#3a3a44", None)
        c.ellipse(px, py - 6, 9, 10, "#efc29c", INK, 0.9)
        c.raw(f'<path d="M{px - 9:.1f} {py - 8:.1f} Q{px:.1f} {py - 20:.1f} {px + 9:.1f} {py - 8:.1f}" fill="#3a2a22"/>')
        c.raw(f'<path d="M{px - 4:.1f} {py - 1:.1f} Q{px:.1f} {py - 3:.1f} {px + 4:.1f} {py - 1:.1f}" stroke="#3a2a22" stroke-width="2" fill="none"/>')
    elif kind == "accordion":
        c.wall_rect(side, a, z, w, h, "#f4e8c8", INK, 1)
        px, py = c.wall_point(side, a + w / 2, z + 32)
        c.raw(f'<rect x="{px - 14:.1f}" y="{py - 12:.1f}" width="28" height="22" rx="2" fill="#c0392b" stroke="{INK}" stroke-width="1"/>'
              f'<path d="M{px - 6:.1f} {py - 12:.1f} L{px - 6:.1f} {py + 10:.1f} M{px:.1f} {py - 12:.1f} L{px:.1f} {py + 10:.1f} M{px + 6:.1f} {py - 12:.1f} L{px + 6:.1f} {py + 10:.1f}" stroke="{INK}" stroke-width="1"/>')
    elif kind == "team":
        c.wall_rect(side, a, z, w, h, "#e8e2d2", INK, 1)
        for k in range(5):
            px, py = c.wall_point(side, a + 0.08 + k * 0.11, z + 30 + (k % 2) * 6)
            c.ellipse(px, py, 3.2, 3.6, "#efc29c", INK, 0.6)
            c.raw(f'<rect x="{px - 3.5:.1f}" y="{py + 3:.1f}" width="7" height="9" fill="#c0392b" stroke="{INK}" stroke-width="0.6"/>')


def kilim(c: Canvas, side: str, a: float, z: float, w: float = 1.5, h: float = 110) -> None:
    """Pirot kilim hung on the wall: red field, dark border, stepped diamonds."""
    c.wall_rect(side, a, z, w, h, "#b8302f", INK, 1.6)
    c.wall_rect(side, a + 0.06, z + 6, w - 0.12, h - 12, "#8a1f22", None)
    c.wall_rect(side, a + 0.12, z + 12, w - 0.24, h - 24, "#c94a3a", None)
    for k in range(3):
        cx = a + w * (k + 0.5) / 3
        for scale, color in [(1.0, "#1f3b5a"), (0.62, "#f0c040"), (0.3, "#f4efe4")]:
            dz, da = 30 * scale, 0.2 * scale
            pts = [c.wall_point(side, cx, z + h / 2 + dz), c.wall_point(side, cx + da, z + h / 2), c.wall_point(side, cx, z + h / 2 - dz), c.wall_point(side, cx - da, z + h / 2)]
            c.poly(pts, color, None)
    for k in range(9):
        fx, fy = c.wall_point(side, a + 0.08 + k * (w - 0.16) / 8, z)
        c.line([(fx, fy), (fx, fy + 6)], "#f0c040", 1.4)


def shelf(c: Canvas, side: str, a: float, length: float, z: float, wood: str, rng: random.Random, bottles: int = 10) -> None:
    c.wall_rect(side, a, z, length, 7, wood, INK, 1.4)
    colors = ["#2f7a4a", "#b8732a", "#d9c8a0", "#7a2236", "#3a6ea5", "#c9a24a", "#e8e4dc"]
    for k in range(bottles):
        t = (k + 0.5) / bottles
        bx, by = c.wall_point(side, a + t * length, z + 7)
        col = rng.choice(colors)
        hgt = rng.uniform(16, 26)
        c.raw(f'<path d="M{bx - 3.2:.1f} {by:.1f} L{bx - 3.2:.1f} {by - hgt * 0.62:.1f} Q{bx - 3.2:.1f} {by - hgt * 0.75:.1f} {bx - 1.3:.1f} {by - hgt * 0.8:.1f} '
              f'L{bx - 1.3:.1f} {by - hgt:.1f} L{bx + 1.3:.1f} {by - hgt:.1f} L{bx + 1.3:.1f} {by - hgt * 0.8:.1f} Q{bx + 3.2:.1f} {by - hgt * 0.75:.1f} {bx + 3.2:.1f} {by - hgt * 0.62:.1f} L{bx + 3.2:.1f} {by:.1f} Z" '
              f'fill="{col}" stroke="{INK}" stroke-width="1"/>'
              f'<rect x="{bx - 2.6:.1f}" y="{by - hgt * 0.45:.1f}" width="5.2" height="{hgt * 0.22:.1f}" fill="#f4efe4" opacity="0.85"/>', [(bx - 4, by - hgt), (bx + 4, by)])


def door(c: Canvas, side: str, a: float, wood: str) -> None:
    w, h = 1.2, 150
    c.wall_rect(side, a - 0.1, 0, w + 0.2, h + 12, shade(wood, -0.25), INK, 1.8)
    c.wall_rect(side, a, 0, w, h, "#1d2a4a", INK, 1.4)
    # The door stands open into the night; a warm light spills onto the floor.
    c.poly([c.wall_point(side, a, 0), c.wall_point(side, a, h), P(0.45, a + 0.25, h - 4), P(0.45, a + 0.25, 0)], wood, INK, 1.6)
    hx, hy = P(0.32, a + 0.16, 70)
    c.ellipse(hx, hy, 2.4, 2.4, "#f0c040", INK, 0.8)
    # A small red sign above the door.
    c.wall_rect(side, a + 0.25, h + 18, w - 0.5, 20, "#c0392b", INK, 1.4)
    c.wall_rect(side, a + 0.32, h + 23, w - 0.64, 10, "#f0c040", None)


def room(theme_name: str, theme: dict, lay: dict, manifest: dict) -> None:
    rng = random.Random(sum(map(ord, theme_name)))
    c = Canvas()
    lights = lay.setdefault("lights", [])
    W, D = lay["w"], lay["d"]
    if theme["open"]:
        # A raft on the river at night: water all around, railings instead of walls.
        far = 2.5
        c.poly([P(-far, -far), P(W + far, -far), P(W + far, D + far), P(-far, D + far)], "#13314f", None)
        for k in range(160):
            x, y = rng.uniform(-far, W + far), rng.uniform(-far, D + far)
            if -0.5 < x < W + 0.5 and -0.5 < y < D + 0.5:
                continue
            px, py = P(x, y)
            c.raw(f'<path d="M{px - 10:.1f} {py:.1f} q5 -3 10 0 q5 3 10 0" stroke="#3f6f9f" stroke-width="1.6" fill="none" opacity="0.7"/>', [(px - 10, py - 3), (px + 10, py + 3)])
        for k in range(40):
            x, y = rng.uniform(-far, W + far), rng.uniform(-far, D + far)
            if -0.5 < x < W + 0.5 and -0.5 < y < D + 0.5:
                continue
            px, py = P(x, y)
            c.raw(f'<path d="M{px - 4:.1f} {py:.1f} L{px + 4:.1f} {py:.1f}" stroke="#f0c040" stroke-width="1.4" opacity="0.6"/>')
        # Pontoons under the deck.
        c.poly([P(W, 0, -14), P(W, D, -14), P(W, D, -34), P(W, 0, -34)], "#3a4a5a", INK, 1.6)
        c.poly([P(0, D, -14), P(W, D, -14), P(W, D, -34), P(0, D, -34)], "#4a5a6a", INK, 1.6)
    floor(c, theme, W, D, rng)
    if not theme["open"]:
        wall(c, theme, "left", D, rng)
        wall(c, theme, "right", W, rng)
        # Stage corner: curtain on both walls behind the stage.
        for side, length in (("left", STAGE_D + 0.4), ("right", STAGE_W + 0.4)):
            c.wall_rect(side, 0, 18, length, WALL_H - 40, theme["curtain"], INK, 1.6)
            for k in range(int(length * 5)):
                a = k / 5 + 0.1
                c.raw(f'<path d="M{c.wall_point(side, a, 22)[0]:.1f} {c.wall_point(side, a, 22)[1]:.1f} L{c.wall_point(side, a, WALL_H - 26)[0]:.1f} {c.wall_point(side, a, WALL_H - 26)[1]:.1f}" stroke="{shade(theme["curtain"], -0.3)}" stroke-width="2"/>')
            c.wall_rect(side, 0, WALL_H - 36, length, 16, shade(theme["curtain"], 0.15), INK, 1.4)
        bar_x0 = lay["bar"][0]
        shelf(c, "right", bar_x0 + 0.2, W - bar_x0 - 0.6, 110, theme["trim"], rng, int((W - bar_x0) * 3))
        shelf(c, "right", bar_x0 + 0.2, W - bar_x0 - 0.6, 152, theme["trim"], rng, int((W - bar_x0) * 2.5))
        mirror_x = bar_x0 + (W - bar_x0) / 2 - 0.6
        c.wall_rect("right", mirror_x, 186, 1.2, 30, "#c9d8de" if theme_name != "birtija" else "#8a6a46", INK, 1.4)
        # Left wall: windows and decor between the stage and the door; right wall: one window.
        window(c, "right", STAGE_W + 0.35, 104, theme["trim"], 1.1)
        gold = theme_name == "restoran"
        slots = [a for a in range(STAGE_D + 1, D - 4, 3)]
        kinds = ["kilim", "window", "picture", "window", "kilim", "picture"] if theme_name == "kafana" else \
                ["window", "picture", "window", "picture", "window", "picture"]
        pics = ["landscape", "portrait", "accordion", "team"] if theme_name != "restoran" else ["landscape", "portrait", "landscape", "portrait"]
        for i, a in enumerate(slots):
            kind = kinds[i % len(kinds)]
            if kind == "kilim":
                kilim(c, "left", a + 0.2, 100, 1.5, 104)
            elif kind == "window":
                window(c, "left", a + 0.3, 100, theme["trim"], 1.2)
            else:
                picture(c, "left", a + 0.5, 128, pics[i % len(pics)], rng, gold)
        door(c, "left", lay["door"][1], theme["trim"])
        if theme["lights"] == "string":
            for side, length in (("left", D), ("right", W)):
                n = int(length * 1.5)
                for k in range(n):
                    a0, a1 = k / 1.5, (k + 1) / 1.5
                    p0, p1 = c.wall_point(side, a0, WALL_H - 26), c.wall_point(side, a1, WALL_H - 26)
                    mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + 16)
                    c.raw(f'<path d="M{p0[0]:.1f} {p0[1]:.1f} Q{mid[0]:.1f} {mid[1]:.1f} {p1[0]:.1f} {p1[1]:.1f}" stroke="#2b1d14" stroke-width="1.4" fill="none"/>')
                    c.ellipse(mid[0], mid[1] - 7, 3.4, 4.2, "#ffe7a0", INK, 1)
                    lights.append([round(mid[0], 1), round(mid[1] - 7, 1), 0])
        if theme["lights"] == "bulbs":
            for side, length in (("left", D), ("right", W)):
                for k in range(2, int(length), 4):
                    p = c.wall_point(side, k, WALL_H - 50)
                    c.raw(f'<path d="M{p[0]:.1f} {p[1] - 6:.1f} l0 -14" stroke="{INK}" stroke-width="1.4"/>')
                    c.ellipse(p[0], p[1], 5, 6, "#ffe7a0", INK, 1.2)
                    lights.append([round(p[0], 1), round(p[1], 1), 1])
    else:
        # Railings along the back edges of the deck and lantern poles at the corners.
        for side, length in (("left", D), ("right", W)):
            c.wall_rect(side, 0, 34, length, 7, theme["wainscot"], INK, 1.4)
            c.wall_rect(side, 0, 16, length, 5, theme["wainscot"], INK, 1.2)
            for k in range(int(length) + 1):
                p0, p1 = c.wall_point(side, k, 0), c.wall_point(side, k, 42)
                c.line([p0, p1], INK, 5)
                c.line([p0, p1], theme["wainscot"], 3)
    if theme["open"]:
        lay["poles"] = [[0.35, 0.35]] + [[float(k), 0.3] for k in range(6, W, 6)] + [[0.3, float(k)] for k in range(6, D - 3, 6)]
    if theme["lights"] == "chandelier":
        for side, length in (("left", D), ("right", W)):
            for k in range(3, int(length) - 1, 4):
                p = c.wall_point(side, k, WALL_H - 70)
                c.raw(f'<path d="M{p[0] - 8:.1f} {p[1] + 8:.1f} L{p[0] + 8:.1f} {p[1] + 8:.1f} L{p[0]:.1f} {p[1] - 2:.1f} Z" fill="#c9a24a" stroke="{INK}" stroke-width="1.2"/>')
                c.ellipse(p[0], p[1] - 8, 5, 8, "#ffe7a0", INK, 1.2)
                lights.append([round(p[0], 1), round(p[1] - 8, 1), 1])
    # Keep the room texture within ~3800 px; it is VRAM-compressed on import.
    write(f"room_{theme_name}", c, P(0, 0), manifest, scale=min(1.5, 3800 / max(1.0, c.x1 - c.x0 + 8)))


# ---------------------------------------------------------------------------------------------
# Furniture
# ---------------------------------------------------------------------------------------------

def chair(theme_name: str, theme: dict, facing: str, manifest: dict) -> None:
    """facing: 'se' = seat on the back-left of a table looking down-right; 'nw' = front chair looking up-left."""
    c = Canvas()
    wood = theme["chair"]
    s = 0.17
    seat_z = 22
    cx, cy = 0.0, 0.0
    legs = [(-s + 0.03, -s + 0.03), (s - 0.03, -s + 0.03), (s - 0.03, s - 0.03), (-s + 0.03, s - 0.03)]
    back_side = "w" if facing == "se" else "e"

    def backrest():
        if back_side == "w":
            c.box(cx - s, cy - s, seat_z, 0.07, 2 * s, 34, wood)
            c.box(cx - s - 0.01, cy - s, seat_z + 30, 0.09, 2 * s, 8, shade(wood, 0.05))
        else:
            c.box(cx + s - 0.07, cy - s, seat_z, 0.07, 2 * s, 34, wood)
            c.box(cx + s - 0.08, cy - s, seat_z + 30, 0.09, 2 * s, 8, shade(wood, 0.05))

    if back_side == "w":
        backrest()
    for lx, ly in legs:
        c.box(cx + lx - 0.025, cy + ly - 0.025, 0, 0.05, 0.05, seat_z, shade(wood, -0.1))
    c.box(cx - s, cy - s, seat_z, 2 * s, 2 * s, 5, wood)
    if theme["cushion"]:
        c.box(cx - s + 0.03, cy - s + 0.03, seat_z + 5, 2 * s - 0.06, 2 * s - 0.06, 4, theme["cushion"])
    if back_side == "e":
        backrest()
    write(f"{theme_name}_chair_{facing}", c, P(cx, cy), manifest)


def table(theme_name: str, theme: dict, manifest: dict) -> None:
    c = Canvas()
    h = 30
    r = 0.42
    wood = shade(theme["chair"], -0.05) if theme["table"] == "cloth" else theme["cloth"]
    c.box(-0.05, -0.05, 0, 0.1, 0.1, h, shade(wood, -0.2))
    c.ellipse(*P(0, 0), 20, 9, shade(wood, -0.25), INK, 1.4)
    if theme["table"] == "bare":
        c.box(-r, -r, h, 2 * r, 2 * r, 6, wood)
        for k in range(1, 4):
            t = -r + 2 * r * k / 4
            c.line([P(t, -r, h + 6), P(t, r, h + 6)], shade(wood, -0.25), 1)
    else:
        drop = 16
        base, alt = theme["cloth"], theme["cloth2"]
        # Draped sides.
        for side in ("l", "r"):
            if side == "l":
                pts = [P(-r - 0.04, r + 0.04, h + 3), P(r + 0.04, r + 0.04, h + 3), P(r + 0.04, r + 0.04, h + 3 - drop), P(-r - 0.04, r + 0.04, h + 3 - drop)]
            else:
                pts = [P(r + 0.04, -r - 0.04, h + 3), P(r + 0.04, r + 0.04, h + 3), P(r + 0.04, r + 0.04, h + 3 - drop), P(r + 0.04, -r - 0.04, h + 3 - drop)]
            c.poly(pts, shade(base, -0.06 if side == "l" else -0.16))
            if alt != base:
                n = 5
                for k in range(n):
                    for row in range(2):
                        if (k + row) % 2 == 0:
                            continue
                        t0, t1 = -r - 0.04 + (2 * r + 0.08) * k / n, -r - 0.04 + (2 * r + 0.08) * (k + 1) / n
                        z0, z1 = h + 3 - drop * row / 2, h + 3 - drop * (row + 1) / 2
                        if side == "l":
                            q = [P(t0, r + 0.04, z0), P(t1, r + 0.04, z0), P(t1, r + 0.04, z1), P(t0, r + 0.04, z1)]
                        else:
                            q = [P(r + 0.04, t0, z0), P(r + 0.04, t1, z0), P(r + 0.04, t1, z1), P(r + 0.04, t0, z1)]
                        c.poly(q, shade(alt, -0.06 if side == "l" else -0.16), None)
            c.poly(pts, "none")
            c.line([pts[3], pts[2]], INK, 1.4)
        c.top_quad(-r - 0.04, -r - 0.04, h + 3, 2 * r + 0.08, 2 * r + 0.08, base)
        if alt != base:
            n = 5
            for i in range(n):
                for j in range(n):
                    if (i + j) % 2:
                        x0 = -r - 0.04 + (2 * r + 0.08) * i / n
                        y0 = -r - 0.04 + (2 * r + 0.08) * j / n
                        c.top_quad(x0, y0, h + 3, (2 * r + 0.08) / n, (2 * r + 0.08) / n, alt, None)
            c.top_quad(-r - 0.04, -r - 0.04, h + 3, 2 * r + 0.08, 2 * r + 0.08, "none")
        if theme_name == "restoran":
            # Candle and a small vase on white linen.
            vx, vy = P(0.1, -0.1, h + 3)
            c.raw(f'<rect x="{vx - 2:.1f}" y="{vy - 14:.1f}" width="4" height="14" fill="#f4efe4" stroke="{INK}" stroke-width="1"/><ellipse cx="{vx:.1f}" cy="{vy - 17:.1f}" rx="2" ry="3.2" fill="#f0c040"/>')
    write(f"{theme_name}_table", c, P(0, 0), manifest)
    manifest[f"{theme_name}_table"]["top_z"] = h + 3


def bar_counter(theme_name: str, theme: dict, lay: dict, manifest: dict) -> None:
    c = Canvas()
    x0, y0, length, depth = lay["bar"]
    h = 46
    wood = theme["bar"]
    c.box(x0, y0, 0, length, depth, h, wood)
    for k in range(int(length * 2)):
        a = x0 + k / 2 + 0.07
        c.poly([P(a, y0 + depth, 8), P(a + 0.36, y0 + depth, 8), P(a + 0.36, y0 + depth, h - 10), P(a, y0 + depth, h - 10)], shade(wood, 0.08), shade(wood, -0.35), 1.1)
    c.box(x0 - 0.05, y0 - 0.05, h, length + 0.1, depth + 0.1, 6, theme["bar_top"])
    # Beer taps, glasses and the cash register.
    tx, ty = P(x0 + 1.0, y0 + 0.3, h + 6)
    c.raw(f'<rect x="{tx - 12:.1f}" y="{ty - 26:.1f}" width="24" height="7" rx="2" fill="#c9ced3" stroke="{INK}" stroke-width="1.2"/>'
          + "".join(f'<path d="M{tx - 8 + k * 8:.1f} {ty - 19:.1f} l0 10" stroke="{INK}" stroke-width="3"/><path d="M{tx - 8 + k * 8:.1f} {ty - 19:.1f} l0 10" stroke="#e8e4dc" stroke-width="1.6"/><circle cx="{tx - 8 + k * 8:.1f}" cy="{ty - 30:.1f}" r="3" fill="{["#c0392b", "#f0c040", "#2f7a4a"][k]}" stroke="{INK}" stroke-width="1"/>' for k in range(3)),
          [(tx - 12, ty - 34), (tx + 12, ty)])
    rx, ry = P(x0 + length - 1.2, y0 + 0.35, h + 6)
    c.raw(f'<path d="M{rx - 14:.1f} {ry:.1f} L{rx - 12:.1f} {ry - 16:.1f} L{rx + 12:.1f} {ry - 16:.1f} L{rx + 14:.1f} {ry:.1f} Z" fill="#3a3a44" stroke="{INK}" stroke-width="1.2"/>'
          f'<rect x="{rx - 9:.1f}" y="{ry - 26:.1f}" width="18" height="10" fill="#9fd8b0" stroke="{INK}" stroke-width="1.2"/>', [(rx - 14, ry - 26), (rx + 14, ry)])
    for k in range(3):
        gx, gy = P(x0 + 2.2 + k * 0.5, y0 + 0.45, h + 6)
        c.raw(f'<path d="M{gx - 3:.1f} {gy - 9:.1f} L{gx + 3:.1f} {gy - 9:.1f} L{gx + 2.4:.1f} {gy:.1f} L{gx - 2.4:.1f} {gy:.1f} Z" fill="#e8f2f4" fill-opacity="0.7" stroke="{INK}" stroke-width="1"/>')
    write(f"{theme_name}_bar", c, P(x0 + length, y0 + depth), manifest)


def stool(theme_name: str, theme: dict, manifest: dict) -> None:
    c = Canvas()
    c.box(-0.03, -0.03, 0, 0.06, 0.06, 30, "#3a3a44")
    c.ellipse(*P(0, 0), 12, 5, "#3a3a44", INK, 1.2)
    c.cylinder(0, 0, 30, 0.13, 7, theme["cushion"] or theme["chair"])
    write(f"{theme_name}_stool", c, P(0, 0), manifest)


def stage(theme_name: str, theme: dict, manifest: dict) -> None:
    c = Canvas()
    c.box(0, 0, 0, STAGE_W, STAGE_D, STAGE_Z, theme["stage"], top=shade(theme["stage"], 0.18), left=theme["skirt"], right=shade(theme["skirt"], -0.2))
    for k in range(1, STAGE_W * 3):
        a = k / 3
        c.line([P(a, 0, STAGE_Z), P(a, STAGE_D, STAGE_Z)], shade(theme["stage"], -0.15), 1)
    for k in range(STAGE_D * 4):
        y = k / 4
        c.line([P(STAGE_W, y + 0.08, 3), P(STAGE_W, y + 0.08, STAGE_Z - 3)], shade(theme["skirt"], -0.4), 1.2)
    for k in range(STAGE_W * 4):
        x = k / 4
        c.line([P(x + 0.08, STAGE_D, 3), P(x + 0.08, STAGE_D, STAGE_Z - 3)], shade(theme["skirt"], -0.3), 1.2)
    # Footlights on the front edges.
    for k in range(STAGE_W * 2):
        lx, ly = P(k / 2 + 0.25, STAGE_D, STAGE_Z)
        c.ellipse(lx, ly, 3, 2, "#ffe7a0", INK, 0.8)
    for k in range(STAGE_D * 2):
        lx, ly = P(STAGE_W, k / 2 + 0.25, STAGE_Z)
        c.ellipse(lx, ly, 3, 2, "#ffe7a0", INK, 0.8)
    write(f"{theme_name}_stage", c, P(STAGE_W, STAGE_D), manifest)


def speaker(manifest: dict, big: bool) -> None:
    c = Canvas()
    s = 0.22 if big else 0.16
    h = 70 if big else 46
    c.box(-s, -s, 0, 2 * s, 2 * s, h, "#2b2b33")
    for k, zz in enumerate([h * 0.3, h * 0.72]):
        x, y = P(s, 0, zz)
        r = 9 if k == 0 or big else 6
        c.ellipse(x - 1, y, r * 0.6, r, "#4a4a55", INK, 1.2)
        c.ellipse(x - 1, y, r * 0.25, r * 0.4, "#15151a", None)
    write("speaker_big" if big else "speaker_small", c, P(0, 0), manifest)


def plant(manifest: dict, kind: str) -> None:
    c = Canvas()
    rng = random.Random(kind)
    c.cylinder(0, 0, 0, 0.16, 26, "#b8653a")
    c.ellipse(*P(0, 0, 26), 16, 8, "#4a2e1c", INK, 1.2)
    if kind == "ficus":
        leaves = [(rng.uniform(-22, 22), rng.uniform(-80, -32)) for _ in range(26)]
        x0, y0 = P(0, 0, 26)
        c.line([(x0, y0), (x0, y0 - 46)], "#5a3a22", 4)
        for dx, dy in sorted(leaves, key=lambda v: v[1]):
            col = rng.choice(["#3f8a4f", "#4f9a5a", "#2f7a42", "#5fae6a"])
            c.raw(f'<ellipse cx="{x0 + dx:.1f}" cy="{y0 + dy:.1f}" rx="9" ry="5.5" fill="{col}" stroke="{INK}" stroke-width="1.1" transform="rotate({rng.uniform(-40, 40):.0f} {x0 + dx:.1f} {y0 + dy:.1f})"/>',
                  [(x0 + dx - 10, y0 + dy - 10), (x0 + dx + 10, y0 + dy + 10)])
    else:
        x0, y0 = P(0, 0, 26)
        for k in range(9):
            ang = -math.pi / 2 + (k - 4) * 0.32
            ex, ey = x0 + math.cos(ang) * 34, y0 + math.sin(ang) * 40
            c.raw(f'<path d="M{x0:.1f} {y0:.1f} Q{(x0 + ex) / 2 - 6:.1f} {(y0 + ey) / 2:.1f} {ex:.1f} {ey:.1f} Q{(x0 + ex) / 2 + 6:.1f} {(y0 + ey) / 2 + 4:.1f} {x0:.1f} {y0:.1f} Z" fill="{rng.choice(["#3f8a4f", "#4f9a5a"])}" stroke="{INK}" stroke-width="1.1"/>',
                  [(ex - 4, ey - 4), (ex + 4, ey + 4)])
    write(f"plant_{kind}", c, P(0, 0), manifest)


def barrel(manifest: dict) -> None:
    c = Canvas()
    c.cylinder(0, 0, 0, 0.22, 44, "#8a5a32")
    for zz in (8, 36):
        x, y = P(0, 0, zz)
        rx = 0.22 * TW / 2 * math.sqrt(2)
        c.raw(f'<path d="M{x - rx:.1f} {y:.1f} A{rx:.1f} {rx / 2:.1f} 0 0 0 {x + rx:.1f} {y:.1f}" stroke="#3a3a44" stroke-width="3" fill="none"/>')
    write("barrel", c, P(0, 0), manifest)


def piano(manifest: dict) -> None:
    c = Canvas()
    c.box(-0.5, -0.3, 0, 1.0, 0.55, 58, "#1a1a20", top="#2a2a33")
    c.box(-0.5, 0.25, 30, 1.0, 0.15, 6, "#f4f1ea", top="#f4f1ea")
    for k in range(10):
        x = -0.48 + k * 0.1
        c.line([P(x, 0.27, 36.5), P(x, 0.38, 36.5)], INK, 0.8)
    write("piano", c, P(0.5, 0.4), manifest)


def safe(manifest: dict) -> None:
    c = Canvas()
    c.box(-0.25, -0.25, 0, 0.5, 0.5, 44, "#5a6a72")
    x, y = P(0.25, 0, 24)
    c.ellipse(x, y, 5, 8, "#c9ced3", INK, 1.2)
    write("safe", c, P(0.25, 0.25), manifest)


def chandelier(manifest: dict) -> None:
    c = Canvas()
    c.line([(0, -70), (0, -30)], INK, 1.6)
    c.ellipse(0, -28, 26, 8, "#c9a24a", INK, 1.4)
    for k in range(7):
        ang = k / 7 * math.tau
        x, y = math.cos(ang) * 22, -28 + math.sin(ang) * 7
        c.raw(f'<rect x="{x - 1.6:.1f}" y="{y - 12:.1f}" width="3.2" height="12" fill="#f4efe4" stroke="{INK}" stroke-width="0.8"/><ellipse cx="{x:.1f}" cy="{y - 15:.1f}" rx="2.4" ry="3.6" fill="#ffd36a"/>', [(x - 3, y - 19), (x + 3, y)])
    for k in range(8):
        x = -20 + k * 5.7
        c.raw(f'<path d="M{x:.1f} -24 l0 9" stroke="#e8f2f4" stroke-width="1.4"/><circle cx="{x:.1f}" cy="-14" r="1.8" fill="#e8f2f4" stroke="{INK}" stroke-width="0.6"/>', [(x - 2, -24), (x + 2, -12)])
    write("chandelier", c, (0, 0), manifest)


def lantern_pole(manifest: dict) -> None:
    c = Canvas()
    c.box(-0.03, -0.03, 0, 0.06, 0.06, 150, "#3a3a44")
    x, y = P(0, 0, 150)
    c.raw(f'<path d="M{x - 9:.1f} {y:.1f} L{x - 7:.1f} {y - 20:.1f} L{x + 7:.1f} {y - 20:.1f} L{x + 9:.1f} {y:.1f} Z" fill="#ffd36a" stroke="{INK}" stroke-width="1.4"/>'
          f'<path d="M{x - 11:.1f} {y - 20:.1f} L{x:.1f} {y - 30:.1f} L{x + 11:.1f} {y - 20:.1f} Z" fill="#3a3a44" stroke="{INK}" stroke-width="1.4"/>', [(x - 11, y - 30), (x + 11, y)])
    write("lantern_pole", c, P(0, 0), manifest)


def tv(manifest: dict) -> None:
    """Wall TV on the right wall showing a football match (placed as a sorted sprite near the wall)."""
    c = Canvas()
    w = 1.0
    pts = [P(0, 0.02, 150), P(w, 0.02, 150), P(w, 0.02, 205), P(0, 0.02, 205)]
    c.poly(pts, "#1a1a20")
    inner = [P(0.06, 0.03, 155), P(w - 0.06, 0.03, 155), P(w - 0.06, 0.03, 200), P(0.06, 0.03, 200)]
    c.poly(inner, "#3f9a4a", None)
    mx, my = P(w / 2, 0.03, 177)
    c.ellipse(mx, my, 6, 4, "none", "#f4f4f4", 1)
    c.line([P(w / 2, 0.03, 155), P(w / 2, 0.03, 200)], "#f4f4f4", 1)
    for k in range(4):
        px, py = P(0.2 + k * 0.18, 0.03, 165 + (k % 2) * 14)
        c.ellipse(px, py, 1.6, 2.2, "#c0392b" if k % 2 else "#f4f4f4", None)
    write("tv", c, P(0, 0), manifest)


def rug(theme_name: str, manifest: dict, w: float, d: float) -> None:
    c = Canvas()
    c.top_quad(0, 0, 1, w, d, "#a32a2a")
    c.top_quad(0.12, 0.12, 1, w - 0.24, d - 0.24, "#c94a3a", None)
    for k in range(int(w)):
        cx = k + 0.5
        for s, col in ((0.42, "#1f3b5a"), (0.26, "#f0c040"), (0.12, "#f4efe4")):
            c.poly([P(cx - s, d / 2, 1), P(cx, d / 2 - s, 1), P(cx + s, d / 2, 1), P(cx, d / 2 + s, 1)], col, None)
    c.top_quad(0, 0, 1, w, d, "none")
    write(f"rug_{theme_name}", c, P(0, 0), manifest)


# ---------------------------------------------------------------------------------------------
# Emotes and pickups (screen-space sprites)
# ---------------------------------------------------------------------------------------------

def emotes(manifest: dict) -> None:
    def save(name, body, w, h):
        path = OUT / "fx" / f"{name}.svg"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * 2}" height="{h * 2}" viewBox="0 0 {w} {h}">{body}</svg>\n', encoding="utf-8")
        manifest[f"fx/{name}"] = {"w": w, "h": h, "ox": w / 2, "oy": h, "scale": 2}

    cloud = ('<path d="M18 46 Q4 46 6 34 Q2 22 14 18 Q16 6 30 8 Q38 0 48 8 Q62 4 64 18 Q76 22 72 34 Q74 46 60 46 Z" '
             f'fill="#ffffff" stroke="{INK}" stroke-width="2.4" stroke-linejoin="round"/>'
             f'<circle cx="30" cy="54" r="4.5" fill="#ffffff" stroke="{INK}" stroke-width="2"/><circle cx="24" cy="62" r="2.6" fill="#ffffff" stroke="{INK}" stroke-width="1.8"/>')
    save("cloud", cloud, 78, 66)
    save("heart", f'<path d="M24 40 C4 26 6 8 18 8 C22 8 24 12 24 14 C24 12 26 8 30 8 C42 8 44 26 24 40 Z" fill="#ff5d7a" stroke="{INK}" stroke-width="2.2"/><ellipse cx="15" cy="15" rx="3.5" ry="2.2" fill="#fff" opacity="0.7"/>', 48, 44)
    face = lambda fill, inner: f'<circle cx="24" cy="24" r="20" fill="{fill}" stroke="{INK}" stroke-width="2.2"/>{inner}'
    save("happy", face("#ffd23f", f'<path d="M14 21 Q17 15 20 21 M28 21 Q31 15 34 21" stroke="{INK}" stroke-width="2.4" fill="none" stroke-linecap="round"/><path d="M13 27 Q24 40 35 27 Z" fill="#8b2e2a" stroke="{INK}" stroke-width="2"/>'), 48, 48)
    save("angry", face("#ff6a3d", f'<path d="M12 15 L20 19 M36 15 L28 19" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/><circle cx="18" cy="23" r="2.6" fill="{INK}"/><circle cx="30" cy="23" r="2.6" fill="{INK}"/>'
                          f'<rect x="12" y="29" width="24" height="9" rx="2" fill="#2b1d14"/><path d="M15 33 l3 -2 l2 3 l3 -3 l2 3 l3 -3 l2 3 l3 -2" stroke="#f4f1ea" stroke-width="1.4" fill="none"/>'), 48, 48)
    save("sleepy", face("#9fd0f0", f'<path d="M13 22 Q17 25 21 22 M27 22 Q31 25 35 22" stroke="{INK}" stroke-width="2.2" fill="none" stroke-linecap="round"/><ellipse cx="24" cy="32" rx="4" ry="3" fill="#2b1d14"/>'
                           f'<path d="M30 6 L38 6 L30 15 L38 15" stroke="{INK}" stroke-width="2.2" fill="none" stroke-linejoin="round"/>'), 48, 48)
    save("note", f'<path d="M18 8 L40 4 L40 34" fill="none" stroke="#ffffff" stroke-width="5" stroke-linejoin="round"/><path d="M18 8 L18 38" stroke="#ffffff" stroke-width="5"/>'
                 f'<ellipse cx="12" cy="38" rx="8" ry="6" fill="#ffffff" transform="rotate(-20 12 38)"/><ellipse cx="34" cy="34" rx="8" ry="6" fill="#ffffff" transform="rotate(-20 34 34)"/>', 48, 46)
    save("cash", f'<g transform="rotate(-12 26 22)"><rect x="6" y="12" width="40" height="22" rx="3" fill="#5fbf5a" stroke="{INK}" stroke-width="2.2"/><rect x="10" y="16" width="32" height="14" rx="2" fill="none" stroke="#2f7a3a" stroke-width="1.4"/>'
                 f'<circle cx="26" cy="23" r="5" fill="#9fe08a" stroke="#2f7a3a" stroke-width="1.4"/></g>'
                 f'<g transform="rotate(8 26 26)"><rect x="8" y="18" width="40" height="22" rx="3" fill="#6fd06a" stroke="{INK}" stroke-width="2.2"/><circle cx="28" cy="29" r="5" fill="#9fe08a" stroke="#2f7a3a" stroke-width="1.4"/></g>', 54, 48)
    save("coin", f'<circle cx="16" cy="16" r="13" fill="#ffc83d" stroke="{INK}" stroke-width="2.2"/><circle cx="16" cy="16" r="8.5" fill="none" stroke="#c98a1a" stroke-width="1.8"/><ellipse cx="12" cy="11" rx="3" ry="2" fill="#fff" opacity="0.7"/>', 32, 32)
    save("pin", f'<path d="M26 58 L16 42 Q4 38 4 24 Q4 4 26 4 Q48 4 48 24 Q48 38 36 42 Z" fill="#ffc83d" stroke="{INK}" stroke-width="2.4" stroke-linejoin="round"/><circle cx="26" cy="24" r="16" fill="#fff3c4" stroke="{INK}" stroke-width="1.6"/>', 52, 60)
    save("plus", f'<circle cx="24" cy="24" r="20" fill="#5fbf5a" stroke="{INK}" stroke-width="2.4"/><path d="M24 13 L24 35 M13 24 L35 24" stroke="#fff" stroke-width="6" stroke-linecap="round"/>', 48, 48)
    save("dust", "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#f4efe4" stroke="{INK}" stroke-width="1.8"/>' for x, y, r in [(20, 34, 12), (36, 26, 14), (54, 34, 12), (30, 44, 10), (46, 44, 11)])
         + f'<path d="M14 14 l6 6 M60 12 l-6 6 M38 6 l0 8" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>', 72, 56)
    save("glow", '<defs><radialGradient id="g"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset="0.35" stop-color="#fff" stop-opacity="0.45"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs><circle cx="32" cy="32" r="32" fill="url(#g)"/>', 64, 64)


# ---------------------------------------------------------------------------------------------

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest: dict = {}
    layouts = {}
    for name, theme in THEMES.items():
        lay = layout(theme)
        layouts[name] = lay
        room(name, theme, lay, manifest)
        table(name, theme, manifest)
        chair(name, theme, "se", manifest)
        chair(name, theme, "nw", manifest)
        bar_counter(name, theme, lay, manifest)
        stool(name, theme, manifest)
        stage(name, theme, manifest)
        rug(name, manifest, 3, 2)
    for big in (False, True):
        speaker(manifest, big)
    for kind in ("ficus", "fern"):
        plant(manifest, kind)
    barrel(manifest)
    piano(manifest)
    safe(manifest)
    chandelier(manifest)
    lantern_pole(manifest)
    tv(manifest)
    emotes(manifest)
    data = {"tile": [TW, TH], "wall_h": WALL_H, "sprites": manifest, "venues": layouts,
            "themes": {k: {"lights": v["lights"], "open": v["open"]} for k, v in THEMES.items()}}
    (OUT / "world.json").write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    print(f"{len(manifest)} sprites; rooms: " + ", ".join(f"{k} {v['w']}x{v['d']} ({len(v['tables'])} slots)" for k, v in layouts.items()))


if __name__ == "__main__":
    main()
