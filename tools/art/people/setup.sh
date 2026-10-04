#!/bin/bash
# Fetch everything the people pipeline needs into $DO_ZORE_ART_CACHE (default ~/.cache/do-zore-art):
# Blender 4.5 LTS, the MPFB 2 add-on (GPL code; the assets it makes are CC0), the MakeHuman asset packs
# (CC0), and Quaternius' Universal Animation Library 1 and 2 (CC0). Then cartoonise the textures.
#
#   tools/art/people/setup.sh
#
# Afterwards:
#   $CACHE/blender/blender -b --python tools/art/people/build_people.py -- $CACHE/out
#   $CACHE/blender/blender -b --python tools/art/people/anim_lib.py -- client/assets/people/people_anims.glb
#   python3 tools/art/people/install_people.py --godot GODOT
set -euo pipefail
CACHE=${DO_ZORE_ART_CACHE:-$HOME/.cache/do-zore-art}
HERE=$(cd "$(dirname "$0")" && pwd)
BLENDER_VERSION=4.5.14
mkdir -p "$CACHE" && cd "$CACHE"

if [ ! -x blender/blender ]; then
  curl -sSL -o blender.tar.xz "https://download.blender.org/release/Blender4.5/blender-$BLENDER_VERSION-linux-x64.tar.xz"
  tar xf blender.tar.xz && rm blender.tar.xz
  ln -sfn "blender-$BLENDER_VERSION-linux-x64" blender
fi

if [ ! -d mpfb2 ]; then
  git clone --depth 1 https://github.com/makehumancommunity/mpfb2
fi
(cd mpfb2/src && rm -f ../../mpfb.zip && zip -qr ../../mpfb.zip mpfb)
blender/blender --command extension install-file -r user_default -e mpfb.zip >/dev/null

# MakeHuman asset packs (all CC0).
mkdir -p mh/data
for pack in asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip functional/faceunits01.zip \
            asset_packs/hair01/hair01_cc0.zip asset_packs/shirts01/shirts01_cc0.zip asset_packs/suits01/suits01_cc0.zip \
            asset_packs/hats01/hats01_cc0.zip asset_packs/pants01/pants01_cc0.zip asset_packs/dress01/dress01_cc0.zip; do
  file=mh/$(basename "$pack")
  [ -f "$file" ] || curl -sSL -o "$file" "https://files.makehumancommunity.org/$pack"
  unzip -qo "$file" -d mh/data
done
# MPFB looks for user assets in its extension data folder.
USER_DATA=$(blender/blender -b --python-expr "import bpy; print('DATA=' + bpy.utils.extension_path_user('bl_ext.user_default.mpfb', create=True))" 2>/dev/null | sed -n 's/^DATA=//p')/data
mkdir -p "$USER_DATA"
for dir in mh/data/*; do
  ln -sfn "$CACHE/$dir" "$USER_DATA/$(basename "$dir")"
done

# Quaternius' animation libraries come from itch.io (free downloads, CC0).
itch() {
  local game=$1 out=$2 jar
  jar=$(mktemp)
  local token url page
  token=$(curl -s -c "$jar" -b "$jar" "$game/purchase" | grep -oE 'csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')
  url=$(curl -s -c "$jar" -b "$jar" -X POST --data-urlencode "csrf_token=$token" "$game/download_url" | python3 -c 'import sys,json;print(json.load(sys.stdin)["url"])')
  page=$(curl -s -c "$jar" -b "$jar" "$url")
  token=$(echo "$page" | grep -oE 'csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')
  for id in $(echo "$page" | grep -oE 'data-upload_id="[0-9]+"' | grep -oE '[0-9]+' | sort -u); do
    url=$(curl -s -c "$jar" -b "$jar" -X POST --data-urlencode "csrf_token=$token" "$game/file/$id?source=game_download" | python3 -c 'import sys,json;print(json.load(sys.stdin)["url"])')
    curl -sSL -o "$out" "$url"
  done
}
mkdir -p anim
[ -f anim/ual1.zip ] || itch https://quaternius.itch.io/universal-animation-library anim/ual1.zip
[ -f anim/ual2.zip ] || itch https://quaternius.itch.io/universal-animation-library-2 anim/ual2.zip
unzip -qo anim/ual1.zip -d anim/ual1
unzip -qo anim/ual2.zip -d anim/ual2

python3 -m pip install --quiet opencv-python-headless numpy
DO_ZORE_ART_CACHE=$CACHE python3 "$HERE/prep_textures.py"
echo "People pipeline ready in $CACHE"
