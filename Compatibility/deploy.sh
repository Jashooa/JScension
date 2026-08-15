#!/usr/bin/env bash
# Build the Compatibility shim + injector into Solution/bin, then deploy
# them to the Wine prefix's C:\local. The launcher does not manage that
# folder, so it survives repairs.
set -euo pipefail

COMPAT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMPAT_DIR/../config.sh"

echo "building..."
( cd "$COMPAT_DIR" && ./build.sh )

mkdir -p "$COMPAT_DEPLOY_DIR"
install -m 755 "$COMPAT_BIN_DIR/$COMPAT_DLL_NAME" "$COMPAT_BIN_DIR/$COMPAT_EXE_NAME" "$COMPAT_DEPLOY_DIR/"
echo "deployed:"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_DLL_NAME"
echo "  $COMPAT_DEPLOY_DIR/$COMPAT_EXE_NAME"
