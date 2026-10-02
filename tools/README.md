# Do Zore tools

These are standard-library Python tools. The balance tools read the canonical `/data`
directory and never edit it or the contracts; the art tools in `tools/art` write the
client's generated art. Run everything from the repository root with Python 3.10+.

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

All game art is generated from code in one outlined isometric cartoon style:

```sh
python tools/art/build_people.py   # guests, waiters, bartender, bouncer and musicians (animation sheets)
python tools/art/build_world.py    # rooms, furniture, decor and emotes for every venue + world.json
python tools/art/build_sprites.py  # UI icons and drink pictures
```

- `people.py` is a parametric chibi rig: 3/4 front and back views, walk, sit, drink, dance and
  carry-tray frames, and instrument animations. Guest looks per type live in `GUESTS`.
- `isokit.py` draws outlined isometric boxes, cylinders and wall decals; `build_world.py` uses it
  for each venue's room (floor, walls, windows, kilims, shelves, door), its furniture and its
  layout (table slots, stage, bar, door and the walkable grid) written to `world.json`.

After running a script, run the Godot import step (`run_checks.py` does it) so new files get
their `.import` settings; world textures use VRAM compression with mipmaps.

## Tests

```sh
python -m unittest discover -s tools -p "test_*.py" -v
```

Tests cover cross-tier offline formulas, caps/clock rollback, upgrade effects,
deterministic progression, source immutability, single order charges/payments,
song multipliers, and reporting unreached milestones. For the Godot suite and
OpenAPI/JSON Schema checks, see `client/README.md`.
