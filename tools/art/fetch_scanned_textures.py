"""Painted surfaces for the 3D world: floors, streets, grass, plaster, stone, brick, roofs.

Downloads CC0 texture sets from Poly Haven (https://polyhaven.com, public domain, no attribution
required; credited in client/assets/textures/SCANNED.md anyway) and paints them into the game's
cartoon style: the colour is flattened into painted areas (mean-shift filtering), and the scan's
relief draws the ink: plank gaps, cobble joints, mortar and roof-tile edges, found where the normal
map tilts away, become dark lines. One NAME.jpg per surface in client/assets/textures. The game
maps them in world space and tints them by vertex colour (see client/scripts/world3d/kit3d.gd).

Plaster is turned into a neutral grey so each building's colour tints it; the warm and rose
plasters bake their hue in. Wooden floors are drawn by build_textures.py instead.

    python tools/art/fetch_scanned_textures.py
"""

from __future__ import annotations

import io
import json
import urllib.request
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/textures"
API = "https://api.polyhaven.com"
HEADERS = {"User-Agent": "do-zore-art-tools/1.0"}

# Game texture -> (Poly Haven asset, size, treatment). Treatments: "colour" keeps the scan's
# colours (with a brightness and saturation trim, and optionally a colour filter), "neutral"
# makes a tintable grey, a hex colour bakes that hue into the neutral grey.
TEXTURES = {
    "cobble": ("cobblestone_floor_08", 512, ("colour", 1.0, 0.9)),
    "paving": ("pavement_03", 512, ("colour", 1.1, 0.6)),
    "sidewalk": ("concrete_pavers", 512, ("colour", 1.3, 0.8)),
    "asphalt": ("asphalt_02", 512, ("colour", 0.95, 1.0)),
    "grass": ("grass_ground", 512, ("colour", 1.1, 1.15, "#a8e070")),
    "dirt": ("dirt", 512, ("colour", 1.15, 1.0)),
    "roof_tiles": ("clay_roof_tiles_02", 512, ("colour", 1.0, 0.95)),
    "stone_wall": ("stone_wall", 512, ("colour", 1.0, 0.85)),
    "bricks": ("brick_wall_001", 512, ("colour", 1.0, 0.95)),
    "plaster_white": ("painted_plaster_wall", 512, ("neutral",)),
    "plaster_warm": ("painted_plaster_wall", 512, ("#e8d2a8",)),
    "plaster_rose": ("painted_plaster_wall", 512, ("#dba89a",)),
}

MAPS = {"Diffuse": "", "nor_gl": "_normal"}
# How strongly each surface's joints are inked (0 = none): soft ground gets none, stone and tile 0.85.
INK = {"grass": 0.0, "dirt": 0.0, "asphalt": 0.15, "plaster_white": 0.2, "plaster_warm": 0.2,
       "plaster_rose": 0.2}
# Fewer painted colours for the quiet surfaces.
COLOURS = {"grass": 5, "dirt": 5, "asphalt": 4, "plaster_white": 4, "plaster_warm": 4, "plaster_rose": 4}


def _get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as response:
        return response.read()


