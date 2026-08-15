#!/usr/bin/env bash
# Deploy both components: the Accessibility addon and the Compatibility
# shim. Run this after any change to either component.
set -euo pipefail

SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOLUTION_DIR/config.sh"

# Accessibility addon -> Interface/AddOns
"$SOLUTION_DIR/Accessibility/deploy.sh"

# Compatibility shim: build into Solution/bin, then install to C:\local
# (outside the launcher-managed folders, so it survives repairs).
( cd "$SOLUTION_DIR/Compatibility" && ./build.sh )
mkdir -p "$COMPAT_DEPLOY_DIR"
install -m 755 "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME" "$COMPAT_DEPLOY_DIR/"
echo "deployed:"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_DLL_NAME"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_EXE_NAME"

echo "all components deployed"
