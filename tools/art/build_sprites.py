"""Generate the UI vector sprites (drinks and icons) as SVG files Godot imports directly.

Every sprite is written at twice its on-screen size so the default import scale stays crisp.

    python tools/art/build_sprites.py
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/sprites"

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def shade(color: str, amount: float) -> str:
    """Lighten (amount > 0) or darken (amount < 0) a #rrggbb colour."""
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    if amount >= 0:
        r, g, b = (round(c + (255 - c) * amount) for c in (r, g, b))
    else:
        r, g, b = (round(c * (1 + amount)) for c in (r, g, b))
    return f"#{r:02x}{g:02x}{b:02x}"


def svg(width: int, height: int, view: str, body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="{view}">\n'
            f'{body}\n</svg>\n')


# ---------------------------------------------------------------------------------------------
# Drinks: 120x120 artwork on a transparent background (shown inside order bubbles and the menu).
# ---------------------------------------------------------------------------------------------

GLASS = 'fill="#dfeff0" fill-opacity="0.22" stroke="#cfe3e0" stroke-width="3"'
HIGHLIGHT = 'stroke="#fff" stroke-opacity="0.55" stroke-width="4" stroke-linecap="round" fill="none"'
SHADOW = '<ellipse cx="60" cy="108" rx="40" ry="6" fill="#000" opacity="0.22"/>'

