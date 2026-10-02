# Do Zore mobile client

Godot 4.x / GDScript offline vertical slice. The design viewport is 1080 × 1920
portrait; the UI uses expanding containers, scroll views and safe-area padding.
Serbian Latin (`sr`) is the default language, with an English (`en`) catalog.
The main screen is an animated isometric kafana (see **Art**); audio hooks are still silent.

## Run

1. Install Godot 4.5.x (standard build; .NET is unnecessary).
2. Import `client/project.godot` in Godot and press **F5** to run the main scene.
   Or run from the repository root:

   ```sh
   godot --path client
   ```

The checked-in configuration uses mock mode. No account or backend is required.
The vertical slice intentionally does not make real network requests.

## Play

- Guests walk in and sit down; a thought cloud shows what they ordered. Tap the cloud or the
  table to serve it (a ring fills while it is prepared) and tap the table again for details.
  A small cloud with a coloured note is the genre they want.
- Tap the stage or the yellow music button to play a known song. The band plays, notes rise
  and happy tables get up to dance. Leaving guests pay; the coins fly to the money counter.
- Matching music improves table mood and eventual bakšiš. Mismatches and long
  waits reduce mood. Nearby unhappy groups can trigger a fight.
- The bottom navigation opens **Kafana**, **Bend**, **Piće**, **Unapređenja** and
  **Lokali**. Hire each band tier, buy upgrades and songs, and advance from
  **birtija → kafana → restoran → splav** using data-defined prices and gates.
- Random events offer choices with costs and consequences. Settings controls
  language, sound/music hooks and a confirmed progress reset. The leaderboard,
  offline-earnings dialog and cloud-conflict dialog use mock data in this slice.

## Art

The Kafana tab is an isometric scene in the style of cartoon idle tycoon games: one outlined
art style for the room, the furniture and the people. `scripts/ui/floor_view.gd` hosts it in a
`SubViewport` with a `Camera2D` (drag to pan, pinch or wheel to zoom, tap to act) and
`scripts/world/kafana_world.gd` builds the current venue and keeps it in step with the
simulation:

- Guests walk in through the door (A* on the floor grid), sit on the chairs around their table
  and walk out again when they leave; faces follow the table's mood and happy tables dance.
- Thought clouds (`scripts/world/table_hud.gd`) show the order (tap to serve; a ring fills while
  it is prepared), the requested genre and emoji for the mood; big parties get a `+N` badge.
- Waiters carry served drinks from the bar, the bartender works behind it and the band on stage
  plays while a song is on. Konobar, ozvučenje, dekor, izbacivač and sef levels are visible.
- Paying guests drop coins that fly to the money counter; a power cut darkens the room and a
  fight raises a dust cloud. The next free table slot shows a `+` that opens the upgrades.
- A brand-new game coaches the first order and the first song request.

Every venue has its own room, palette and band line-up. All art is generated from code: see
`tools/README.md`. World textures are VRAM-compressed with mipmaps (S3TC on desktop, ETC2/ASTC on
Android). The UI font is Baloo 2 (SIL Open Font License, `assets/fonts/OFL.txt`).

## Architecture

`DataCatalog` loads the bundled balance JSON and the centralized strings catalog.
`GameState` owns schema-compatible player progress and delegates simulation to
plain GDScript logic in `scripts/simulation`. `Economy` exposes data-driven prices,
upgrade effects and capped offline calculations. The UI only reads state and
calls actions; simulation does not depend on UI nodes.

`EventBus` carries state, event, locale, persistence and API notifications.
`SaveSystem` writes a local JSON envelope with a backup, autosaves, and saves on
application pause/close. The envelope separates contract save data from settings
and mock sync metadata. `ApiClient` is the optional mock-backed boundary for
config, saves, offline claims, live events, analytics and leaderboard screens.

Source `/data` and `/contracts` are read-only. The generated bundle retains the
contract data shape. User-visible data text is extracted into
`localization/strings.json`; UI strings live in that same catalog. Add translations
there and rebuild generated entries when source data changes. See
`CONTRACT_ISSUES.md` for unresolved balance and contract semantics.

