# People pipeline

The game's people are cartoon characters made in Blender from MakeHuman bodies, with Quaternius'
animations. Everything they are built from is CC0 (credits in `client/assets/people/CREDITS.md`).

1. `setup.sh` fetches Blender 4.5 LTS, the MPFB 2 add-on, the MakeHuman asset packs and the animation
   libraries into `$DO_ZORE_ART_CACHE` (default `~/.cache/do-zore-art`), then runs
   `prep_textures.py`, which flattens the hair and clothes textures into painted colour areas with clean
   cut-out edges (needs OpenCV).
2. `build_people.py` (in Blender: `blender -b --python tools/art/people/build_people.py -- OUT [look...]`)
   builds each look in `LOOKS` and writes `LOOK.glb` and `LOOK_atlas.png`:
   - a MakeHuman body with the look's age, weight and build, reshaped into cartoon proportions before
     anything is fitted to it: the head about twice the size (grown about the chin), shorter legs and
     torso, bigger hands and feet, a rounder face with a short jaw and a small nose;
   - the face cleaned into one smooth surface: the eyes closed and stitched, the inside of the mouth and
     eye sockets removed, the slits welded and the face smoothed. The game draws the eyes, brows and mouth
     on it (`client/shaders/person.gdshader`);
   - hair and clothes fitted by MPFB, the game_engine rig (Unreal bone names) and its skin weights;
   - clothes standing a few millimetres off the body, the covered body shrunk a little, slimmer legs
     under dresses, and untucked tops pushed out over the trousers, so nothing pokes through;
   - one mesh and one material: the parts' cartoonised textures packed in a 1024 px atlas (UV), the face
     plane (UV2: eyes at (0.31, 0.41) and (0.69, 0.41), mouth at (0.5, 0.79)) and vertex colours for the
     shader (palette slot, face mask, keep-the-texture's-colours);
   - triangles kept to a budget (`BUDGET`, about 7–9 k per person); Godot adds levels of detail on import.
3. `anim_lib.py` (in Blender) cuts Quaternius' Universal Animation Library 1 and 2 down to the clips the
   game uses: `client/assets/people/people_anims.glb`.
4. `install_people.py --godot GODOT [OUT]` copies the looks into `client/assets/people`, writes the
   humanoid bone maps (`bone_maps.gd`) and gives every GLB the import options that retarget it to
   Godot's humanoid profile, so the one animation library plays on every body.

The cast (`LOOKS`) follows the guest types: three dede (flat cap and knitted sweater; old suit and
fedora; overalls, with a šajkača added in the game), two babe (grey bun; tiered dress under a
headscarf), two students and two studentkinje (logo t-shirt and jeans; t-shirt or sweater over jeans),
the groom, a wedding guest, the bride and a guest in a dress, two businessmen and a businesswoman,
mourners, staff and the band. Hats, scarves, backpacks, veils, wreaths, chains and aprons that the
MakeHuman packs don't have are made in the game (`people3d.gd`), and moustaches, beards and wrinkles
are drawn by the face shader.

To add a role, add a look to `LOOKS` (an asset folder and file from the MakeHuman packs per part, its
palette slot, and whether it keeps its texture's colours or takes the person's palette), build it,
install, and use it in `make_look` in `client/scripts/world3d/people3d.gd`.
