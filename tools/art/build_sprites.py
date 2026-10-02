"""Generate the vector sprites (guests, drinks, UI icons) as SVG files Godot imports directly.

Every sprite is written at twice its on-screen size so the default import scale stays crisp.

    python tools/art/build_sprites.py
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/sprites"

# ---------------------------------------------------------------------------------------------
# Guests: a 120x160 bust, drawn front-on (back chairs) or from behind (front chairs).
# ---------------------------------------------------------------------------------------------

GUESTS = {
    "penzioner_a": dict(skin="#e9c2a0", hair="#bdbbb5", style="fringe", top="#7a5a3c", collar="#efe8d8",
                        wear="cardigan", extras=["cap", "mustache"]),
    "penzioner_b": dict(skin="#efc8a8", hair="#cfcdc8", style="bun", top="#7b4f7f", collar="#f2ece0",
                        wear="cardigan", extras=["glasses"]),
    "studenti_a": dict(skin="#f0c8a4", hair="#3a2a22", style="messy", top="#2f8f8a", collar="#2f8f8a",
                       wear="hoodie", extras=[]),
    "studenti_b": dict(skin="#f3cfae", hair="#6b3f24", style="long", top="#e0a43a", collar="#e0a43a",
                       wear="sweater", extras=["glasses"]),
    "ozalosceni_a": dict(skin="#e8c09c", hair="#2b2622", style="short", top="#26262b", collar="#f1eee8",
                         wear="suit", tie="#111114", extras=[]),
    "ozalosceni_b": dict(skin="#eec6a6", hair="#1f1f24", style="scarf", top="#2a2a30", collar="#2a2a30",
                         wear="sweater", extras=[]),
    "svatovi_a": dict(skin="#f0c49e", hair="#3b2a1f", style="short", top="#b8302f", collar="#f5f2ea",
                      wear="vest", extras=["carnation"]),
    "svatovi_b": dict(skin="#f3cdb0", hair="#2e1f18", style="long", top="#c23a3a", collar="#c23a3a",
                      wear="dress", extras=["wreath"]),
    "biznismen_a": dict(skin="#e8bf98", hair="#1f1a17", style="slick", top="#1f2a44", collar="#f4f1ea",
                        wear="suit", tie="#d9a531", extras=["chain"]),
    "biznismen_b": dict(skin="#e2b48c", hair="#1c1816", style="bald", top="#333238", collar="#f4f1ea",
                        wear="suit", tie="#b8302f", extras=["mustache", "shades"]),
}


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


def gradient(name: str, color: str, light: float = 0.18, dark: float = -0.22, vertical: bool = True) -> str:
    x2, y2 = ("0", "1") if vertical else ("1", "0")
    return (f'<linearGradient id="{name}" x1="0" y1="0" x2="{x2}" y2="{y2}">'
            f'<stop offset="0" stop-color="{shade(color, light)}"/>'
            f'<stop offset="1" stop-color="{shade(color, dark)}"/></linearGradient>')


def torso(g: dict, back: bool) -> str:
    top, edge = g["top"], shade(g["top"], -0.45)
    parts = [f'<path d="M8 160 L8 132 Q10 104 38 97 L82 97 Q110 104 112 132 L112 160 Z" fill="url(#top)" '
             f'stroke="{edge}" stroke-width="2"/>']
    if back:
        if g["wear"] == "hoodie":
            parts.append(f'<path d="M34 100 Q60 128 86 100 Q78 92 60 92 Q42 92 34 100 Z" fill="{shade(top, -0.12)}" '
                         f'stroke="{edge}" stroke-width="2"/>')
        if g["wear"] in ("suit", "vest"):
            parts.append(f'<path d="M60 104 L60 160" stroke="{shade(top, -0.3)}" stroke-width="2"/>')
        return "".join(parts)
    wear = g["wear"]
    if wear in ("suit", "vest"):
        parts.append(f'<path d="M44 97 L60 132 L76 97 Z" fill="{g["collar"]}" stroke="{shade(g["collar"], -0.3)}" stroke-width="1.5"/>')
        if wear == "suit":
            parts.append(f'<path d="M40 98 L58 140 L50 112 L56 104 Z M80 98 L62 140 L70 112 L64 104 Z" '
                         f'fill="{shade(top, -0.18)}" stroke="{edge}" stroke-width="1.5"/>')
        else:
            parts.append(f'<path d="M30 102 Q44 120 52 160 M90 102 Q76 120 68 160" stroke="#e7b44c" stroke-width="3" fill="none"/>')
            parts.append(f'<path d="M8 160 L8 132 Q10 106 30 100 L44 160 Z M112 160 L112 132 Q110 106 90 100 L76 160 Z" '
                         f'fill="{g["collar"]}" stroke="{shade(g["collar"], -0.3)}" stroke-width="1.5"/>')
        if "tie" in g:
            parts.append(f'<path d="M57 100 L63 100 L65 108 L62 134 L60 138 L58 134 L55 108 Z" fill="{g["tie"]}" '
                         f'stroke="{shade(g["tie"], -0.4)}" stroke-width="1"/>')
    elif wear == "cardigan":
        parts.append(f'<path d="M46 97 L60 120 L74 97 Z" fill="{g["collar"]}"/>')
        parts.append(f'<path d="M48 98 L60 160 M72 98 L60 160" stroke="{edge}" stroke-width="2"/>')
        parts.append(f'<g fill="{shade(top, 0.45)}"><circle cx="60" cy="132" r="2.4"/><circle cx="60" cy="148" r="2.4"/></g>')
    elif wear == "hoodie":
        parts.append(f'<path d="M36 99 Q60 120 84 99" fill="none" stroke="{edge}" stroke-width="3"/>')
        parts.append('<path d="M52 108 L50 130 M68 108 L70 130" stroke="#f4f1ea" stroke-width="2.5" stroke-linecap="round"/>')
    elif wear == "sweater":
        parts.append(f'<path d="M44 97 Q60 110 76 97" fill="none" stroke="{shade(top, -0.3)}" stroke-width="4"/>')
    elif wear == "dress":
        parts.append(f'<path d="M40 97 Q60 118 80 97" fill="{g["skin"]}" stroke="{shade(g["skin"], -0.25)}" stroke-width="1.5"/>')
    return "".join(parts)


def hair_back(g: dict) -> str:
    """Hair that sits behind the head (long hair, buns, scarves)."""
    h, edge = g["hair"], shade(g["hair"], -0.35)
    if g["style"] == "long":
        return f'<path d="M30 58 Q28 22 60 22 Q92 22 90 58 L94 104 Q78 112 60 108 Q42 112 26 104 Z" fill="{h}" stroke="{edge}" stroke-width="2"/>'
    if g["style"] == "bun":
        return f'<circle cx="60" cy="24" r="12" fill="{h}" stroke="{edge}" stroke-width="2"/>'
    if g["style"] == "scarf":
        return f'<path d="M26 66 Q22 18 60 18 Q98 18 94 66 L98 100 Q60 112 22 100 Z" fill="{h}" stroke="{shade(h, 0.25)}" stroke-width="2"/>'
    return ""


def hair_front(g: dict) -> str:
    h, edge, style = g["hair"], shade(g["hair"], -0.35), g["style"]
    if style == "short":
        return f'<path d="M33 56 Q30 26 60 25 Q90 26 87 56 Q84 42 72 38 Q60 44 46 38 Q36 42 33 56 Z" fill="{h}" stroke="{edge}" stroke-width="2"/>'
    if style == "messy":
        return (f'<path d="M32 58 Q26 30 44 24 L48 16 L56 23 L62 14 L68 23 L78 17 L80 27 Q94 34 88 58 '
                f'Q84 42 74 38 L66 44 L60 38 L52 44 L44 38 Q36 44 32 58 Z" fill="{h}" stroke="{edge}" stroke-width="2"/>')
    if style == "slick":
        return (f'<path d="M33 54 Q30 24 60 23 Q90 24 87 54 Q84 36 60 34 Q40 35 33 54 Z" fill="{h}" stroke="{edge}" stroke-width="2"/>'
                f'<path d="M44 30 Q60 26 76 30" stroke="{shade(h, 0.5)}" stroke-width="2.5" fill="none" stroke-linecap="round"/>')
    if style == "fringe":
        return (f'<path d="M33 66 Q30 50 36 42 L40 60 Z M87 66 Q90 50 84 42 L80 60 Z" fill="{h}" stroke="{edge}" stroke-width="1.5"/>')
    if style == "bun":
        return f'<path d="M33 58 Q30 28 60 28 Q90 28 87 58 Q78 40 60 42 Q42 40 33 58 Z" fill="{h}" stroke="{edge}" stroke-width="2"/>'
    if style == "long":
        return f'<path d="M33 60 Q32 30 60 29 Q88 30 87 60 Q82 42 66 38 Q52 46 40 44 Q35 50 33 60 Z" fill="{h}" stroke="{edge}" stroke-width="2"/>'
    if style == "scarf":
        return (f'<path d="M31 70 Q28 26 60 26 Q92 26 89 70 Q86 44 60 42 Q34 44 31 70 Z" fill="{h}" stroke="{shade(h, 0.25)}" stroke-width="2"/>'
                f'<path d="M50 96 L60 90 L70 96 L64 104 L56 104 Z" fill="{h}" stroke="{shade(h, 0.25)}" stroke-width="1.5"/>')
    if style == "bald":
        return (f'<path d="M33 66 Q31 54 35 46 L39 62 Z M87 66 Q89 54 85 46 L81 62 Z" fill="{h}"/>'
                f'<ellipse cx="50" cy="36" rx="8" ry="4" fill="#fff" opacity="0.35"/>')
    return ""


def face(g: dict, mood: str) -> str:
    ink, mouth = "#3b2418", "#9b3b34"
    parts = ['<ellipse cx="44" cy="70" rx="6" ry="3.5" fill="#f08a7a" opacity="0.35"/>',
             '<ellipse cx="76" cy="70" rx="6" ry="3.5" fill="#f08a7a" opacity="0.35"/>']
    if mood == "happy":
        parts.append(f'<path d="M44 61 Q50 55 55 61 M65 61 Q70 55 76 61" stroke="{ink}" stroke-width="2.8" fill="none" stroke-linecap="round"/>')
        parts.append(f'<path d="M50 73 Q60 84 70 73 Q60 77 50 73 Z" fill="{mouth}" stroke="{ink}" stroke-width="1.6" stroke-linejoin="round"/>')
    elif mood == "angry":
        parts.append(f'<path d="M42 51 L55 56 M78 51 L65 56" stroke="{ink}" stroke-width="3" stroke-linecap="round"/>')
        parts.append(f'<g fill="{ink}"><ellipse cx="50" cy="61" rx="3" ry="3.6"/><ellipse cx="70" cy="61" rx="3" ry="3.6"/></g>')
        parts.append(f'<path d="M51 78 Q60 71 69 78" stroke="{ink}" stroke-width="2.6" fill="none" stroke-linecap="round"/>')
    else:
        parts.append(f'<path d="M44 53 Q50 50 55 53 M65 53 Q70 50 76 53" stroke="{shade(g["hair"], -0.2)}" stroke-width="2.4" fill="none" stroke-linecap="round"/>')
        parts.append(f'<g fill="{ink}"><ellipse cx="50" cy="61" rx="3" ry="3.6"/><ellipse cx="70" cy="61" rx="3" ry="3.6"/></g>')
        parts.append(f'<path d="M53 75 Q60 78 67 75" stroke="{ink}" stroke-width="2.4" fill="none" stroke-linecap="round"/>')
    parts.append(f'<path d="M60 63 Q57 69 61 70" stroke="{shade(g["skin"], -0.3)}" stroke-width="1.8" fill="none" stroke-linecap="round"/>')
    return "".join(parts)


def extras(g: dict, back: bool) -> str:
    parts = []
    for extra in g["extras"]:
        if extra == "cap":
            parts.append('<path d="M31 48 Q32 24 60 23 Q88 24 89 48 Q60 40 31 48 Z" fill="#5a5a5f" stroke="#38383c" stroke-width="2"/>')
            if not back:
                parts.append('<path d="M34 48 Q60 38 92 46 Q96 52 88 52 Q60 46 34 52 Z" fill="#4a4a4f" stroke="#38383c" stroke-width="1.5"/>')
        elif back:
            continue
        elif extra == "mustache":
            color = shade(g["hair"], -0.1) if g["style"] != "bald" else "#2a211c"
            parts.append(f'<path d="M48 71 Q54 66 60 69 Q66 66 72 71 Q66 75 60 72 Q54 75 48 71 Z" fill="{color}" stroke="{shade(color, -0.3)}" stroke-width="1"/>')
        elif extra == "glasses":
            parts.append('<g fill="#ffffff" fill-opacity="0.25" stroke="#3b2f2a" stroke-width="2"><circle cx="50" cy="61" r="8"/><circle cx="70" cy="61" r="8"/></g>'
                         '<path d="M58 61 L62 61" stroke="#3b2f2a" stroke-width="2"/>')
        elif extra == "shades":
            parts.append('<path d="M40 56 L58 56 L56 66 Q49 69 43 66 Z M62 56 L80 56 L77 66 Q71 69 64 66 Z" fill="#1b1b1f"/>'
                         '<path d="M58 58 L62 58" stroke="#1b1b1f" stroke-width="2.5"/>'
                         '<path d="M44 58 L48 58" stroke="#fff" stroke-width="1.5" opacity="0.6"/>')
        elif extra == "carnation":
            parts.append('<g transform="translate(88 118)"><circle r="7" fill="#d63a3a"/><circle r="4" fill="#f06a5a"/>'
                         '<path d="M0 6 L-2 16" stroke="#3f8a4f" stroke-width="2"/></g>')
        elif extra == "wreath":
            flowers = "".join(f'<circle cx="{x}" cy="{y}" r="5" fill="{c}" stroke="#7a2a2a" stroke-width="1"/>'
                              for x, y, c in [(36, 40, "#f4f1ea"), (46, 31, "#d63a3a"), (60, 28, "#f4f1ea"),
                                              (74, 31, "#d63a3a"), (84, 40, "#f4f1ea")])
            parts.append(flowers)
        elif extra == "chain":
            parts.append('<path d="M46 100 Q60 118 74 100" stroke="#e7b44c" stroke-width="2.5" fill="none" stroke-dasharray="3 2"/>')
    return "".join(parts)


def guest(g: dict, mood: str = "neutral", back: bool = False) -> str:
    skin, edge = g["skin"], shade(g["skin"], -0.3)
    defs = f'<defs>{gradient("top", g["top"])}</defs>'
    parts = [defs, hair_back(g) if not back or g["style"] in ("long", "bun", "scarf") else "", torso(g, back),
             f'<rect x="51" y="84" width="18" height="18" rx="4" fill="{shade(skin, -0.12)}"/>']
    if back:
        parts.append(f'<ellipse cx="33" cy="62" rx="5" ry="8" fill="{skin}" stroke="{edge}" stroke-width="1.5"/>'
                     f'<ellipse cx="87" cy="62" rx="5" ry="8" fill="{skin}" stroke="{edge}" stroke-width="1.5"/>')
        scalp = skin if g["style"] in ("fringe", "bald") else g["hair"]
        parts.append(f'<ellipse cx="60" cy="56" rx="27" ry="31" fill="{scalp}" stroke="{shade(scalp, -0.3)}" stroke-width="2"/>')
        if g["style"] in ("fringe", "bald"):
            parts.append(f'<path d="M35 66 Q60 80 85 66 L84 71 Q60 85 36 71 Z" fill="{g["hair"]}"/>')
        elif g["style"] == "slick":
            parts.append(f'<path d="M44 40 Q60 34 76 40 M42 52 Q60 46 78 52" stroke="{shade(g["hair"], 0.4)}" stroke-width="2" fill="none"/>')
        elif g["style"] == "messy":
            parts.append(f'<path d="M40 34 L44 24 L50 32 L56 22 L62 32 L70 22 L74 32 L80 26" stroke="{shade(g["hair"], -0.35)}" '
                         f'stroke-width="2" fill="{g["hair"]}"/>')
        parts.append(extras(g, True))
    else:
        parts.append(f'<ellipse cx="33" cy="62" rx="5" ry="8" fill="{skin}" stroke="{edge}" stroke-width="1.5"/>'
                     f'<ellipse cx="87" cy="62" rx="5" ry="8" fill="{skin}" stroke="{edge}" stroke-width="1.5"/>')
        parts.append(f'<ellipse cx="60" cy="58" rx="27" ry="30" fill="{skin}" stroke="{edge}" stroke-width="2"/>')
        parts.append(face(g, mood))
        parts.append(hair_front(g))
        parts.append(extras(g, False))
    return svg(240, 320, "0 0 120 160", "\n".join(p for p in parts if p))


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
# UI icons: 64x64 artwork. Nav glyphs are white so Godot can tint them.
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
    "guests": """<g fill="#f4eedc"><circle cx="23" cy="22" r="9"/><path d="M8 52 Q8 34 23 34 Q38 34 38 52 Z"/></g>
