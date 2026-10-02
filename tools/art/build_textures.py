"""Textures for the 3D city and venues: floors, cloths, walls, streets, rugs, paintings and signs.

Tiling textures are seamless 512x512 PNGs; the game maps them in world space (triplanar), so one
texture covers floors of any size. Rugs, paintings, signs and light pools are single images
mapped by UV. Written to client/assets/textures.

    python tools/art/build_textures.py
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/textures"
FONTS = ROOT / "client/assets/fonts"
N = 512


def rgb(hex_color: str) -> np.ndarray:
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


def noise(size: int, cells: int, seed: int, octaves: int = 4) -> np.ndarray:
    """Seamless value noise in [0, 1]: wraps at the edges so tiles join invisibly."""
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    for octave in range(octaves):
        g = cells * (2 ** octave)
        grid = rng.random((g, g)).astype(np.float32)
        coords = np.arange(size, dtype=np.float32) * g / size
        i0 = np.floor(coords).astype(int) % g
        i1 = (i0 + 1) % g
        t = coords - np.floor(coords)
        t = t * t * (3 - 2 * t)
        rows = grid[i0][:, i0] * (1 - t)[None, :] + grid[i0][:, i1] * t[None, :]
        rows2 = grid[i1][:, i0] * (1 - t)[None, :] + grid[i1][:, i1] * t[None, :]
        layer = rows * (1 - t)[:, None] + rows2 * t[:, None]
        total += layer * amp
        norm += amp
        amp *= 0.5
    return total / norm


def save(name: str, pixels: np.ndarray) -> None:
    Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8)).save(OUT / f"{name}.png", optimize=True)


def shade(base: np.ndarray, amount: np.ndarray) -> np.ndarray:
    """Multiply a colour by a per-pixel brightness map."""
    return base[None, None, :] * amount[..., None]


# ---------------------------------------------------------------------------------------------
# Floors
# ---------------------------------------------------------------------------------------------

def planks(name: str, base: str, board: int, seed: int, gap: str, contrast: float = 0.16, weathered: bool = False) -> None:
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    rows = (y // board).astype(int)
    out = np.zeros((N, N, 3), np.float32)
    grain_noise = noise(N, 8, seed + 1, 3)
    fine = noise(N, 64, seed + 2, 2)
    for r in range(N // board):
        tone = 1.0 + rng.uniform(-contrast, contrast)
        offset = rng.uniform(0, N)
        joint = rng.uniform(0, N)
        mask = rows == r
        xs = x[mask]
        ys = y[mask]
        grain = 0.5 + 0.5 * np.sin((xs + offset) * 0.045 + grain_noise[mask] * 9.0 + (ys % board) * 0.35)
        level = tone * (0.88 + 0.12 * grain) * (0.94 + 0.12 * fine[mask])
        col = rgb(base)[None, :] * level[:, None]
        # Board ends.
        near_joint = np.abs(((xs - joint) % N)) < 2.5
        col[near_joint] *= 0.62
        out[mask] = col
    seam = (y % board) < 2.5
    out[seam] = rgb(gap)
    if weathered:
        stains = noise(N, 6, seed + 3, 4)
        out *= (0.82 + 0.3 * stains)[..., None]
    save(name, out)


def parquet(name: str, base: str, seed: int) -> None:
    """Basket-weave parquet: blocks of three slats, alternating direction."""
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N, 3), np.float32)
    block = 64
    slat = block / 3
    fine = noise(N, 32, seed, 3)
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    bx, by = (x // block).astype(int), (y // block).astype(int)
    horizontal = (bx + by) % 2 == 0
    local = np.where(horizontal, y % block, x % block)
    along = np.where(horizontal, x, y)
    slat_id = (local // slat).astype(int) + bx * 7 + by * 13
    tones = rng.uniform(0.82, 1.12, size=200)
    level = tones[slat_id % 200] * (0.9 + 0.1 * np.sin(along * 0.08 + fine * 6)) * (0.94 + 0.1 * fine)
    out = shade(rgb(base), level)
    edge = (local % slat < 1.6) | (x % block < 1.6) | (y % block < 1.6)
    out[edge] *= 0.6
    save(name, out)


def checker_marble(name: str) -> None:
    y, x = np.mgrid[0:N, 0:N]
    cell = 64
    dark = ((x // cell) + (y // cell)) % 2 == 1
    veins = noise(N, 6, 9, 5)
    vein = np.clip(1 - np.abs(np.sin(veins * 18.0)) * 6, 0, 1)
    light = shade(rgb("#ece6da"), 0.95 + 0.05 * veins) - vein[..., None] * 40
    darkc = shade(rgb("#2c2f38"), 0.9 + 0.15 * veins) + vein[..., None] * 30
    out = np.where(dark[..., None], darkc, light)
    grout = (x % cell < 1.5) | (y % cell < 1.5)
    out[grout] = rgb("#8a8478")
    save(name, out)


# ---------------------------------------------------------------------------------------------
# Cloth
# ---------------------------------------------------------------------------------------------

def gingham(name: str, colour: str, ground: str = "#f6eedc", cell: int = 32) -> None:
    y, x = np.mgrid[0:N, 0:N]
    a = (x // cell) % 2 == 0
    b = (y // cell) % 2 == 0
    weave = 0.93 + 0.07 * ((x + y) % 3 == 0) + 0.05 * noise(N, 64, 3, 2)
    c = rgb(colour)
    g = rgb(ground)
    half = (c + g) / 2
    out = np.where((a & b)[..., None], c, np.where((a | b)[..., None], half, g))
    out = out * weave[..., None]
    save(name, out)


def linen(name: str, base: str) -> None:
    y, x = np.mgrid[0:N, 0:N]
    weave = 0.94 + 0.04 * ((x % 4) < 2) + 0.03 * ((y % 4) < 2) + 0.05 * noise(N, 48, 5, 2)
    save(name, shade(rgb(base), weave))


# ---------------------------------------------------------------------------------------------
# Streets and ground
# ---------------------------------------------------------------------------------------------

def voronoi_stones(name: str, base: str, mortar: str, count: int, seed: int, variance: float = 0.22) -> None:
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2)) * N
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    best = np.full((N, N), 1e9, np.float32)
    second = np.full((N, N), 1e9, np.float32)
    owner = np.zeros((N, N), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(x - px)
        dx = np.minimum(dx, N - dx)
        dy = np.abs(y - py)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < best
        second = np.where(closer, best, np.minimum(second, d))
        owner = np.where(closer, i, owner)
        best = np.where(closer, d, best)
    edge = second - best
    tones = rng.uniform(1 - variance, 1 + variance, size=count)
    fine = noise(N, 32, seed + 1, 3)
    level = tones[owner] * (0.85 + 0.25 * fine)
    # Rounded stones: darker toward their edges.
    level *= np.clip(0.75 + edge / 18.0, 0.75, 1.0)
    out = shade(rgb(base), level)
    out[edge < 3.0] = rgb(mortar) * (0.9 + 0.2 * fine[edge < 3.0])[..., None]
    save(name, out)


def asphalt(name: str) -> None:
    n = noise(N, 128, 11, 2)
    speck = np.random.default_rng(12).random((N, N)) > 0.985
    out = shade(rgb("#3b3d44"), 0.85 + 0.25 * n)
    out[speck] = rgb("#6a6c74")
    save(name, out)


def slabs(name: str, base: str, cell: int, seed: int) -> None:
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:N, 0:N]
    tones = rng.uniform(0.9, 1.08, size=(N // cell + 1, N // cell + 1))
    fine = noise(N, 32, seed, 3)
    out = shade(rgb(base), tones[y // cell, x // cell] * (0.92 + 0.12 * fine))
    out[(x % cell < 2) | (y % cell < 2)] *= 0.72
    save(name, out)


def grass(name: str) -> None:
    n = noise(N, 8, 21, 5)
    blades = noise(N, 128, 22, 2)
    out = shade(rgb("#3f7a3a"), 0.75 + 0.35 * n + 0.15 * blades)
    out[..., 0] *= 0.9 + 0.2 * noise(N, 4, 23, 2)
    save(name, out)


def dirt(name: str) -> None:
    n = noise(N, 16, 31, 4)
    pebbles = np.random.default_rng(32).random((N, N)) > 0.992
    out = shade(rgb("#7a5a3c"), 0.8 + 0.3 * n)
    out[pebbles] = rgb("#a08a6e")
    save(name, out)


# ---------------------------------------------------------------------------------------------
# Walls and roofs
# ---------------------------------------------------------------------------------------------

def plaster(name: str, base: str, seed: int) -> None:
    n = noise(N, 6, seed, 5)
    save(name, shade(rgb(base), 0.9 + 0.14 * n))


def damask(name: str, base: str, motif: str) -> None:
    """Wallpaper: a repeating gold motif on a deep ground, the old kafana look."""
    img = Image.new("RGB", (N, N), base)
    d = ImageDraw.Draw(img)
    step = 128
    for gy in range(0, N + step, step):
        for gx in range(0, N + step, step):
            for ox, oy in ((0, 0), (step // 2, step // 2)):
                cx, cy = gx + ox, gy + oy
                d.polygon([(cx, cy - 34), (cx + 18, cy), (cx, cy + 34), (cx - 18, cy)], outline=motif, width=3)
                d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], fill=motif)
                for s in (-1, 1):
                    d.arc([cx + s * 16 - 14, cy - 30, cx + s * 16 + 14, cy - 2], 0, 360, fill=motif, width=2)
                    d.arc([cx + s * 16 - 14, cy + 2, cx + s * 16 + 14, cy + 30], 0, 360, fill=motif, width=2)
    arr = np.asarray(img).astype(np.float32) * (0.92 + 0.1 * noise(N, 8, 41, 3))[..., None]
    save(name, arr)


def stripes(name: str, a: str, b: str, width: int) -> None:
    x = np.mgrid[0:N, 0:N][1]
    out = np.where(((x // width) % 2 == 0)[..., None], rgb(a), rgb(b)) * (0.95 + 0.06 * noise(N, 8, 51, 3))[..., None]
    save(name, out)


def logs(name: str) -> None:
    """Horizontal timber logs for the village birtija."""
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    h = 64
    local = (y % h) / h
    roundness = np.sin(local * math.pi) ** 0.6
    grain = noise(N, 16, 61, 3)
    rng = np.random.default_rng(62)
    tones = rng.uniform(0.85, 1.1, size=N // h + 1)
    level = (0.55 + 0.5 * roundness) * tones[(y // h).astype(int)] * (0.9 + 0.15 * np.sin(x * 0.05 + grain * 10))
    save(name, shade(rgb("#8a5e3a"), level))


def bricks(name: str, base: str, mortar: str) -> None:
    rng = np.random.default_rng(71)
    y, x = np.mgrid[0:N, 0:N]
    bh, bw = 32, 64
    row = y // bh
    shift = (row % 2) * (bw // 2)
    col = (x + shift) // bw
    tones = rng.uniform(0.82, 1.15, size=(N // bh + 1, N // bw + 2))
    fine = noise(N, 64, 72, 2)
    out = shade(rgb(base), tones[row, col % tones.shape[1]] * (0.9 + 0.15 * fine))
    joint = (y % bh < 3) | ((x + shift) % bw < 3)
    out[joint] = rgb(mortar)
    save(name, out)


def roof_tiles(name: str) -> None:
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    h, w = 32, 32
    row = (y // h).astype(int)
    shift = (row % 2) * (w / 2)
    local_x = ((x + shift) % w) / w
    local_y = (y % h) / h
    curve = np.sin(local_x * math.pi) ** 0.5
    level = (0.6 + 0.45 * curve) * (1.0 - 0.35 * local_y)
    rng = np.random.default_rng(81)
    tones = rng.uniform(0.85, 1.12, size=(N // h + 1, int(N / w) + 3))
    level *= tones[row, (((x + shift) // w).astype(int)) % tones.shape[1]]
    save(name, shade(rgb("#b4532f"), level))


# ---------------------------------------------------------------------------------------------
# Rugs, paintings, signs and light
# ---------------------------------------------------------------------------------------------

def kilim(name: str, ground: str, colours: list, w: int = 512, h: int = 768) -> None:
    img = Image.new("RGB", (w, h), ground)
    d = ImageDraw.Draw(img)
    border = 40
    d.rectangle([0, 0, w - 1, h - 1], outline=colours[0], width=border)
    d.rectangle([border, border, w - border - 1, h - border - 1], outline=colours[2], width=8)
    step = 28
    for k in range(0, w, step):
        d.polygon([(k, 6), (k + step / 2, border - 6), (k + step, 6)], fill=colours[1])
        d.polygon([(k, h - 6), (k + step / 2, h - border + 6), (k + step, h - 6)], fill=colours[1])
    cx = w / 2
    for i, cy in enumerate((h * 0.25, h * 0.5, h * 0.75)):
        for size, colour in ((150, colours[0]), (110, colours[1]), (70, colours[2]), (30, colours[3])):
            s = size if i == 1 else size * 0.75
            pts = [(cx, cy - s), (cx + s * 0.8, cy), (cx, cy + s), (cx - s * 0.8, cy)]
            d.polygon(pts, fill=colour)
    for k in range(0, h, 24):
        for side in (border + 24, w - border - 24):
            d.rectangle([side - 6, k + 4, side + 6, k + 16], fill=colours[3])
    arr = np.asarray(img).astype(np.float32)
    weave = 0.9 + 0.1 * ((np.mgrid[0:h, 0:w][0] % 4) < 2)
    save(name, arr * weave[..., None])


def painting(name: str, kind: str) -> None:
    w, h = 256, 200
    img = Image.new("RGB", (w, h), "#2b2b33")
    d = ImageDraw.Draw(img)
    if kind == "landscape":
        for k in range(h):
            t = k / h
            d.line([(0, k), (w, k)], fill=(int(120 + 100 * t), int(150 + 60 * t), int(190 - 40 * t)))
        d.ellipse([170, 30, 210, 70], fill="#ffe2a0")
        d.polygon([(0, 140), (60, 90), (120, 130), (180, 85), (256, 135), (256, 200), (0, 200)], fill="#4f7a46")
        d.polygon([(0, 165), (90, 140), (160, 170), (256, 150), (256, 200), (0, 200)], fill="#3a5e36")
        for tx in (40, 70, 200):
            d.rectangle([tx, 130, tx + 4, 150], fill="#4a3020")
            d.ellipse([tx - 12, 108, tx + 16, 138], fill="#2f5a35")
    elif kind == "portrait":
        d.rectangle([0, 0, w, h], fill="#3b2a24")
        d.ellipse([88, 40, 168, 130], fill="#d9b08c")
        d.pieslice([60, 110, 196, 260], 180, 360, fill="#1e2433")
        d.rectangle([108, 26, 148, 46], fill="#2a1d14")
        d.line([(110, 104), (146, 104)], fill="#4a2a1a", width=5)
    elif kind == "still":
        d.rectangle([0, 0, w, h], fill="#4a2f2a")
        d.rectangle([0, 150, w, h], fill="#6b4a30")
        d.polygon([(90, 150), (100, 60), (120, 55), (130, 150)], fill="#2f5a35")
        d.ellipse([140, 110, 190, 160], fill="#b8302f")
        d.ellipse([60, 120, 100, 160], fill="#e0a838")
    elif kind == "river":
        for k in range(h):
            t = k / h
            d.line([(0, k), (w, k)], fill=(int(30 + 40 * t), int(40 + 50 * t), int(90 + 60 * t)))
        d.rectangle([0, 120, w, h], fill="#24406e")
        for k in range(9):
            x0 = 10 + k * 28
            d.rectangle([x0, 70 - (k % 3) * 14, x0 + 22, 120], fill="#1a2440")
            d.rectangle([x0 + 6, 84, x0 + 10, 90], fill="#ffd36a")
        d.arc([20, 90, 236, 170], 180, 360, fill="#d9d2c0", width=6)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(OUT / f"{name}.png", optimize=True)


def sign(name: str, text: str, board: str, ink: str, outline: str) -> None:
    w, h = 640, 192
    img = Image.new("RGB", (w, h), board)
    d = ImageDraw.Draw(img)
    grain = noise(512, 16, 91, 3)
    arr = np.asarray(img).astype(np.float32)
    arr *= (0.85 + 0.25 * np.array(Image.fromarray((grain * 255).astype(np.uint8)).resize((w, h))) / 255.0)[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, w - 7, h - 7], outline="#d9a531", width=8)
    font = ImageFont.truetype(str(FONTS / "Shrikhand-Regular.ttf"), 112)
    box = d.textbbox((0, 0), text, font=font)
    tx = (w - (box[2] - box[0])) / 2 - box[0]
    ty = (h - (box[3] - box[1])) / 2 - box[1] - 4
    d.text((tx + 4, ty + 6), text, font=font, fill="#00000088")
    d.text((tx, ty), text, font=font, fill=ink, stroke_width=6, stroke_fill=outline)
    img.save(OUT / f"{name}.png", optimize=True)


def radial(name: str, size: int, inner: tuple, power: float = 1.6) -> None:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.sqrt((x - size / 2) ** 2 + (y - size / 2) ** 2) / (size / 2)
    a = np.clip(1 - r, 0, 1) ** power
    out = np.zeros((size, size, 4), np.float32)
    out[..., 0], out[..., 1], out[..., 2] = inner[0], inner[1], inner[2]
    out[..., 3] = a * 255
    Image.fromarray(out.astype(np.uint8), "RGBA").save(OUT / f"{name}.png", optimize=True)


def slot_marker(name: str) -> None:
    """Dashed outline where a table can be bought, mapped onto the floor."""
    size = 256
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([14, 14, size - 15, size - 15], radius=36, fill=(255, 255, 255, 28))
    inset, dash, gap = 14, 26, 16
    edge = size - 2 * inset
    for side in range(4):
        pos = 36
        while pos < edge - 36:
            a, b = pos, min(pos + dash, edge - 36)
            if side == 0: d.line([(inset + a, inset), (inset + b, inset)], fill=(255, 255, 255, 190), width=7)
            if side == 1: d.line([(size - inset, inset + a), (size - inset, inset + b)], fill=(255, 255, 255, 190), width=7)
            if side == 2: d.line([(inset + a, size - inset), (inset + b, size - inset)], fill=(255, 255, 255, 190), width=7)
            if side == 3: d.line([(inset, inset + a), (inset, inset + b)], fill=(255, 255, 255, 190), width=7)
            pos += dash + gap
    for cx, cy in ((inset + 36, inset + 36), (size - inset - 36, inset + 36), (inset + 36, size - inset - 36), (size - inset - 36, size - inset - 36)):
        start = {(inset + 36, inset + 36): 180, (size - inset - 36, inset + 36): 270, (inset + 36, size - inset - 36): 90, (size - inset - 36, size - inset - 36): 0}[(cx, cy)]
        d.arc([cx - 36, cy - 36, cx + 36, cy + 36], start, start + 90, fill=(255, 255, 255, 190), width=7)
    img.save(OUT / f"{name}.png", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    planks("planks_rough", "#a8784a", 64, 1, "#3a2414", 0.18, weathered=True)
    planks("planks_walnut", "#7a4a2a", 32, 2, "#2a160c", 0.14)
    planks("planks_deck", "#9a8468", 64, 3, "#2e261e", 0.12, weathered=True)
    planks("planks_honey", "#b98250", 32, 4, "#4a2c18", 0.1)
    parquet("parquet", "#a86a3c", 5)
    checker_marble("marble_checker")
    gingham("cloth_red", "#c0322c")
    gingham("cloth_blue", "#2f5fa8")
    linen("linen", "#f7f3ea")
    voronoi_stones("cobble", "#6e6a66", "#2c2a28", 260, 7)
    voronoi_stones("stone_wall", "#9a9184", "#5a544c", 90, 8, 0.15)
    asphalt("asphalt")
    slabs("paving", "#a29c92", 64, 9)
    slabs("sidewalk", "#8c8780", 48, 10)
    grass("grass")
    dirt("dirt")
    plaster("plaster_warm", "#e6cfa6", 11)
    plaster("plaster_white", "#efe9de", 12)
    plaster("plaster_blue", "#9fb3c6", 13)
    plaster("plaster_rose", "#d9a596", 14)
    damask("damask_red", "#6e1f22", "#c9963c")
    stripes("stripes_cream", "#efe4cc", "#e6d7b8", 24)
    logs("logs")
    bricks("bricks", "#9a4a32", "#c9bba5")
    roof_tiles("roof_tiles")
    kilim("rug_kilim", "#a3302c", ["#1f3b5a", "#d9a531", "#f3e8cf", "#2b1d14"])
    kilim("rug_persian", "#5a1f2a", ["#1f2a44", "#c9963c", "#e8d8b8", "#8a2f2a"])
    kilim("rug_blue", "#24406e", ["#f3e8cf", "#c0322c", "#9fb3c6", "#1a2440"])
    for kind in ("landscape", "portrait", "still", "river"):
        painting(f"painting_{kind}", kind)
    sign("sign_birtija", "Birtija", "#4a2c1a", "#f6dc8e", "#2b1d14")
    sign("sign_kafana", "Kafana", "#3a1418", "#ffd36a", "#2b1d14")
    sign("sign_restoran", "Restoran", "#1d2433", "#f3e8cf", "#0e1428")
    sign("sign_splav", "Splav", "#0f3346", "#ffffff", "#0b1d2a")
    slot_marker("slot")
    radial("glow", 128, (255, 214, 140), 1.8)
    radial("pool", 256, (255, 196, 110), 1.3)
    radial("shadow", 128, (0, 0, 0), 1.2)
    print(f"textures written to {OUT}")


if __name__ == "__main__":
    main()
