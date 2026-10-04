# Do Zore mobile client

Godot 4.x / GDScript offline vertical slice. The design viewport is 1080 × 1920
portrait; the UI uses expanding containers, scroll views and safe-area padding.
Serbian Latin (`sr`) is the default language, with an English (`en`) catalog.
The main screen is a lit 3D night city that doubles as the map, with the venue being played
as a roofless cut-away full of guests (see **Art**), with kafana music and sounds (see **Audio**).

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

- Guests come on foot down the street, walk in and sit down while townspeople stroll the
  pavements outside; a thought cloud shows what they ordered. A waiter takes it by himself after
  a few seconds (sooner with **Konobar** levels); tap the cloud or the table to serve it at once
  (a ring fills while it is prepared) and tap the table again for details. Each round is paid
  when the waiter sets it down ("+ din" over the table) and a party adds its bakšiš when it
  leaves. A visit lasts about one and a half to three minutes with three to five rounds. A small
  cloud with a coloured note is the genre they want.
- Tap the stage or the red **Pesma** button to play a known song (about a minute): the band
  plays, notes rise and happy tables get up to dance.
- Matching music improves table mood and the bakšiš. Mismatches and long waits reduce
  mood. Nearby unhappy groups can trigger a fight.
- The kafana keeps working while the app is closed: after a minute or more away, a dialog shows
  what it earned (about a third of the active rate, up to the venue's cap of 2 to 8 hours).
- Pacing, measured by playing the real simulation with a bot that plays requested songs and buys
  upgrades: the kafana opens after about 12 minutes, the restoran after 35–45 and the splav after
  about two hours of play.
- The HUD floats over the city in one row: the venue on its red ribbon, money, the room's mood
  and guests, and settings; under it a slim strip shows the road to the next venue (tap it for
  **Lokali**). **Bend**, **Piće** and **Rang** sit on the right; **Mapa**, **Pesma** and
  **Unapređenja** at the bottom, with the song playing just above **Pesma**. One red badge
  marks the most useful next step.
- The night turns from a warm dusk to deep night and on to dawn; every new venue opens at dusk.
- **Mapa** pulls the camera out over the whole city: the birtija at the village edge, the
  kafana in the old town, the restoran on the central square and the splav on the river. The
  next venue shows its price; tap a venue to see it in **Lokali**. Buying it plays a short
  opening and flies the camera across the city to the new place.
- Random events offer choices with costs and consequences. Settings controls language,
  sound, music and a confirmed progress reset. The leaderboard, offline-earnings dialog
  and cloud-conflict dialog use mock data in this slice.

## Art

Everything is drawn in real time in 3D with the Compatibility renderer, through an orthographic
isometric camera, in the lit low-poly style of idle tycoon games (`design/research.md` explains
the choice). `scripts/ui/floor_view.gd` hosts the 3D world in a `SubViewport` (drag to pan, pinch
or wheel to zoom from a table close-up out to the whole map, tap to act) and keeps the 2D thought
clouds, coins and notes over their 3D anchors.

- `scripts/world3d/city3d.gd` builds the city on a 52 m street grid in four districts along the
  road "up" the screen: village houses with porches, old-town blocks with shuttered windows,
  pediments, dormers and shops, centre blocks with balconies and rooftop clutter around
  courtyards, the square, the river with its quay and bridge, the far bank, parked and passing
  cars and townspeople walking round the blocks. Facades near the played venue get full detail;
  the rest keep their shapes and lit windows. Buildings in front of the played venue give way
  to small parks so it is never hidden.
- `scripts/world3d/venue3d.gd` lays out and builds each venue: the played one as a cut-away
  (floor, back walls with windows, bar, stage, themed decor, pendant lamps with real lights, a
  table set per slot); the others as closed buildings with their signs. Paintings, kilims, the
  clock, peppers and wall lamps are laid out along the side wall by one plan (`wall_plan`), each in
  the widest free stretch between the windows, so nothing hangs over a window or over another
  piece.
- `scripts/world3d/venue_world.gd` turns simulation state into people and props: parties walk
  in from the street along an A* grid (a party in single file; everyone steers round everyone
  else, see `People.steer_crowd`), pull out their chairs and sit
  down, order, drink, get up to dance and leave; waiters walk out from the bar with the
  tray level on the flat of the left hand (the glasses stand up on it), set the order down on the
  table with the right hand and walk back with the empty tray; the band plays; konobar,
  ozvučenje, dekor, izbacivač and sef levels show. The chairs are one MultiMesh per room so
  each can slide out and back. A served order puts its bottle or dish in the middle of the
  table and a cup or glass in front of every seated guest.
- `scripts/world3d/people3d.gd` dresses each character from a look (guest type, staff or
  musician): one of the cartoon people in `assets/people` (built in Blender from MakeHuman bodies,
  CC0; see `tools/art/people`) with a palette, a face style (lashes, brows, lipstick, glasses), an
  age (wrinkles, moustache, beard, bushy brows) and a mood. Props sit on its bones: šajkača,
  headscarf, beanie, bridal veil, flower wreath, backpack, gold chain, apron, bow ties, flowers
  and instruments. The šajkača, the headscarf (tied at the nape) and the bride's veil are shaped
  to the cartoon heads (measured tables in `people3d.gd`) so nothing goes through them. The cast follows
  the guest types: penzioneri in flat caps, fedoras, šajkače and headscarves; classic students in logo t-shirts, jeans and trainers with backpacks; the
  bride and the wedding guests; businessmen in suits; mourners in black. The animation library
  (`people_anims.glb`, Quaternius' Universal Animation Library, CC0) is retargeted on import
  through Godot's humanoid profile, so it plays on every body; a few clips are put together from
  two at run time. Sitting down and getting up use the library's sit-down and stand-up clips with
  the hips lifted onto the seat. Musicians' hands are put on their instruments with a grip (`_grip`): the arm by
  two-bone IK, the hand turned so the palm lies on the instrument and the fingers curled round the
  neck, over the keys or round the bow. Drinking is two-bone IK on the right arm: reach for the glass,
  lift it to the lips, tip and sip, put it back. Props and the mouth are placed through the skin's
  bind poses (the import's rest fixer moves the rests, not the mesh). The face is drawn by
  `shaders/person.gdshader` from a few numbers per person, eased towards the person's mood, with
  blinks, chatter and sips on top; `shaders/ink.gdshader` is the outline (also round the props), set
  a little behind the surface so the inside of a garment seen through an opening shows its cloth.
- `scripts/world3d/builder.gd` merges primitives per material and per spatial chunk;
  `kit3d.gd` holds the shared materials: the toon world shader (`shaders/world.gdshader`: vertex
  colours times painted textures mapped in world space or by UV, two-tone light, sheen), one glow
  shader for every lamp and window, and the river shader.

Budget, measured with a full venue (about 80 people): 440–620 draw calls and 500–580 k
triangles at venue zoom, 760–960 draw calls with the whole map in view (two draws per person
and per prop, body and outline; one per glass on the tables; people take coarser levels of
detail early, `lod_bias` 0.3; the contact shadows under people and tables are one MultiMesh, the
walkers' another, the chairs a third).

The interface is the modern-kafana kit in `scripts/ui/ui_kit.gd` (floating pills, glossy round
and lipped buttons, cream cards with a red header over a tablecloth trim); see
`design/README.md`. Fonts: Shrikhand, Titan One and Nunito (SIL Open Font License, licences in
`assets/fonts`). The characters are cartoon MakeHuman people with Quaternius' animations (CC0,
`assets/people/CREDITS.md`); the
streets, walls and roofs are painted-over Poly Haven scans (CC0, `assets/textures/SCANNED.md`);
everything else is
generated from code: see `tools/README.md`. The venue, band and
guest pictures in `assets/ui/{venues,bands,guests}` are renders of the 3D models made with
`tests/render_venue_cards.gd`.

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

## iPhone

**Play in Safari (no Mac needed).** Export the **Web** preset (single-threaded, ETC2/ASTC and S3TC
textures, a home-screen manifest) and host the folder over HTTPS; on the iPhone open it in Safari,
then Share → Add to Home Screen to get a full-screen app icon. The build needs no special server
headers (no threads). From the repository root:

```sh
godot --headless --path client --export-release "Web" export/web/index.html
```

**Install as an app (Mac).** iOS apps can only be built and signed on a Mac with Xcode. From the
repository root run `tools/ios/make_ios_app.sh`: it downloads Godot 4.5.1 and the iOS export template
into `~/.do-zore` once, exports the **iOS** preset (`application/export_project_only`) to
`export/ios/DoZore.xcodeproj` and opens it in Xcode. There, choose your Apple ID team under the
DoZore target's Signing & Capabilities, plug in the iPhone, pick it at the top and press Run. The
first time, enable Developer Mode on the iPhone (Settings → Privacy & Security) and trust the
developer under Settings → General → VPN & Device Management. With a free Apple ID the app runs for
7 days, then run it from Xcode again. `TEAM_ID` and `BUNDLE_ID` override the detected team and the
default `rs.dozore.client` identifier; the committed preset keeps both blank/default.

## Audio

`scripts/autoload/kafana_audio.gd` (autoload `KafanaAudio`) plays the music and sounds. While a song
is on, the band's track (`assets/audio/songs/<song id>.ogg`) plays; between songs a quieter
venue tune (`between_<venue>.ogg`) loops, and the music drops further when the camera is out on
the city map. Two players crossfade between tracks. `EventBus.audio_requested` cues map to the
short sounds in `assets/audio/sfx` (glasses, pouring, coins, a breaking glass, event stings, the
opening fanfare). The music and sound settings switch each part off. On iOS the audio session
is **Playback** mixed with other apps (`audio/general/ios/session_category`), so the music
plays with the ring/silent switch on, and a track stopped by a call or the background is picked
up again. In a browser, Safari starts web audio only from a tap: the web page resumes the
game's audio context on taps until it runs.

All of it is original and synthesised by `tools/audio/kafana_music.py` (Python with numpy and
scipy, ffmpeg for OGG): accordion, tamburica, guitar, bass, violin, tapan and darbuka in the four
song styles: starogradske waltzes in 3/4, izvorna kolo in 2/4, tamburica in 2/4 and narodnjaci
in 7/8. Each track is rendered twice and the second pass kept, so the reverb tail wraps and the
loop is seamless. Re-run it from the repository root to regenerate the files.

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

Verified with Godot 4.5.1: 162 gameplay/integration checks, a fresh-process backup
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
with a song playing at 1080×1920. `tests/render_venue_cards.gd` re-renders the interface
pictures from the 3D models. Without a
display, wrap either command in `xvfb-run -a` and add `--rendering-driver opengl3`.

The read-only Python progression simulator and its assumptions are documented in
`tools/README.md`. From the repository root run `python tools/economy_simulator.py`.

## TODO / explicit stubs

- Add a kitchen/cook for the kuhinja upgrade and characters for the inspection and VIP events.
- Replace or extend the generated music and sound (`tools/audio/kafana_music.py`) with recorded
  performances if wanted.
- Add real HTTP/auth/cloud integration after the offline slice. Mock behavior
  does not establish compatibility with a deployed backend.
- Complete server-owned balance rules for glass breaking, happy-guest extra stay
  and other gaps listed in `CONTRACT_ISSUES.md`.
- Exercise the Android export on actual portrait phones and cutout/aspect-ratio
  variants; add release signing and distribution configuration outside Git.
- Review English copy and accessibility with final artwork/audio.
- Ads, purchases, account linking and monetization are outside this slice.
