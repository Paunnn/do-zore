# Do Zore mobile client

Godot 4.x / GDScript offline vertical slice. The design viewport is 1080 × 1920
portrait; the UI uses expanding containers, scroll views and safe-area padding.
Serbian Latin (`sr`) is the default language, with an English (`en`) catalog.
The main screen is a painted kafana with animated band and guests (see **Art**);
audio hooks are still silent.

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

- New groups arrive and sit at the tables. A bubble above a table shows what they
  ordered: tap the table to serve it (a ring fills while it is prepared). Tap a
  table again for its details. The coloured note badge is the genre they want.
- Tap the stage or **Izaberi pesmu** to play a known song. The accordionist plays
  while it lasts and happy tables dance. Faces show each table's mood; when guests
  leave, their bill and bakšiš float up from the table.
- Matching music improves table mood and eventual bakšiš. Mismatches and long
  waits reduce mood. Nearby unhappy groups can trigger a fight.
- The bottom navigation opens **Kafana**, **Bend**, **Piće**, **Unapređenja** and
  **Lokali**. Hire each band tier, buy upgrades and songs, and advance from
  **birtija → kafana → restoran → splav** using data-defined prices and gates.
- Random events offer choices with costs and consequences. Settings controls
  language, sound/music hooks and a confirmed progress reset. The leaderboard,
  offline-earnings dialog and cloud-conflict dialog use mock data in this slice.

## Art

`scripts/ui/floor_view.gd` draws the floor: the painted room, a repeating floor
below it, flickering lanterns and string lights, the musician animation and one
`scripts/ui/table_view.gd` per table. Tables follow the simulation's
`floor_columns` grid (staggered), so a venue with more tables simply scrolls. Each
table is three painted layers with up to four guests between them (two facing us,
two seen from behind) plus a `+N` badge for bigger parties.

Assets live in `assets/art` (painted layers, `layout.json`) and `assets/sprites`
(SVG guests in three moods and from behind, drinks and icons; Godot imports the SVG
files directly). Both are generated: see `tools/README.md` and
`art_source/README.md` for how to rebuild them and where the paintings came from.

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
`tests/capture_floor.gd` takes the same variables and renders a busy floor (song
playing, every order state, dancing and angry tables) at 1080×1920. Without a
display, wrap either command in `xvfb-run -a` and add `--rendering-driver opengl3`.

The read-only Python progression simulator and its assumptions are documented in
`tools/README.md`. From the repository root run `python tools/economy_simulator.py`.

## TODO / explicit stubs

- Give each venue its own painted room (all four currently share the kafana).
- Animate guests arriving/leaving with walking sprites and add waiter characters.
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