Rebuild the bundle and centralized data strings from the repository root:

```sh
python tools/bundle_client_data.py
```

## Configuration and persistence

Edit `config/client.json` to set mock behavior, base URL, application version,
autosave and background intervals. The base URL is reserved for subsequent live
integration; disabling mocks must not prevent local gameplay. Never put tokens,
credentials or signing secrets in the project.

Saves use Godot's `user://` directory (custom application directory
`DoZore-client`); on Windows this is normally `%APPDATA%/DoZore-client`.
Use Settings → Reset only when you intend to discard that installation's
progress. Tests use a separate save directory and do not reset normal progress.

## Android export

Install the Godot export templates matching your editor and configure a compatible
Android SDK/JDK in **Editor Settings → Export → Android**. In **Project → Export**,
select the supplied **Android** preset, keep portrait orientation, choose a package ID,
and set your local debug/release signing configuration. Export a debug APK for a
device smoke test. Keep signing material outside Git. An Android SDK, templates
and a signing key are environment requirements; no APK is included in this slice.

Verify pause/resume autosaving, cutouts, navigation gestures and text size on real
phones before release. The desktop/headless checks do not establish device QA.

## Validation

Install the optional Python validation dependencies:

```sh
python -m pip install -r client/tests/requirements.txt
python client/tests/validate_contracts.py
```

The validator reads the repository JSON Schemas locally, checks source and bundled
balance data, and can validate captured client requests/responses with
`--fixtures path/to/contract-fixtures.json`. Run the complete suite with:

```sh
python client/tests/run_checks.py --godot /path/to/godot
```

The runner creates a fresh temporary save directory through
`DO_ZORE_TEST_USER_DIR`, imports scripts headlessly, runs gameplay/API/UI checks,
restarts against a deliberately corrupted primary save to verify backup recovery,
then validates captured contract fixtures. It reports the temporary log directory.
`--artifacts path/to/new-directory` keeps those artifacts in a chosen fresh path.
Do not run the destructive headless test scripts directly against normal saves.

Verified with Godot 4.5.1: 157 gameplay/integration checks, a fresh-process backup
recovery check, and 50 schema-validated source/bundle/save/API documents. Coverage
includes both locales and every screen/popup, all venue and band tiers, hit and
upgrade gates, song duration and duplicate rewards, offline caps and exact-once
settlement, mock conflicts, token rotation and analytics retries. This is structural
UI validation; actual phone layout and Android lifecycle QA remain separate.

The rendered UI was also inspected at 450×800, 450×1000 and 768×1024 window sizes.
`tests/capture_ui.gd` can reproduce captures with a graphics-capable Godot process:
set `DO_ZORE_TEST_USER_DIR` to an isolated absolute save directory and
`DO_ZORE_CAPTURE_OUTPUT` to an absolute output directory, then run
`godot --path client --audio-driver Dummy --script res://tests/capture_ui.gd`.
`tests/capture_floor.gd` takes the same variables and renders every venue full of guests
with a song playing at 1080×1920. Without a
display, wrap either command in `xvfb-run -a` and add `--rendering-driver opengl3`.

The read-only Python progression simulator and its assumptions are documented in
`tools/README.md`. From the repository root run `python tools/economy_simulator.py`.

## TODO / explicit stubs

- Add a kitchen/cook for the kuhinja upgrade and characters for the inspection and VIP events.
- Attach licensed music and sound to the silent hooks; settings already expose
  the intended controls.
- Add real HTTP/auth/cloud integration after the offline slice. Mock behavior
  does not establish compatibility with a deployed backend.
- Complete server-owned balance rules for glass breaking, happy-guest extra stay
  and other gaps listed in `CONTRACT_ISSUES.md`.
- Exercise the Android export on actual portrait phones and cutout/aspect-ratio
  variants; add release signing and distribution configuration outside Git.
- Review English copy and accessibility with final artwork/audio.
- Ads, purchases, account linking and monetization are outside this slice.
