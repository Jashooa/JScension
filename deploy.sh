#!/usr/bin/env bash
# Deploy both components: the Accessibility addon and the Compatibility
# shim. Run this after any change to either component.
set -euo pipefail

SOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SOLUTION_DIR/Accessibility/deploy.sh"
"$SOLUTION_DIR/Compatibility/deploy.sh"

echo "all components deployed"
