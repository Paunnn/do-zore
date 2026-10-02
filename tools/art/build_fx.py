"""Emotes and effects drawn over the 3D world: thought clouds, mood faces, notes, coins, the "+"
for a new table and fight dust. Writes client/assets/world/fx/*.svg and their anchors to
client/assets/world/world.json (read by scripts/world/world_data.gd).

    python tools/art/build_fx.py
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/world"
INK = "#2b1d14"


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


def main() -> None:
    manifest: dict = {}
    emotes(manifest)
    (OUT / "world.json").write_text(json.dumps({"sprites": manifest}, indent=1) + "\n", encoding="utf-8")
    print(f"{len(manifest)} effect sprites written to {OUT / 'fx'}")


if __name__ == "__main__":
    main()
