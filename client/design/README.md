# Do Zore design system

Modern kafana: the clean, glossy language of today's idle tycoon games, warmed with kafana
materials — red-and-cream checked tablecloths, brass and gold, lamp light in a night city. The
reasoning and the reference games are in `research.md`.

## World

- One night city is the map. The road from the birtija to the splav runs up the screen through
  the village edge, the old town, the centre and the river quay (`scripts/world3d/city3d.gd`).
- Lit low-poly 3D seen through an orthographic camera pitched 46° and turned 45°, zoomed so the
  venue fills the screen edge to edge.
- One night runs from a warm dusk through deep night to dawn ("do zore") in 20 minutes and opens
  again at dusk with every new venue (`SKIES` in `scripts/ui/floor_view.gd`). The sun, then the
  moon, casts the only shadows; interiors, windows and street lamps are always warm.
- Shapes are simple primitives with vertex colours; surfaces that need grain (wood, cloth,
  cobbles, plaster, roof tiles) use the world-mapped textures from `tools/art/build_textures.py`.
- The played venue is a roofless cut-away with low front walls; nothing between it and the
  camera rises above one storey. Nothing hangs over the tables either: the room is lit by lights
  alone, and the lamps you see are sconces on the back walls and shaded pendants over the bar.
- Keep the floor quiet: only the next table to buy is marked, tables stand on soft contact
  shadows, and floor textures are low-contrast.
- Characters are chibi at 1.3× life size so they read on a phone (cars and trees are scaled to
  them): the head is about 40 % of the height, with dark oval eyes and a highlight, brows, rosy
  cheeks and a small smile; a rounded body, short limbs, round hands and shoes; hair as a cap
  with a fringe. Clothes and hair carry fabric textures from one atlas (knit cardigans, denim,
  plaid and striped shirts, pinstripe and tweed suits, satin dresses, a lace veil, a floral
  marama, hair strands), so each character is still one material and one draw call. A readable silhouette per guest type
  (šajkača and moustache for penzioneri, a marama for their wives, hoodies for studenti, black
  for ožalošćeni, suits and dresses for svatovi, suits and ties for biznismeni, the long white
  apron for konobari).
- The city has life: guests walk to the door along the pavement, townspeople stroll round the
  nearby blocks.

## Colour

| Role | Colour |
| --- | --- |
| Sky | dusk `#2b2546`, night `#0e1830`, dawn `#3b3658` (background); sun `#ffb47e`, moon `#a9c2ff` |
| Ink, outlines | `#2b1d14`; text outline `#3a1d0e` |
| Primary action (gold) | `#ffd95a` → `#ffbf2e` → `#f0a01c`, lip `#a8620c` |
| Decisive action (red) | `#de5246` → `#b8302f`, lip `#6a1916` |
| Cards | cream `#fbf3e2` with a `#ead9b6` inner line; rows white |
| HUD pills | `#1a1428` at 72 % with a soft sheen |
| Text on cream | ink `#2b1d14`, secondary `#7a6148`, headings in red `#b8302f` |
| Good / bad | green `#5bd16a`, red `#ff5a4a` (mood and progress fills) |
| Genres | starogradske `#e8a33a`, tamburica `#2f9e86`, izvorna `#d2553f`, narodnjaci `#8e5cc7` |

## Type

All three faces are OFL and cover Serbian Latin (č ć đ š ž); Lilita One and Fredoka were
rejected because they lack č, ć and đ.

- **Shrikhand** — titles, venue names, card headers: white with a dark red outline, or gold.
- **Titan One** — buttons, numbers, prices, captions: white with a dark outline and a 4 px
  drop shadow (`UIKit.outlined`), or ink on paper buttons.
- **Nunito** (700 / 900) — body text and descriptions.

Sizes on the 1080-wide design canvas: title 56, heading 40, name 32, body 28, small 24, tiny 21.

## Components (`scripts/ui/ui_kit.gd`, art from `tools/art/build_ui.py`)

- **HUD**: one row (venue ribbon, money, the room chip with mood and guests, settings) and a slim
  strip under it with the road to the next venue. Counters sit on `pill_dark`; the coin
  overlaps the money pill. Now playing is a small chip just above the music button.
- **Badges**: one red badge at a time, on the single most useful next step (open the next venue,
  then an affordable upgrade, then the band).
- **Round buttons** (`round_cream` small with an ink glyph; `round_gold` / `round_red` large
  with a white glyph) with a Titan One caption and a red `!` badge slot. Bottom: Mapa, Pesma,
  Unapređenja; right edge: Bend, Piće, Rang.
- **Lipped buttons** (`button_gold`, `button_red`, `button_paper`; a grey face when disabled);
  the face drops 7 px when pressed.
- **Card** (`card`) with a red **header** ribbon, a round **close** button and the
  **checker strip** (tablecloth trim) under the header; list **rows** inside.
- Progress bars: dark slot on the HUD, a pressed paper groove inside cards.

## Spacing

Gutter 24 at the screen edges, 16 between stacked blocks; inside cards 24–30. The 3D view
always keeps the venue between the bottom of the HUD and the top of the bottom buttons.

## Branding

`key_art.svg` (boot splash) and `icon*.svg` come from `tools/art/build_key_art.py`. They embed
the venue renders and reference the fonts in `assets/fonts`, so rasterise them in a browser
engine (Playwright Chromium: inline the SVG in an HTML page with `<meta charset="utf-8">` and
screenshot it at 1080×1920 / 1024×1024), then save `assets/branding/splash.png`, `icon.png`
(512), `icon_192.png` and the 432 px adaptive-icon layers.
