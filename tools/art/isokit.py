"""Isometric vector kit: outlined boxes, cylinders and wall/floor decals in one cartoon style.

Coordinates are tiles on the floor (x runs down-right on screen, y runs down-left) and a
height z in design pixels. A tile is 128x64 design pixels.
"""

from __future__ import annotations

import math

TW, TH = 128.0, 64.0
INK = "#2b1d14"
LINE = 1.7


def P(x: float, y: float, z: float = 0.0) -> tuple:
    return ((x - y) * TW / 2, (x + y) * TH / 2 - z)


def shade(color: str, amount: float) -> str:
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    if amount >= 0:
        r, g, b = (round(c + (255 - c) * amount) for c in (r, g, b))
    else:
        r, g, b = (round(c * (1 + amount)) for c in (r, g, b))
    return f"#{max(0, min(255, r)):02x}{max(0, min(255, g)):02x}{max(0, min(255, b)):02x}"


def mix(a: str, b: str, t: float) -> str:
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


class Canvas:
    """Collects SVG fragments in screen pixels and tracks their bounds."""

    def __init__(self) -> None:
        self.items: list[str] = []
        self.x0 = self.y0 = math.inf
        self.x1 = self.y1 = -math.inf
        self.defs: list[str] = []

    def _grow(self, points) -> None:
        for x, y in points:
            self.x0, self.y0 = min(self.x0, x), min(self.y0, y)
            self.x1, self.y1 = max(self.x1, x), max(self.y1, y)

    def add(self, svg: str, points=()) -> None:
        self.items.append(svg)
        self._grow(points)

    # -- primitives in screen space ------------------------------------------------------------
    def poly(self, pts, fill: str, stroke: str = INK, width: float = LINE, extra: str = "") -> None:
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
        s = f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round"' if stroke else ""
        self.add(f'<path d="{d}" fill="{fill}"{s}{extra}/>', pts)

    def line(self, pts, color: str = INK, width: float = LINE, extra: str = "") -> None:
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)
        self.add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"{extra}/>', pts)

    def ellipse(self, cx, cy, rx, ry, fill, stroke=INK, width=LINE, extra="") -> None:
        s = f' stroke="{stroke}" stroke-width="{width}"' if stroke else ""
        self.add(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"{s}{extra}/>',
                 [(cx - rx, cy - ry), (cx + rx, cy + ry)])

    def raw(self, svg: str, points=()) -> None:
        self.add(svg, points)

    # -- isometric primitives ------------------------------------------------------------------
    def box(self, x, y, z, w, d, h, color, top=None, left=None, right=None, outline=True, faces="tlr") -> None:
        top = top or shade(color, 0.14)
        left = left or color
        right = right or shade(color, -0.2)
        z1 = z + h
        stroke = INK if outline else None
        if "l" in faces:
            self.poly([P(x, y + d, z), P(x + w, y + d, z), P(x + w, y + d, z1), P(x, y + d, z1)], left, stroke)
        if "r" in faces:
            self.poly([P(x + w, y, z), P(x + w, y + d, z), P(x + w, y + d, z1), P(x + w, y, z1)], right, stroke)
        if "t" in faces:
            self.poly([P(x, y, z1), P(x + w, y, z1), P(x + w, y + d, z1), P(x, y + d, z1)], top, stroke)

    def top_quad(self, x, y, z, w, d, fill, stroke=INK, width=LINE) -> None:
        self.poly([P(x, y, z), P(x + w, y, z), P(x + w, y + d, z), P(x, y + d, z)], fill, stroke, width)

    def cylinder(self, x, y, z, r, h, color, top=None, outline=True) -> None:
        """Upright cylinder centred on floor point (x, y); r in tiles."""
        cx, cy = P(x, y, z)
        rx, ry = r * TW / 2 * math.sqrt(2), r * TH / 2 * math.sqrt(2)
        stroke = INK if outline else None
        side = (f'M{cx - rx:.1f} {cy:.1f} L{cx - rx:.1f} {cy - h:.1f} A{rx:.1f} {ry:.1f} 0 0 0 {cx + rx:.1f} {cy - h:.1f} '
                f'L{cx + rx:.1f} {cy:.1f} A{rx:.1f} {ry:.1f} 0 0 1 {cx - rx:.1f} {cy:.1f} Z')
        grad = self.gradient(color)
        s = f' stroke="{INK}" stroke-width="{LINE}"' if outline else ""
        self.add(f'<path d="{side}" fill="url(#{grad})"{s}/>', [(cx - rx, cy - h - ry), (cx + rx, cy + ry)])
        self.ellipse(cx, cy - h, rx, ry, top or shade(color, 0.18), stroke)

    def gradient(self, color: str) -> str:
        name = f"g{len(self.defs)}"
        self.defs.append(f'<linearGradient id="{name}" x1="0" x2="1"><stop offset="0" stop-color="{shade(color, 0.12)}"/>'
                         f'<stop offset="0.55" stop-color="{color}"/><stop offset="1" stop-color="{shade(color, -0.28)}"/></linearGradient>')
        return name

    # -- wall planes ---------------------------------------------------------------------------
    @staticmethod
    def on_left_wall(y, z, x=0.0):
        """Point on the upper-left wall (the x=const plane)."""
        return P(x, y, z)

    @staticmethod
    def on_right_wall(x, z, y=0.0):
        return P(x, y, z)

    def wall_rect(self, wall: str, a: float, z: float, length: float, height: float, fill: str, stroke=INK, width=LINE, offset=0.0) -> None:
        """Rectangle lying on a wall: a/length along the wall in tiles, z/height in pixels."""
        if wall == "left":
            pts = [P(offset, a, z), P(offset, a + length, z), P(offset, a + length, z + height), P(offset, a, z + height)]
        else:
            pts = [P(a, offset, z), P(a + length, offset, z), P(a + length, offset, z + height), P(a, offset, z + height)]
        self.poly(pts, fill, stroke, width)

    def wall_point(self, wall: str, a: float, z: float, offset=0.0) -> tuple:
        return P(offset, a, z) if wall == "left" else P(a, offset, z)

    # -- output --------------------------------------------------------------------------------
    def svg(self, anchor=(0.0, 0.0), pad: float = 4.0, scale: float = 2.0, fixed=None) -> tuple:
        """Return (svg_text, info) where info has the image size and the anchor inside it."""
        if fixed:
            x0, y0, x1, y1 = fixed
        else:
            x0, y0, x1, y1 = self.x0 - pad, self.y0 - pad, self.x1 + pad, self.y1 + pad
        w, h = x1 - x0, y1 - y0
        defs = f"<defs>{''.join(self.defs)}</defs>" if self.defs else ""
        text = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * scale:.0f}" height="{h * scale:.0f}" '
                f'viewBox="{x0:.1f} {y0:.1f} {w:.1f} {h:.1f}">{defs}{"".join(self.items)}</svg>\n')
        return text, {"w": round(w, 1), "h": round(h, 1), "ox": round(anchor[0] - x0, 1), "oy": round(anchor[1] - y0, 1), "scale": scale}
