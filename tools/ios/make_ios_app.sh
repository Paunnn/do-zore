#!/bin/bash
# Builds the Do Zore iPhone app on a Mac and opens it in Xcode.
#
#   tools/ios/make_ios_app.sh
#
# Downloads Godot 4.5.1 and its iOS export template into ~/.do-zore (once), exports the "iOS"
# preset as an Xcode project into export/ios, then opens it in Xcode. In Xcode: pick your team
# under Signing & Capabilities, plug in the iPhone and press Run.
#
# Optional environment:
#   TEAM_ID    Apple team id (10 characters). Found automatically from your "Apple Development"
#              certificate once Xcode has signed in with your Apple ID; otherwise pick the team in Xcode.
#   BUNDLE_ID  App identifier, default rs.dozore.client. Change it if Xcode says it is taken.
#   GODOT      Path to an existing Godot 4.5.1 binary to use instead of downloading one.
set -euo pipefail

VERSION=4.5.1
TAG=$VERSION-stable
RELEASES=https://github.com/godotengine/godot/releases/download/$TAG
CACHE=$HOME/.do-zore
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$VERSION.stable"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CLIENT=$ROOT/client
OUT=$ROOT/export/ios
BUNDLE_ID=${BUNDLE_ID:-rs.dozore.client}

[ "$(uname)" = Darwin ] || { echo "iOS apps can only be built on a Mac."; exit 1; }
[ -d "$(xcode-select -p 2>/dev/null)/Platforms/iPhoneOS.platform" ] || {
	echo "Xcode is needed: install it from the App Store and open it once."
	echo "If it is installed, run: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }
mkdir -p "$CACHE"

# Godot itself.
if [ -z "${GODOT:-}" ]; then
	GODOT=$CACHE/Godot.app/Contents/MacOS/Godot
	if [ ! -x "$GODOT" ]; then
		echo "Downloading Godot $VERSION..."
		curl -fL --progress-bar -o "$CACHE/godot.zip" "$RELEASES/Godot_v${TAG}_macos.universal.zip"
		unzip -q -o "$CACHE/godot.zip" -d "$CACHE" && rm "$CACHE/godot.zip"
		xattr -dr com.apple.quarantine "$CACHE/Godot.app" 2>/dev/null || true
	fi
fi

# The iOS export template (it ships inside the full template bundle, about 1 GB to download once).
if [ ! -f "$TEMPLATES/ios.zip" ]; then
	echo "Downloading the Godot $VERSION export templates (once, about 1 GB)..."
	curl -fL --progress-bar -o "$CACHE/templates.tpz" "$RELEASES/Godot_v${TAG}_export_templates.tpz"
	mkdir -p "$TEMPLATES"
	unzip -q -o -j "$CACHE/templates.tpz" templates/ios.zip templates/version.txt -d "$TEMPLATES"
	rm "$CACHE/templates.tpz"
fi

# The team that signs the app: the one behind your Apple Development certificate if there is one.
if [ -z "${TEAM_ID:-}" ]; then
	TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
		| openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
fi
if [ -n "$TEAM_ID" ]; then
	echo "Signing team: $TEAM_ID"
	team=$TEAM_ID
else
	echo "No Apple Development certificate yet: pick your team in Xcode (Signing & Capabilities)."
	team=AAAAAAAAAA   # Godot needs some team id to export; Xcode replaces it when you pick yours.
fi

# Export with the team and bundle id filled in, leaving the committed preset untouched.
cp "$CLIENT/export_presets.cfg" "$CACHE/export_presets.cfg.bak"
trap 'cp "$CACHE/export_presets.cfg.bak" "$CLIENT/export_presets.cfg"' EXIT
sed -i '' -e "s/^application\/app_store_team_id=.*/application\/app_store_team_id=\"$team\"/" \
	-e "s/^application\/bundle_identifier=\"rs.dozore.client\"/application\/bundle_identifier=\"$BUNDLE_ID\"/" \
	"$CLIENT/export_presets.cfg"

echo "Importing the project (the first time takes a few minutes)..."
"$GODOT" --headless --path "$CLIENT" --editor --import >/dev/null 2>&1 || true
rm -rf "$OUT" && mkdir -p "$OUT"
echo "Exporting the Xcode project..."
"$GODOT" --headless --path "$CLIENT" --export-release "iOS" "$OUT/DoZore.ipa"
[ -d "$OUT/DoZore.xcodeproj" ] || { echo "Export failed, see the messages above."; exit 1; }

echo
echo "Done: $OUT/DoZore.xcodeproj"
echo "In Xcode: DoZore target > Signing & Capabilities > Team = your Apple ID,"
echo "plug in the iPhone, choose it at the top, press Run (the play button)."
open "$OUT/DoZore.xcodeproj"
