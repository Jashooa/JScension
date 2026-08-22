#!/usr/bin/env bash
# Local settings for the Accessibility addon and the Compatibility shim.
# Copy this file to scripts/config.sh and edit the marked machine-specific
# values. The copied file is gitignored.
#
# Path rules:
#   - The game lives under the Ascension Launcher's resources folder inside
#     the Wine prefix.
#   - The launcher repairs its own game-dir files, so we never write into the
#     game directory except the addon folder (Interface/AddOns).
#   - Compatibility artifacts go to C:\local, which the launcher does not
#     manage and therefore never deletes.
#
# This file is sourced by the other scripts; do not run it directly.
#
# Machine-specific: Wine prefix containing the game installation.
PREFIX="/path/to/your/wine/prefix"

# Solution root (parent of this scripts/ folder).
SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Game install root (inside the prefix). The launcher owns everything here
# except the addon folder below.
GAME_DIR="$PREFIX/drive_c/Program Files/Ascension Launcher/resources/ascension-live"

# Accessibility deploy folder (inside the game's Interface/AddOns).
ADDON_DEST="$GAME_DIR/Interface/AddOns/Accessibility"

# Compatibility deploy folder (the wine C:\local directory, which is outside
# the launcher-managed folders and so survives repairs).
COMPAT_DEPLOY_DIR="$PREFIX/drive_c/local"

# File names produced by scripts/build.sh.
COMPAT_DLL_NAME="compatibility.dll"
COMPAT_EXE_NAME="compatibility.exe"

# Toolchain commands. Use absolute paths when they are not on PATH.
MINGW_CC="i686-w64-mingw32-gcc"
MINGW_OBJDUMP="i686-w64-mingw32-objdump"

# Build output folder (gitignored; the shim + injector binaries live here).
COMPAT_BIN_DIR="$SOLUTION_DIR/bin"

# Machine-specific: Wine binary used to run the injector.
WINE="/path/to/your/wine"

