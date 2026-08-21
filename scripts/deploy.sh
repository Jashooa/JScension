#!/usr/bin/env bash
# Deploy both components: the Accessibility addon and the Compatibility
# shim. Run this after any change to either component.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/script_helpers.sh"
load_config

for required_value in \
    SOLUTION_DIR PREFIX GAME_DIR ADDON_DEST COMPAT_DEPLOY_DIR \
    COMPAT_BIN_DIR COMPAT_DLL_NAME COMPAT_EXE_NAME; do
    require_config_value "$required_value"
done
require_command install
require_directory "$PREFIX/drive_c"
require_directory "$GAME_DIR"

ADDON_SRC="$SOLUTION_DIR/Accessibility"
ADDON_PARENT="$GAME_DIR/Interface/AddOns"
EXPECTED_ADDON_DEST="$ADDON_PARENT/Accessibility"
if [[ "$ADDON_DEST" != "$EXPECTED_ADDON_DEST" ]]; then
    echo "refusing to deploy to unexpected path: $ADDON_DEST" >&2
    echo "expected: $EXPECTED_ADDON_DEST" >&2
    exit 1
fi
case "$COMPAT_DEPLOY_DIR" in
    "$PREFIX/drive_c"/*) ;;
    *)
        echo "refusing to deploy compatibility artifacts outside the Wine prefix: $COMPAT_DEPLOY_DIR" >&2
        exit 1
        ;;
esac

require_directory "$ADDON_SRC"
for addon_directory in Libs Core Game Utils UI; do
    require_directory "$ADDON_SRC/$addon_directory"
done
for addon_file in Accessibility.toc Accessibility.lua Bindings.xml; do
    require_file "$ADDON_SRC/$addon_file"
done

"$SOLUTION_DIR/scripts/test.sh"
"$SOLUTION_DIR/scripts/build.sh"
require_file "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME"
require_file "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME"

mkdir -p "$ADDON_PARENT"
STAGING_DIR="$(mktemp -d "$ADDON_PARENT/.Accessibility.staging.XXXXXX")"
BACKUP_DIR=""
cleanup() {
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    if [[ -n "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
    fi
}
trap cleanup EXIT

cp "$ADDON_SRC"/*.toc "$ADDON_SRC"/*.lua "$ADDON_SRC"/*.xml "$STAGING_DIR/"
cp -r "$ADDON_SRC"/Libs "$STAGING_DIR/Libs"
cp -r "$ADDON_SRC"/Core "$ADDON_SRC"/Game "$ADDON_SRC"/Utils "$ADDON_SRC"/UI "$STAGING_DIR/"

mkdir -p "$COMPAT_DEPLOY_DIR"
install -m 755 \
    "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" \
    "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME" \
    "$COMPAT_DEPLOY_DIR/"

if [[ -e "$ADDON_DEST" || -L "$ADDON_DEST" ]]; then
    BACKUP_DIR="$(mktemp -d "$ADDON_PARENT/.Accessibility.backup.XXXXXX")"
    rmdir "$BACKUP_DIR"
    mv "$ADDON_DEST" "$BACKUP_DIR"
fi

if ! mv "$STAGING_DIR" "$ADDON_DEST"; then
    if [[ -n "$BACKUP_DIR" ]]; then
        mv "$BACKUP_DIR" "$ADDON_DEST"
        BACKUP_DIR=""
    fi
    echo "error: could not replace addon deployment at $ADDON_DEST" >&2
    exit 1
fi
STAGING_DIR=""

if [[ -n "$BACKUP_DIR" ]]; then
    rm -rf "$BACKUP_DIR"
    BACKUP_DIR=""
fi

echo "deployed: $ADDON_DEST"
echo "deployed:"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_DLL_NAME"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_EXE_NAME"
echo "all components deployed"
