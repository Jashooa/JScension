#!/usr/bin/env bash
# Deploy both components: the Accessibility addon and the Compatibility
# shim. Run this after any change to either component.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# --- Accessibility addon -> Interface/AddOns ---
case "$ADDON_DEST" in
	*/Interface/AddOns/Accessibility) ;;
	*) echo "refusing to delete unexpected path: $ADDON_DEST" >&2; exit 1 ;;
esac
rm -rf "$ADDON_DEST"
mkdir -p "$ADDON_DEST"

ADDON_SRC="$SOLUTION_DIR/Accessibility"
cp "$ADDON_SRC"/*.toc "$ADDON_SRC"/*.lua "$ADDON_SRC"/*.xml "$ADDON_DEST/"
cp -r "$ADDON_SRC"/Libs "$ADDON_DEST/Libs"
cp -r "$ADDON_SRC"/Core "$ADDON_SRC"/Game "$ADDON_SRC"/Utils "$ADDON_SRC"/UI "$ADDON_DEST/"
echo "deployed: $ADDON_DEST"

# --- Compatibility shim: build into Solution/bin, then install to C:\local
# (outside the launcher-managed folders, so it survives repairs). ---
"$SOLUTION_DIR/scripts/build.sh"
mkdir -p "$COMPAT_DEPLOY_DIR"
install -m 755 "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME" "$COMPAT_DEPLOY_DIR/"
echo "deployed:"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_DLL_NAME"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_EXE_NAME"

echo "all components deployed"
