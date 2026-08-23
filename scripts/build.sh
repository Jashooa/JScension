#!/usr/bin/env bash
# Build compatibility.dll (the shim) + compatibility.exe (the injector)
# into the Solution bin/ folder (gitignored build output).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/script_helpers.sh"
load_config

for required_value in \
    SOLUTION_DIR COMPAT_BIN_DIR COMPAT_DLL_NAME COMPAT_EXE_NAME \
    MINGW_CC MINGW_OBJDUMP; do
    require_config_value "$required_value"
done
require_executable "$MINGW_CC"
require_executable "$MINGW_OBJDUMP"
require_command awk
require_command install

SHIM_SOURCES=(
    "$SOLUTION_DIR/Compatibility/shim.c"
    "$SOLUTION_DIR/Compatibility/client_layout.c"
    "$SOLUTION_DIR/Compatibility/client_api.c"
    "$SOLUTION_DIR/Compatibility/lua_bridge.c"
    "$SOLUTION_DIR/Compatibility/secure_executor.c"
    "$SOLUTION_DIR/Compatibility/trust_manifest.c"
    "$SOLUTION_DIR/Compatibility/command_dispatch.c"
    "$SOLUTION_DIR/Compatibility/command_parser.c"
    "$SOLUTION_DIR/Compatibility/target_selector.c"
    "$SOLUTION_DIR/Compatibility/window_lifecycle.c"
    "$SOLUTION_DIR/Compatibility/compatibility.def"
)

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/accessibility-build.XXXXXX")"
cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

DLL_PATH="$BUILD_DIR/$COMPAT_DLL_NAME"
EXE_PATH="$BUILD_DIR/$COMPAT_EXE_NAME"

"$MINGW_CC" -O2 -shared -o "$DLL_PATH" \
    "${SHIM_SOURCES[@]}" \
    -static-libgcc -Wl,--exclude-all-symbols
"$MINGW_CC" -O2 -o "$EXE_PATH" \
    "$SOLUTION_DIR/Compatibility/injector.c" \
    -static-libgcc

# The registered callback's descriptor bytes (entry+0x4d..0x4f) must read
# b3 01 00: the game's call wrapper consumes them as per-function metadata,
# and a compiler change that shifts the naked stub breaks the arg machinery
# silently. Fail the build here instead of crashing in-game.
CB_VMA="$(LC_ALL=C "$MINGW_OBJDUMP" -d "$DLL_PATH" |
    awk '/<_Compatibility_cb>:/{vma=$1} END{print vma}')"
if [[ -z "$CB_VMA" ]]; then
    echo "error: Compatibility_cb symbol not found; cannot verify descriptor bytes" >&2
    exit 1
fi
CB_BYTES="$(LC_ALL=C "$MINGW_OBJDUMP" -s \
    --start-address="0x$(printf '%x' $((0x$CB_VMA + 0x4d)))" \
    --stop-address="0x$(printf '%x' $((0x$CB_VMA + 0x50)))" \
    "$DLL_PATH" | awk 'NF>=2 && $1 ~ /^[0-9a-f]+$/ {print $2; exit}')"
if [[ "$CB_BYTES" != "b30100" ]]; then
    echo "error: Compatibility_cb descriptor bytes are '$CB_BYTES', expected 'b30100'" >&2
    echo "       a toolchain change altered the naked stub; see CALLBACK DESCRIPTOR" >&2
    echo "       CONSTRAINT in Compatibility/shim.c" >&2
    exit 1
fi

mkdir -p "$COMPAT_BIN_DIR"
install -m 755 "$DLL_PATH" "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME"
install -m 755 "$EXE_PATH" "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME"
echo "verified: Compatibility_cb descriptor bytes b3 01 00"
echo "built: $COMPAT_BIN_DIR/$COMPAT_DLL_NAME + $COMPAT_BIN_DIR/$COMPAT_EXE_NAME"