<g fill="#9fb3ad"><circle cx="43" cy="24" r="8"/><path d="M30 52 Q30 36 43 36 Q56 36 56 52 Z"/></g>""",
    "trophy": """<path d="M18 10 L46 10 L46 26 Q46 40 32 42 Q18 40 18 26 Z" fill="#eab575" stroke="#8a5a1c" stroke-width="2.5"/>
<path d="M18 14 L8 14 Q8 30 20 32 M46 14 L56 14 Q56 30 44 32" fill="none" stroke="#eab575" stroke-width="4"/>
<rect x="28" y="42" width="8" height="8" fill="#b07a2c"/><rect x="18" y="50" width="28" height="7" rx="2" fill="#8a5a1c"/>""",
    "gear": """<g transform="translate(32 32)" fill="#f4eedc">
<path d="M-4 -27 L4 -27 L6 -19 L12 -16 L19 -21 L24 -16 L19 -9 L22 -3 L29 -2 L29 6 L21 8 L18 14 L23 21 L17 26 L11 21 L5 24 L3 31 L-5 31 L-6 23 L-12 20 L-19 25 L-24 19 L-19 13 L-22 6 L-29 4 L-29 -4 L-21 -6 L-18 -12 L-23 -19 L-17 -24 L-10 -19 L-5 -21 Z"/>
<circle r="9" fill="#1c2a2e"/></g>""",
    "note": """<path d="M26 12 L52 6 L52 42" fill="none" stroke="#ffffff" stroke-width="5" stroke-linejoin="round"/>
