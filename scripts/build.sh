#!/bin/bash
# Builds ISLe8 into build/<Configuration>/ISLe8.app, signed with your Xcode Personal Team.
# Usage: scripts/build.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."

configuration=${1:-Debug}
# Debug builds only for this Mac; Release builds for both Apple silicon and Intel.
arch_flags=()
[ "$configuration" = Debug ] && arch_flags=(-arch "$(uname -m)")

xcodebuild \
    ${arch_flags[@]+"${arch_flags[@]}"} \
    -project ISLe8.xcodeproj \
    -target ISLe8 \
    -configuration "$configuration" \
    -allowProvisioningUpdates \
    -quiet \
    build

echo "build/$configuration/ISLe8.app"
