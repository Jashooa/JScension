#!/usr/bin/env bash
# Inject the Compatibility shim into the running game. Run this after the
# game is at (or past) the login screen, then watch for the
# COMPATIBILITY_RUN=1 self-test in chat.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/script_helpers.sh"
load_config

for required_value in \
    PREFIX COMPAT_DEPLOY_DIR COMPAT_EXE_NAME WINE GAME_PROC_PATTERN; do
    require_config_value "$required_value"
done
require_executable "$WINE"
require_command pgrep
require_file "$COMPAT_DEPLOY_DIR/$COMPAT_EXE_NAME"

case "$COMPAT_DEPLOY_DIR" in
    "$PREFIX/drive_c"/*) ;;
    *)
        echo "refusing to inject from outside the Wine prefix: $COMPAT_DEPLOY_DIR" >&2
        exit 1
        ;;
esac

# Wine maps "$PREFIX/drive_c" to C:. Convert the Compatibility deploy folder
# to its Windows form and append the injector file name.
WIN_DIR="C:${COMPAT_DEPLOY_DIR#"$PREFIX/drive_c"}"
WIN_DIR="${WIN_DIR//\//\\}"
EXE="${WIN_DIR}\\${COMPAT_EXE_NAME}"

if pgrep -f "$GAME_PROC_PATTERN" >/dev/null 2>&1; then
    echo "game process found"
else
    echo "warning: no ascension-live game process found (injector will report 'game window not found')"
fi

echo "launching injector: $EXE"
WINEPREFIX="$PREFIX" "$WINE" "$EXE"