<path d="M26 12 L26 48" stroke="#ffffff" stroke-width="5"/>
<ellipse cx="19" cy="49" rx="9" ry="7" fill="#ffffff" transform="rotate(-20 19 49)"/><ellipse cx="45" cy="43" rx="9" ry="7" fill="#ffffff" transform="rotate(-20 45 43)"/>""",
    "nav_floor": """<path d="M6 26 L32 14 L58 26 L32 38 Z" fill="#ffffff"/><path d="M8 28 L8 34 L32 46 L56 34 L56 28 L32 40 Z" fill="#ffffff" opacity="0.7"/>
<rect x="30" y="44" width="4" height="14" fill="#ffffff"/><rect x="22" y="56" width="20" height="4" rx="2" fill="#ffffff"/>""",
    "nav_band": """<rect x="8" y="16" width="16" height="34" rx="3" fill="#ffffff"/><rect x="40" y="16" width="16" height="34" rx="3" fill="#ffffff"/>
<path d="M24 18 L28 50 L32 18 L36 50 L40 18" fill="none" stroke="#ffffff" stroke-width="3" stroke-linejoin="round"/>
<g fill="#1c2a2e"><rect x="12" y="22" width="8" height="4" rx="1"/><rect x="12" y="30" width="8" height="4" rx="1"/><rect x="12" y="38" width="8" height="4" rx="1"/></g>""",
    "nav_menu": """<path d="M27 6 L37 6 L35 24 Q48 32 46 46 Q45 58 32 58 Q19 58 18 46 Q16 32 29 24 Z" fill="#ffffff"/>