def _treat(image: Image.Image, treatment: tuple) -> Image.Image:
    kind = treatment[0]
    if kind == "colour":
        brightness, saturation = treatment[1], treatment[2]
        image = ImageEnhance.Color(ImageEnhance.Brightness(image).enhance(brightness)).enhance(saturation)
        if len(treatment) > 3:
            # A colour filter, normalised so the brightest channel is untouched.
            hue = np.array([int(treatment[3][i:i + 2], 16) for i in (1, 3, 5)], np.float32)
            pixels = np.asarray(image, np.float32) * (hue / hue.max())[None, None, :]
            image = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGB")
        return image
    grey = np.asarray(image.convert("L"), np.float32) / 255.0
    # Keep the plaster's relief but centre it on a light value the building colour can tint.
    grey = 0.86 + (grey - grey.mean()) * 0.9
    if kind == "neutral":
        hue = np.ones(3, np.float32)
    else:
        hue = np.array([int(kind[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0
        hue = hue / hue.max()
    pixels = np.clip(grey[..., None] * hue[None, None, :] * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(pixels, "RGB")


def _paint(colour: Image.Image, normal: Image.Image, ink: float, colours: int = 7) -> Image.Image:
    """Paint a scan: flatten it into a few colour areas (mean-shift, then k-means), bevel the relief
    with a light from the upper left, and draw its joints (where the normal map tilts away) in ink."""
    bgr = np.asarray(colour.convert("RGB"))[:, :, ::-1].copy()
    flat = cv2.bilateralFilter(cv2.pyrMeanShiftFiltering(bgr, 10, 38), 9, 50, 9)
    samples = flat.reshape(-1, 3).astype(np.float32)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0)
    _, labels, centres = cv2.kmeans(samples, colours, None, criteria, 2, cv2.KMEANS_PP_CENTERS)
    painted = cv2.medianBlur(centres[labels.flatten()].reshape(flat.shape).astype(np.uint8), 5)
    hsv = cv2.cvtColor(painted, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[..., 1] = np.clip(hsv[..., 1] * 1.25, 0, 255)
    out = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR).astype(np.float32) / 255.0
    nrm = np.asarray(normal.convert("RGB"), np.float32) / 255.0
    nx, ny, nz = nrm[..., 0] * 2.0 - 1.0, nrm[..., 1] * 2.0 - 1.0, nrm[..., 2]
    bevel = cv2.GaussianBlur(np.clip((ny - nx) * 0.9, -1.0, 1.0).astype(np.float32), (0, 0), 1.0)
    out *= 1.0 + 0.22 * bevel[..., None] * min(1.0, ink * 1.5)
    if ink > 0.0:
        crease = cv2.GaussianBlur(np.clip((0.93 - nz) / 0.22, 0.0, 1.0).astype(np.float32), (0, 0), 1.1)
        line = np.clip((crease - 0.3) / 0.4, 0.0, 1.0) * ink
        dark = np.array([0.16, 0.2, 0.3], np.float32)  # warm brown ink, BGR
        out = out * (1.0 - line[..., None]) + dark * out * line[..., None]
    out = np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8)[:, :, ::-1]
    return Image.fromarray(out, "RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    credits: dict[str, dict] = {}
    cache: dict[tuple[str, str], Image.Image] = {}
    for name, (asset, size, treatment) in TEXTURES.items():
        files = json.loads(_get(f"{API}/files/{asset}"))
        info = json.loads(_get(f"{API}/info/{asset}"))
        credits[asset] = {"name": info.get("name", asset), "authors": sorted(info.get("authors", {}))}
        images = {}
        for map_name in MAPS:
            key = (asset, map_name)
            if key not in cache:
                url = files[map_name]["1k"]["jpg"]["url"]
                cache[key] = Image.open(io.BytesIO(_get(url))).convert("RGB")
            images[map_name] = cache[key].resize((size, size), Image.LANCZOS)
        colour = _treat(images["Diffuse"], treatment)
        painted = _paint(colour, images["nor_gl"], INK.get(name, 0.85), COLOURS.get(name, 7))
        painted.save(OUT / f"{name}.jpg", quality=90, optimize=True)
        print(f"{name}: {asset} ({size} px)")
    lines = [
        "# Scanned textures",
        "",
        "Written by `tools/art/fetch_scanned_textures.py` from [Poly Haven](https://polyhaven.com)",
        "texture sets, released under CC0 (public domain). Thank you to their authors:",
        "",
    ]
    for name, (asset, _, _) in TEXTURES.items():
        lines.append(f"- `{name}`: {credits[asset]['name']} (`{asset}`) by {', '.join(credits[asset]['authors'])}")
    (OUT / "SCANNED.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
