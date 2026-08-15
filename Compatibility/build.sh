#!/bin/sh
# Build compatibility.dll (the shim) + compatibility.exe (the injector)
# into the Solution bin/ folder (gitignored build output).
# Requires i686-w64-mingw32-gcc (mingw-w64).
set -e

# Compatibility/../bin resolves to Solution/bin regardless of cwd.
COMPAT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$COMPAT_DIR/.." && pwd)/bin"
cd "$COMPAT_DIR"

mkdir -p "$BIN_DIR"
i686-w64-mingw32-gcc -O2 -shared -o "$BIN_DIR/compatibility.dll" shim.c compatibility.def \
    -static-libgcc -Wl,--exclude-all-symbols
i686-w64-mingw32-gcc -O2 -o "$BIN_DIR/compatibility.exe" injector.c -static-libgcc
echo "built: $BIN_DIR/compatibility.dll + $BIN_DIR/compatibility.exe"