<path d="M22 44 Q32 48 42 44 L41 50 Q32 54 23 50 Z" fill="#1c2a2e" opacity="0.35"/>""",
    "nav_upgrades": """<path d="M32 6 L52 28 L40 28 L40 52 L24 52 L24 28 L12 28 Z" fill="#ffffff"/><rect x="14" y="54" width="36" height="5" rx="2.5" fill="#ffffff" opacity="0.7"/>""",
    "nav_venues": """<path d="M6 28 L32 8 L58 28 Z" fill="#ffffff"/><rect x="12" y="28" width="40" height="28" fill="#ffffff"/>
<rect x="27" y="38" width="10" height="18" fill="#1c2a2e"/><rect x="16" y="34" width="8" height="8" fill="#1c2a2e"/><rect x="40" y="34" width="8" height="8" fill="#1c2a2e"/>""",
    "lock": """<path d="M20 28 L20 20 Q20 8 32 8 Q44 8 44 20 L44 28" fill="none" stroke="#f4eedc" stroke-width="6"/>
<rect x="12" y="28" width="40" height="30" rx="6" fill="#eab575" stroke="#8a5a1c" stroke-width="2.5"/><circle cx="32" cy="41" r="4" fill="#5a3a12"/><rect x="30" y="42" width="4" height="9" fill="#5a3a12"/>""",
    "sparkle": """<path d="M32 4 Q36 28 60 32 Q36 36 32 60 Q28 36 4 32 Q28 28 32 4 Z" fill="#ffffff"/>""",
}


def bubble() -> str:
    """Speech bubble with a tail at the bottom centre: 112x124 artwork."""
    return svg(224, 248, "0 0 112 124",
               '<path d="M18 4 L94 4 Q108 4 108 18 L108 88 Q108 102 94 102 L66 102 L56 120 L46 102 L18 102 '
               'Q4 102 4 88 L4 18 Q4 4 18 4 Z" fill="#fbf6ea" stroke="#3b2a1c" stroke-width="4" stroke-linejoin="round"/>')


def main() -> None:
    for folder in ("guests", "drinks", "icons"):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    for name, spec in GUESTS.items():
        for mood in ("happy", "neutral", "angry"):
            (OUT / "guests" / f"{name}_{mood}.svg").write_text(guest(spec, mood), encoding="utf-8")
        (OUT / "guests" / f"{name}_back.svg").write_text(guest(spec, back=True), encoding="utf-8")
    for name, body in DRINKS.items():
        (OUT / "drinks" / f"{name}.svg").write_text(svg(240, 240, "0 0 120 120", body.strip()), encoding="utf-8")
    for name, body in ICONS.items():
        (OUT / "icons" / f"{name}.svg").write_text(svg(128, 128, "0 0 64 64", body.strip()), encoding="utf-8")
    (OUT / "icons" / "bubble.svg").write_text(bubble(), encoding="utf-8")
    print(f"Wrote {len(GUESTS) * 4} guest, {len(DRINKS)} drink and {len(ICONS) + 1} icon sprites to {OUT}")


if __name__ == "__main__":
    main()
