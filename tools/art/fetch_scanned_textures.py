"""Photo-scanned surfaces for the 3D world: floors, streets, grass, plaster, stone, brick, roofs.

Downloads CC0 texture sets from Poly Haven (https://polyhaven.com, public domain, no attribution
required; credited in client/assets/textures/SCANNED.md anyway), and writes for each one the
colour, an OpenGL normal map and a roughness map into client/assets/textures as
NAME.jpg, NAME_normal.jpg and NAME_rough.jpg. The game maps them in world space and tints them
by vertex colour (see client/scripts/world3d/kit3d.gd).

Plaster is turned into a neutral grey so each building's colour tints it; the warm and rose
plasters bake their hue in. Indoor floors are kept at 1024 px, everything else at 512 px.

    python tools/art/fetch_scanned_textures.py

After it runs, import the project once (client/tests/run_checks.py does it) and give the
normal maps normal-map import settings (compress/normal_map=1, mipmaps on).
"""

from __future__ import annotations

import io
import json
import urllib.request
from pathlib import Path

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
    "planks_rough": ("wood_floor_worn", 1024, ("colour", 1.08, 1.0)),
    "planks_walnut": ("wood_floor_deck", 1024, ("colour", 1.0, 1.0)),
    "planks_deck": ("weathered_brown_planks", 1024, ("colour", 1.2, 0.9)),
    "parquet": ("herringbone_parquet", 1024, ("colour", 0.95, 0.95)),
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

MAPS = {"Diffuse": "", "nor_gl": "_normal", "Rough": "_rough"}


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


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    credits: dict[str, dict] = {}
    cache: dict[tuple[str, str], Image.Image] = {}
    for name, (asset, size, treatment) in TEXTURES.items():
        files = json.loads(_get(f"{API}/files/{asset}"))
        info = json.loads(_get(f"{API}/info/{asset}"))
        credits[asset] = {"name": info.get("name", asset), "authors": sorted(info.get("authors", {}))}
        for map_name, suffix in MAPS.items():
            key = (asset, map_name)
            if key not in cache:
                url = files[map_name]["1k"]["jpg"]["url"]
                cache[key] = Image.open(io.BytesIO(_get(url))).convert("RGB")
            image = cache[key].resize((size, size), Image.LANCZOS)
            if map_name == "Diffuse":
                image = _treat(image, treatment)
            image.save(OUT / f"{name}{suffix}.jpg", quality=90, optimize=True)
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
