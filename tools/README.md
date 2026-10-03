# Do Zore tools

The balance tools are standard-library Python and read the canonical `/data` directory without
editing it or the contracts. The art tools in `tools/art` write the client's generated art and
need Pillow and NumPy. Run everything from the repository root with Python 3.10+.

## Build the Godot bundle

```sh
python tools/bundle_client_data.py
```

This regenerates `client/data/bundle.json`, the client's schema copies and the
`data.*` entries in `client/localization/strings.json`. Edit UI strings in that
single catalog. Generated data text comes from authoritative source data through
the data owner. The build preserves all other catalog entries. The hash is SHA-256
of UTF-8 JSON with sorted keys and compact separators; canonicalization agreement
with the future server is tracked in `client/CONTRACT_ISSUES.md`.

## Simulate progression

```sh
python tools/economy_simulator.py
python tools/economy_simulator.py --hours 72 --seeds 1,2,3 --json report.json
python tools/economy_simulator.py --hours 24 --step-seconds 1 --seeds 1 --upgrade-policy none
python tools/economy_simulator.py --hours 168 --online-minutes-per-day 30 --event-policy timeout
```

The report compares continuous active play with one daily session followed by a
capped offline claim. It prints elapsed hours to kafana, restoran and splav,
income per minute, offline/online ratios, and balance hypotheses with suggested
trial numbers. JSON additionally contains purchases and per-venue cash flows.
Unreached venues are explicitly reported. Timing ranges and medians include only
the seeds that reached the venue.

The seeded discrete model follows the client's guest, ingredient, bill, mood,
song, tip, random-event, fight, upgrade and offline formulas. The player policy
automatically serves affordable orders and chooses music with the greatest
aggregate mood improvement. These are idealized inputs, not measured user play.
Python and Godot use different random sequences. `--step-seconds` controls timing
approximation; compare smaller steps before acting on tuning recommendations.

`--upgrade-policy roi` uses a separate stationary heuristic to buy upgrades and
bands with estimated payback under `--roi-minutes` (default 360 calendar minutes).
It keeps `--reserve-minutes` of estimated operating income and checks purchases
once per minute. It does not buy paid songs or value additional genre coverage.
`--upgrade-policy none` buys only the next venue. Stationary diagnostics assume
all orders complete and are separate from observed simulation income.

Events use either their timeout choice immediately or the affordable choice with
the best estimated cash outcome. Decision waiting time, strategic mood value,
and future guest-spawn value are not modeled by that policy. High-mood extra stay
and glass economics remain dormant because canonical data does not define their
tuning. No ads, purchases, network requests or live events are simulated.

The assumptions are included in every report. Suggested numbers are experimental
benchmarks, not approved balance changes. Longer multi-seed runs can take several
minutes, depending on timestep and upgrades.

## Rebuild the art

The game world is built in 3D at run time (see `client/README.md`); these scripts generate the
textures, interface pieces and branding it uses:

```sh
python tools/art/fetch_scanned_textures.py  # photo-scanned floors, streets, grass, plaster, stone, brick, roofs
python tools/art/build_textures.py  # painted cloths, wallpapers, logs, rugs, paintings, signs, people atlas
python tools/art/build_ui.py        # HUD pills, buttons, cards, glyphs, upgrade and event pictures
python tools/art/build_fx.py        # thought clouds, emotes, coins, notes, "+" and fight dust
python tools/art/build_sprites.py   # drink pictures and the coin and mood faces
python tools/art/build_key_art.py   # key art / boot splash and app icon (SVG; see client/design/README.md)
```

- `fetch_scanned_textures.py` downloads CC0 (public domain) texture sets from Poly Haven and
  writes `NAME.jpg` with `NAME_normal.jpg` and `NAME_rough.jpg` relief and shine maps (indoor
  floors 1024 px, the rest 512 px); plaster becomes a neutral grey that each building's colour
  tints. It needs network access; the results are committed, with credits in
  `client/assets/textures/SCANNED.md`. After the first import give the `_normal` maps
  `compress/normal_map=1` (and every scan `compress/mode=2`, `mipmaps/generate=true`).
- `build_textures.py` uses NumPy for seamless noise; tiling textures are 512×512 and are mapped
  in world space by the game, so one texture covers floors and walls of any size. It also
  writes `people_atlas.png`: 16 greyscale cells (skin, cotton, knit, denim, wool, pinstripe,
  hair, leather, fleece, satin, linen, a folk floral print, plaid, stripes, felt, lace) that
  the characters' vertex colours tint; `people3d.gd` maps each body part into its cell, so a
  character stays one draw call. The cell order is shared with `CELLS` in that script.
- `build_ui.py` and `build_key_art.py` share `isokit.py`, a small outlined-isometric SVG kit used
  for the upgrade and event pictures.
- The venue, band and guest pictures are renders of the 3D models: run
  `godot --path client --rendering-driver opengl3 --script res://tests/render_venue_cards.gd`
  (under `xvfb-run -a` without a display). The key art embeds the venue renders, so render them
  first.

After running a script, run the Godot import step (`run_checks.py` does it) so new files get
their `.import` settings. Tiling textures use VRAM compression with mipmaps: after the first
import set `compress/mode=2` and `mipmaps/generate=true` in their `.import` files.

## Tests

```sh
python -m unittest discover -s tools -p "test_*.py" -v
```

Tests cover cross-tier offline formulas, caps/clock rollback, upgrade effects,
deterministic progression, source immutability, single order charges/payments,
song multipliers, and reporting unreached milestones. For the Godot suite and
OpenAPI/JSON Schema checks, see `client/README.md`.
