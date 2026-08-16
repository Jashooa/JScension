#!/bin/sh
# Build compatibility.dll (the shim) + compatibility.exe (the injector)
# into the Solution bin/ folder (gitignored build output).
# Requires i686-w64-mingw32-gcc (mingw-w64).
set -e

# Resolve Solution root and the Compatibility source dir from this file's
# location, so the script works regardless of cwd.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOLUTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$SOLUTION_DIR/bin"
COMPAT_DIR="$SOLUTION_DIR/Compatibility"

mkdir -p "$BIN_DIR"
i686-w64-mingw32-gcc -O2 -shared -o "$BIN_DIR/compatibility.dll" "$COMPAT_DIR/shim.c" "$COMPAT_DIR/compatibility.def" \
    -static-libgcc -Wl,--exclude-all-symbols
i686-w64-mingw32-gcc -O2 -o "$BIN_DIR/compatibility.exe" "$COMPAT_DIR/injector.c" -static-libgcc

# The registered callback's descriptor bytes (entry+0x4d..0x4f) must read
# b3 01 00: the game's call wrapper consumes them as per-function metadata,
# and a compiler change that shifts the naked stub breaks the arg machinery
# silently. Fail the build here instead of crashing in-game.
CB_VMA="$(i686-w64-mingw32-objdump -d "$BIN_DIR/compatibility.dll" | awk '/<_Compatibility_cb>:/{print $1; exit}')"
if [ -z "$CB_VMA" ]; then
	echo "error: Compatibility_cb symbol not found; cannot verify descriptor bytes" >&2
	exit 1
fi
CB_BYTES="$(i686-w64-mingw32-objdump -s \
	--start-address="0x$(printf '%x' $((0x$CB_VMA + 0x4d)))" \
	--stop-address="0x$(printf '%x' $((0x$CB_VMA + 0x50)))" \
	"$BIN_DIR/compatibility.dll" | awk 'NR==5{print $2}')"
if [ "$CB_BYTES" != "b30100" ]; then
	echo "error: Compatibility_cb descriptor bytes are '$CB_BYTES', expected 'b30100'" >&2
	echo "       a toolchain change altered the naked stub; see CALLBACK DESCRIPTOR" >&2
	echo "       CONSTRAINT in Compatibility/shim.c" >&2
	exit 1
fi
echo "verified: Compatibility_cb descriptor bytes b3 01 00"
echo "built: $BIN_DIR/compatibility.dll + $BIN_DIR/compatibility.exe"