DRINKS = {
    "domaca_kafa": f"""
<defs><linearGradient id="cu" x1="0" x2="1"><stop offset="0" stop-color="#f0a865"/><stop offset="0.55" stop-color="#c46d36"/><stop offset="1" stop-color="#8a4420"/></linearGradient></defs>
{SHADOW}
<path d="M38 40 q-6 -8 0 -14 q6 -6 0 -14" fill="none" stroke="#9fb3ad" stroke-width="3" stroke-linecap="round" opacity="0.6"/>
<line x1="96" y1="58" x2="116" y2="40" stroke="#5a3a22" stroke-width="6" stroke-linecap="round"/>
<path d="M80 52 L96 52 L101 92 Q101 100 94 100 L80 100 Q74 100 74 92 Z" fill="url(#cu)" stroke="#6e3518" stroke-width="2"/>
<rect x="78" y="49" width="20" height="5" rx="2.5" fill="#f0a865" stroke="#6e3518" stroke-width="1.5"/>
<ellipse cx="44" cy="102" rx="34" ry="7" fill="#e6dcc3" stroke="#b9ab8c" stroke-width="2"/>
<path d="M22 66 Q23 94 35 99 L53 99 Q65 94 66 66 Z" fill="#f4eedc" stroke="#b9ab8c" stroke-width="2"/>
<path d="M23 77 Q44 84 65 77 L64 85 Q44 92 24 85 Z" fill="#2f6b8a"/>
<ellipse cx="44" cy="66" rx="22" ry="5" fill="#f4eedc" stroke="#b9ab8c" stroke-width="2"/>
<ellipse cx="44" cy="67" rx="18" ry="3.4" fill="#3a2418"/>""",
    "kisela_voda": f"""
{SHADOW}
<path d="M50 14 L62 14 L62 30 Q74 40 74 56 L74 100 Q74 106 68 106 L44 106 Q38 106 38 100 L38 56 Q38 40 50 30 Z" fill="#5fae9e" fill-opacity="0.55" stroke="#2f7e6e" stroke-width="3"/>
<rect x="48" y="8" width="16" height="9" rx="2" fill="#2f6b8a"/>
<rect x="40" y="62" width="32" height="22" rx="3" fill="#f4eedc"/><path d="M44 73 L68 73" stroke="#2f6b8a" stroke-width="4"/>
<path d="M78 70 L104 70 L101 106 L81 106 Z" {GLASS}/>
<rect x="80" y="80" width="22" height="25" fill="#bfe6ee" opacity="0.6"/>
<g fill="#fff" opacity="0.8"><circle cx="88" cy="96" r="1.8"/><circle cx="95" cy="88" r="1.5"/><circle cx="90" cy="84" r="1.2"/><circle cx="56" cy="92" r="1.8"/><circle cx="50" cy="48" r="1.5"/></g>
<path d="M44 44 L44 54" {HIGHLIGHT}/>""",
    "pivo": f"""
<defs><linearGradient id="beer" x1="0" x2="1"><stop offset="0" stop-color="#f7c55a"/><stop offset="0.6" stop-color="#e09b2c"/><stop offset="1" stop-color="#b8731c"/></linearGradient></defs>
{SHADOW}
<path d="M86 44 h10 q10 0 10 10 v24 q0 10 -10 10 h-10" fill="none" stroke="#d9e8e5" stroke-width="8" opacity="0.85"/>
<rect x="26" y="34" width="62" height="70" rx="8" fill="url(#beer)" stroke="#d9e8e5" stroke-width="3"/>
<g stroke="#fff" stroke-width="3.5" opacity="0.2" stroke-linecap="round"><line x1="40" y1="48" x2="40" y2="96"/><line x1="57" y1="48" x2="57" y2="96"/><line x1="74" y1="48" x2="74" y2="96"/></g>
<g fill="#fbf6ea" stroke="#e6dcc3" stroke-width="1.5"><circle cx="31" cy="34" r="10"/><circle cx="45" cy="28" r="12"/><circle cx="61" cy="27" r="12"/><circle cx="77" cy="31" r="11"/><circle cx="85" cy="39" r="7"/></g>
<rect x="24" y="31" width="66" height="9" fill="#fbf6ea"/>""",
    "sljivovica": f"""
<defs><linearGradient id="amb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6cf72"/><stop offset="1" stop-color="#c9852e"/></linearGradient>
<radialGradient id="plum" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#8c66b8"/><stop offset="0.6" stop-color="#55327a"/><stop offset="1" stop-color="#2e1748"/></radialGradient>
<clipPath id="ck"><path d="M53 14 L67 14 L64 44 Q84 60 80 84 Q78 102 60 102 Q42 102 40 84 Q36 60 56 44 Z"/></clipPath></defs>
{SHADOW}
<ellipse cx="94" cy="88" rx="16" ry="18" fill="url(#plum)"/><path d="M94 72 q2 -8 8 -12" stroke="#5a3a22" stroke-width="3" fill="none"/>
<path d="M101 61 q12 -6 17 4 q-12 6 -17 -4 Z" fill="#4f9a6a"/>
<g clip-path="url(#ck)"><rect x="30" y="10" width="60" height="100" fill="#dfeff0" opacity="0.2"/><rect x="30" y="64" width="60" height="44" fill="url(#amb)"/></g>
<path d="M53 14 L67 14 L64 44 Q84 60 80 84 Q78 102 60 102 Q42 102 40 84 Q36 60 56 44 Z" fill="none" stroke="#cfe3e0" stroke-width="3" stroke-linejoin="round"/>
<path d="M47 72 Q46 86 52 94" {HIGHLIGHT}/>""",
    "lozovaca": f"""
<defs><linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbe7a0"/><stop offset="1" stop-color="#d9b04a"/></linearGradient>
<clipPath id="ck2"><path d="M53 14 L67 14 L64 44 Q84 60 80 84 Q78 102 60 102 Q42 102 40 84 Q36 60 56 44 Z"/></clipPath></defs>
{SHADOW}
<g fill="#7fae4f" stroke="#4f7a2f" stroke-width="1.5"><circle cx="90" cy="70" r="7"/><circle cx="102" cy="70" r="7"/><circle cx="96" cy="81" r="7"/><circle cx="108" cy="81" r="6"/><circle cx="90" cy="92" r="7"/><circle cx="102" cy="93" r="7"/><circle cx="96" cy="103" r="6"/></g>
<path d="M96 62 q4 -10 12 -12" stroke="#5a3a22" stroke-width="3" fill="none"/><path d="M100 56 q14 -8 18 4 q-12 6 -18 -4 Z" fill="#4f9a6a"/>
<g clip-path="url(#ck2)"><rect x="30" y="10" width="60" height="100" fill="#dfeff0" opacity="0.2"/><rect x="30" y="64" width="60" height="44" fill="url(#gold)"/></g>
<path d="M53 14 L67 14 L64 44 Q84 60 80 84 Q78 102 60 102 Q42 102 40 84 Q36 60 56 44 Z" fill="none" stroke="#cfe3e0" stroke-width="3" stroke-linejoin="round"/>
<path d="M47 72 Q46 86 52 94" {HIGHLIGHT}/>""",
    "meze": f"""
{SHADOW}
<path d="M10 74 L92 62 Q104 60 108 70 L112 86 Q114 94 104 96 L22 106 Q12 108 10 98 Z" fill="#b07a45" stroke="#6e4524" stroke-width="2.5"/>
<path d="M14 80 L104 68" stroke="#8a5a30" stroke-width="2" opacity="0.6"/>
<g stroke="#c9a54a" stroke-width="1.5" fill="#f6e3a0"><path d="M24 76 L40 74 L40 88 L24 90 Z"/><path d="M42 72 L56 70 L56 84 L42 86 Z"/></g>
<g fill="#c94a4a" stroke="#8a2a2a" stroke-width="1.5"><path d="M60 70 Q70 60 80 68 Q74 80 62 82 Z"/><path d="M74 78 Q86 70 94 78 Q86 88 76 88 Z"/></g>
<g fill="#4a5a2a"><circle cx="34" cy="96" r="4"/><circle cx="44" cy="95" r="4"/><circle cx="90" cy="64" r="3.5"/></g>
<g fill="#f4eedc" stroke="#b9ab8c" stroke-width="1.2"><circle cx="62" cy="92" r="5"/><circle cx="70" cy="90" r="4"/></g>""",
    "crno_vino": f"""
<defs><linearGradient id="wine" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a3283f"/><stop offset="1" stop-color="#4f0b1f"/></linearGradient>
<clipPath id="bw"><path d="M32 10 L88 10 Q92 58 60 72 Q28 58 32 10 Z"/></clipPath></defs>
{SHADOW}
<ellipse cx="60" cy="104" rx="26" ry="5" fill="#cfe3e0" opacity="0.5" stroke="#cfe3e0" stroke-width="2"/>
<rect x="57" y="70" width="6" height="34" fill="#cfe3e0" opacity="0.75"/>
<g clip-path="url(#bw)"><rect x="20" y="0" width="80" height="80" fill="#dfeff0" opacity="0.14"/><rect x="20" y="36" width="80" height="44" fill="url(#wine)"/><ellipse cx="60" cy="36" rx="30" ry="4" fill="#c2405c"/></g>
<path d="M32 10 L88 10 Q92 58 60 72 Q28 58 32 10 Z" fill="none" stroke="#cfe3e0" stroke-width="3" stroke-linejoin="round"/>
<path d="M40 18 Q39 40 48 54" {HIGHLIGHT}/>""",
    "vinjak": f"""
<defs><linearGradient id="br" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e09a3c"/><stop offset="1" stop-color="#8a4a14"/></linearGradient>
<clipPath id="sn"><path d="M38 30 Q24 60 40 80 Q60 96 80 80 Q96 60 82 30 Z"/></clipPath></defs>
{SHADOW}
<ellipse cx="60" cy="104" rx="22" ry="5" fill="#cfe3e0" opacity="0.5" stroke="#cfe3e0" stroke-width="2"/>
<rect x="57" y="86" width="6" height="18" fill="#cfe3e0" opacity="0.75"/>
<g clip-path="url(#sn)"><rect x="20" y="20" width="80" height="80" fill="#dfeff0" opacity="0.15"/><rect x="20" y="62" width="80" height="40" fill="url(#br)"/><ellipse cx="60" cy="62" rx="40" ry="5" fill="#f0b45a"/></g>
<path d="M38 30 Q24 60 40 80 Q60 96 80 80 Q96 60 82 30 Z" fill="none" stroke="#cfe3e0" stroke-width="3"/>
<path d="M36 50 Q36 66 44 74" {HIGHLIGHT}/>""",
    "rostilj": f"""
{SHADOW}
<ellipse cx="60" cy="82" rx="52" ry="20" fill="#f4eedc" stroke="#b9ab8c" stroke-width="2.5"/>
<ellipse cx="60" cy="80" rx="40" ry="13" fill="#e9dfc6"/>
<ellipse cx="78" cy="76" rx="22" ry="10" fill="#8a4a24" stroke="#5a2a10" stroke-width="2"/>
<path d="M62 74 Q78 70 94 76" stroke="#5a2a10" stroke-width="1.5" fill="none" opacity="0.6"/>
<g fill="#9a5a2a" stroke="#5a2a10" stroke-width="1.8"><rect x="26" y="70" width="34" height="9" rx="4.5"/><rect x="24" y="80" width="34" height="9" rx="4.5"/><rect x="30" y="89" width="32" height="8" rx="4"/></g>
<g stroke="#f4eedc" stroke-width="2" fill="none" opacity="0.9"><path d="M64 88 q8 -6 16 0"/><path d="M70 92 q8 -6 16 0"/></g>
<path d="M90 88 q6 -4 12 0" stroke="#c94a4a" stroke-width="3" fill="none"/>""",
    "viski": f"""
<defs><linearGradient id="wh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e9a54a"/><stop offset="1" stop-color="#9a5418"/></linearGradient></defs>
{SHADOW}
<path d="M28 40 L92 40 L86 104 L34 104 Z" fill="#dfeff0" fill-opacity="0.2"/>
<path d="M31 66 L89 66 L86 104 L34 104 Z" fill="url(#wh)"/>
<g fill="#eaf6f8" fill-opacity="0.75" stroke="#ffffff" stroke-width="1.5"><rect x="40" y="56" width="18" height="18" rx="3" transform="rotate(-12 49 65)"/><rect x="60" y="60" width="16" height="16" rx="3" transform="rotate(14 68 68)"/></g>
<path d="M28 40 L92 40 L86 104 L34 104 Z" fill="none" stroke="#cfe3e0" stroke-width="3" stroke-linejoin="round"/>
<path d="M34 98 L86 98" stroke="#cfe3e0" stroke-width="3"/>
<path d="M38 48 L42 92" {HIGHLIGHT}/>""",
    "riblja_corba": f"""
{SHADOW}
<path d="M42 40 q-6 -8 0 -14 q6 -6 0 -14 M62 36 q-6 -8 0 -14 q6 -6 0 -14 M82 40 q-6 -8 0 -14 q6 -6 0 -14" fill="none" stroke="#9fb3ad" stroke-width="3" stroke-linecap="round" opacity="0.55"/>
<path d="M12 62 Q14 104 60 106 Q106 104 108 62 Z" fill="#3b6e8a" stroke="#244a5e" stroke-width="2.5"/>
<path d="M18 74 Q60 84 102 74" stroke="#eab575" stroke-width="3" fill="none"/>
<ellipse cx="60" cy="62" rx="48" ry="12" fill="#f4eedc" stroke="#244a5e" stroke-width="2.5"/>
<ellipse cx="60" cy="63" rx="42" ry="8.5" fill="#d9542e"/>
<g fill="#f6a05a" opacity="0.9"><circle cx="44" cy="62" r="3"/><circle cx="66" cy="60" r="2.5"/><circle cx="80" cy="64" r="2.8"/></g>
<path d="M46 66 q6 -4 12 0 M70 66 q4 -3 8 0" stroke="#3f8a4f" stroke-width="2" fill="none"/>""",
    "sampanjac": f"""
<defs><linearGradient id="bt" x1="0" x2="1"><stop offset="0" stop-color="#2f6b46"/><stop offset="1" stop-color="#173a26"/></linearGradient></defs>
{SHADOW}
<path d="M28 106 L28 54 Q28 44 36 38 L38 22 L48 22 L50 38 Q58 44 58 54 L58 106 Z" fill="url(#bt)" stroke="#0f2a1a" stroke-width="2"/>
<rect x="36" y="10" width="14" height="16" rx="2" fill="#e7b44c" stroke="#a87a1c" stroke-width="1.5"/>
<rect x="31" y="66" width="24" height="20" rx="2" fill="#f4eedc"/><path d="M35 76 L51 76" stroke="#e7b44c" stroke-width="3"/>
<path d="M34 50 L34 96" stroke="#fff" stroke-opacity="0.3" stroke-width="4" stroke-linecap="round" fill="none"/>
<path d="M76 26 L100 26 Q100 64 90 70 L90 100 M78 104 L102 104 M86 70 Q76 64 76 26" fill="#f6e3a0" fill-opacity="0.35" stroke="#cfe3e0" stroke-width="3" stroke-linejoin="round"/>
<path d="M78 40 L98 40 Q97 62 88 66 Q79 62 78 40 Z" fill="#f6dc7a" opacity="0.85"/>
<g fill="#fff"><circle cx="86" cy="56" r="1.6"/><circle cx="90" cy="48" r="1.3"/><circle cx="84" cy="44" r="1.1"/><circle cx="92" cy="16" r="2"/><circle cx="84" cy="10" r="1.5"/></g>""",
}

