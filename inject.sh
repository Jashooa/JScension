#!/usr/bin/env bash
# Inject the Compatibility shim into the running game. Run this after the
# game is at (or past) the login screen, then watch for the
# COMPATIBILITY_RUN=1 self-test in chat.
set -euo pipefail

SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOLUTION_DIR/config.sh"

# Wine maps "$PREFIX/drive_c" to C:. Convert the Compatibility deploy folder
# to its Windows form and append the injector file name.
WIN_DIR="C:${COMPAT_DEPLOY_DIR#"$PREFIX/drive_c"}"
EXE="${WIN_DIR//\//\\}\\$COMPAT_EXE_NAME"

if pgrep -f "$GAME_PROC_PATTERN" >/dev/null 2>&1; then
    echo "game process found"
else
    echo "warning: no ascension-live game process found (injector will report 'game window not found')"
fi

WINEPREFIX="$PREFIX" "$WINE" "$EXE"
