"""Put built people into the game: copy the GLBs and atlases into client/assets/people, write the humanoid
bone maps, and give every GLB the import options that retarget it to Godot's humanoid profile (so the
animation library plays on all of them).

    python3 tools/art/people/install_people.py --godot GODOT [OUT_DIR]

OUT_DIR is where build_people.py wrote the looks (default $DO_ZORE_ART_CACHE/out).
"""
import argparse
import glob
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLIENT = ROOT / "client"
PEOPLE = CLIENT / "assets/people"
CACHE = os.environ.get("DO_ZORE_ART_CACHE", os.path.expanduser("~/.cache/do-zore-art"))

RETARGET = '''_subresources={
"nodes": {
"PATH:Armature/Skeleton3D": {
"retarget/bone_map": Resource("res://assets/people/%s_bones.tres"),
"retarget/rest_fixer/fix_silhouette/enable": true
}
}
}'''


def godot_import(godot: str) -> None:
    subprocess.run([godot, "--headless", "--path", str(CLIENT), "--import"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("out", nargs="?", default=os.path.join(CACHE, "out"))
    args = parser.parse_args()
    PEOPLE.mkdir(parents=True, exist_ok=True)
    for old in PEOPLE.iterdir():
        if old.name.startswith("people_anims") or old.suffix == ".tres":
            continue
        if old.name.endswith((".glb", ".glb.import", "_atlas.png", "_atlas.png.import")):
            old.unlink()
    for source in glob.glob(os.path.join(args.out, "*.glb")) + glob.glob(os.path.join(args.out, "*_atlas.png")):
        shutil.copy(source, PEOPLE)
    subprocess.run([args.godot, "--headless", "--path", str(CLIENT), "--script",
                    str(Path(__file__).with_name("bone_maps.gd"))], check=True, stdout=subprocess.DEVNULL)
    godot_import(args.godot)
    for path in PEOPLE.glob("*.glb.import"):
        text = path.read_text()
        sub = RETARGET % ("ual" if path.name.startswith("people_anims") else "mh")
        if '"retarget/bone_map"' not in text:
            path.write_text(text.replace("_subresources={}", sub))
    # Atlases: VRAM-compressed with mipmaps (people are small on screen most of the time).
    for path in PEOPLE.glob("*_atlas.png.import"):
        text = path.read_text()
        text = text.replace("compress/mode=0", "compress/mode=2").replace("mipmaps/generate=false", "mipmaps/generate=true")
        path.write_text(text.replace("detect_3d/compress_to=1", "detect_3d/compress_to=0"))
    for glb in list(PEOPLE.glob("*.glb")) + list(PEOPLE.glob("*_atlas.png")):
        glb.touch()
    godot_import(args.godot)
    print(f"Installed {len(list(PEOPLE.glob('*.glb')))} GLBs into {PEOPLE}")


if __name__ == "__main__":
    main()
