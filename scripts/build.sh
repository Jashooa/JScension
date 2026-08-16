#!/usr/bin/env bash
# Build compatibility.dll (the shim) + compatibility.exe (the injector)
# into the Solution bin/ folder (gitignored build output).
# Requires i686-w64-mingw32-gcc (mingw-w64).
# Sources config.sh for the artifact file names, so a rename touches one file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

mkdir -p "$COMPAT_BIN_DIR"
i686-w64-mingw32-gcc -O2 -shared -o "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" "$SOLUTION_DIR/Compatibility/shim.c" "$SOLUTION_DIR/Compatibility/compatibility.def" \
    -static-libgcc -Wl,--exclude-all-symbols
i686-w64-mingw32-gcc -O2 -o "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME" "$SOLUTION_DIR/Compatibility/injector.c" -static-libgcc

# The registered callback's descriptor bytes (entry+0x4d..0x4f) must read
# b3 01 00: the game's call wrapper consumes them as per-function metadata,
# and a compiler change that shifts the naked stub breaks the arg machinery
# silently. Fail the build here instead of crashing in-game.
CB_VMA="$(i686-w64-mingw32-objdump -d "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" | awk '/<_Compatibility_cb>:/{vma=$1} END{print vma}')"
if [ -z "$CB_VMA" ]; then
	echo "error: Compatibility_cb symbol not found; cannot verify descriptor bytes" >&2
	exit 1
fi
CB_BYTES="$(i686-w64-mingw32-objdump -s \
	--start-address="0x$(printf '%x' $((0x$CB_VMA + 0x4d)))" \
	--stop-address="0x$(printf '%x' $((0x$CB_VMA + 0x50)))" \
	"$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" | awk 'NR==5{bytes=$2} END{print bytes}')"
if [ "$CB_BYTES" != "b30100" ]; then
	echo "error: Compatibility_cb descriptor bytes are '$CB_BYTES', expected 'b30100'" >&2
	echo "       a toolchain change altered the naked stub; see CALLBACK DESCRIPTOR" >&2
	echo "       CONSTRAINT in Compatibility/shim.c" >&2
	exit 1
fi
echo "verified: Compatibility_cb descriptor bytes b3 01 00"
echo "built: $COMPAT_BIN_DIR/$COMPAT_DLL_NAME + $COMPAT_BIN_DIR/$COMPAT_EXE_NAME"
