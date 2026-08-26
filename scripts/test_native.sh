#!/usr/bin/env bash
# Build and run host-side contracts for portable Compatibility modules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/script_helpers.sh"
require_executable gcc

TEST_BINARY="$SOLUTION_DIR/bin/command_parser_test"

mkdir -p "$SOLUTION_DIR/bin"
gcc -std=c11 -Wall -Wextra -Werror -O2 \
    -I"$SOLUTION_DIR/Compatibility" \
    "$SOLUTION_DIR/Compatibility/tests/command_parser_test.c" \
    "$SOLUTION_DIR/Compatibility/command_parser.c" \
    "$SOLUTION_DIR/Compatibility/target_selector.c" \
    "$SOLUTION_DIR/Compatibility/los_geometry.c" \
    -lm -o "$TEST_BINARY"
"$TEST_BINARY"