# ---------------------------------------------------------------------------------------------
# HUD pictures: 64x64 artwork in colour (the coin and the three room moods). Interface glyphs,
# frames and buttons come from build_ui.py.
# ---------------------------------------------------------------------------------------------

ICONS = {
    "coin": """<defs><radialGradient id="c" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffe7a3"/><stop offset="0.6" stop-color="#eab575"/><stop offset="1" stop-color="#b07a2c"/></radialGradient></defs>
<circle cx="32" cy="32" r="26" fill="url(#c)" stroke="#8a5a1c" stroke-width="3"/><circle cx="32" cy="32" r="18" fill="none" stroke="#b07a2c" stroke-width="2.5"/>
<path d="M27 22 L27 42 L32 42 Q40 42 40 32 Q40 22 32 22 Z" fill="none" stroke="#8a5a1c" stroke-width="3.5" stroke-linejoin="round"/>""",
    "mood_happy": """<circle cx="32" cy="32" r="27" fill="#72cbb6" stroke="#3f8a7a" stroke-width="3"/>
<path d="M20 28 Q24 22 28 28 M36 28 Q40 22 44 28" stroke="#173a32" stroke-width="3.5" fill="none" stroke-linecap="round"/>
<path d="M20 38 Q32 52 44 38 Q32 43 20 38 Z" fill="#173a32"/>""",
    "mood_neutral": """<circle cx="32" cy="32" r="27" fill="#eab575" stroke="#a8772c" stroke-width="3"/>
<g fill="#3a2a12"><circle cx="24" cy="27" r="3.5"/><circle cx="40" cy="27" r="3.5"/></g>
<path d="M22 41 L42 41" stroke="#3a2a12" stroke-width="3.5" stroke-linecap="round"/>""",
    "mood_unhappy": """<circle cx="32" cy="32" r="27" fill="#ed8c7a" stroke="#a8473a" stroke-width="3"/>
<path d="M18 20 L28 25 M46 20 L36 25" stroke="#3a1610" stroke-width="3.5" stroke-linecap="round"/>
<g fill="#3a1610"><circle cx="24" cy="30" r="3.5"/><circle cx="40" cy="30" r="3.5"/></g>
<path d="M21 46 Q32 36 43 46" stroke="#3a1610" stroke-width="3.5" fill="none" stroke-linecap="round"/>""",
}


def main() -> None:
    for folder in ("drinks", "icons"):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    for name, body in DRINKS.items():
        (OUT / "drinks" / f"{name}.svg").write_text(svg(240, 240, "0 0 120 120", body.strip()), encoding="utf-8")
    for name, body in ICONS.items():
        (OUT / "icons" / f"{name}.svg").write_text(svg(128, 128, "0 0 64 64", body.strip()), encoding="utf-8")
    print(f"Wrote {len(DRINKS)} drink and {len(ICONS)} icon sprites to {OUT}")


if __name__ == "__main__":
    main()
