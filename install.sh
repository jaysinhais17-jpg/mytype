#!/bin/bash
# Build MyType, install it to ~/Applications, and launch it.
set -euo pipefail
cd "$(dirname "$0")"
./bundle.sh
pkill -x MyType 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/MyType.app
cp -R build/MyType.app ~/Applications/MyType.app
open ~/Applications/MyType.app
echo "Installed to ~/Applications/MyType.app (also findable in Spotlight as 'MyType')"
