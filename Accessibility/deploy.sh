#!/usr/bin/env bash
# Deploy the Accessibility addon to the game's Interface/AddOns directory.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC/../config.sh"

rm -rf "$ADDON_DEST"
mkdir -p "$ADDON_DEST"

cp "$SRC"/*.toc "$SRC"/*.lua "$SRC"/*.xml "$ADDON_DEST/"
cp -r "$SRC"/Libs "$ADDON_DEST/Libs"
cp -r "$SRC"/Core "$SRC"/Game "$SRC"/Utils "$SRC"/UI "$ADDON_DEST/"

echo "deployed: $ADDON_DEST"
