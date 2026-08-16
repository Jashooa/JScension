#!/usr/bin/env bash
# Shared settings for the Accessibility addon and the Compatibility shim.
# Source this file from the other scripts; do not run it directly.
#
# Path rules:
#   - The game lives under the Ascension Launcher's resources folder inside
#     the Wine prefix.
#   - The launcher repairs its own game-dir files, so we never write into the
#     game directory except the addon folder (Interface/AddOns).
#   - Compatibility artifacts go to C:\local, which the launcher does not
#     manage and therefore never deletes.

# Solution root (parent of this scripts/ folder). Each sourcing script may set
# it already; recomputing from this file's location is always correct.
SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Wine prefix containing the game installation.
PREFIX="/mnt/games/Faugus/ascension-test/pfx"

# Game install root (inside the prefix). The launcher owns everything here
# except the addon folder below.
GAME_DIR="$PREFIX/drive_c/Program Files/Ascension Launcher/resources/ascension-live"

# Accessibility deploy folder (inside the game's Interface/AddOns).
ADDON_DEST="$GAME_DIR/Interface/AddOns/Accessibility"

# Compatibility deploy folder (the wine C:\local directory, which is outside
# the launcher-managed folders and so survives repairs). Named for its role,
# not for the value's folder name.
COMPAT_DEPLOY_DIR="$PREFIX/drive_c/local"

# File names produced by scripts/build.sh.
COMPAT_DLL_NAME="compatibility.dll"
COMPAT_EXE_NAME="compatibility.exe"

# Build output folder (gitignored; the shim + injector binaries live here).
COMPAT_BIN_DIR="$SOLUTION_DIR/bin"

# Wine binary used to run the injector (Proton's 32-bit capable wine).
WINE="/home/jash/.local/share/Steam/compatibilitytools.d/Proton-CachyOS Latest/files/bin/wine"

# Game process pattern used to detect the running client.
GAME_PROC_PATTERN="ascension-live.*Ascension[.]exe"
