#!/usr/bin/env bash
# Run the native Compatibility contracts and the addon Lua contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/script_helpers.sh"
require_executable lua5.1

"$SCRIPT_DIR/test_native.sh"
(
    cd "$SOLUTION_DIR/Accessibility"
    lua5.1 tests/run.lua
)
