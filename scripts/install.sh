#!/bin/bash
# Builds a Release ISLe8, puts it in /Applications and starts it.
# A fixed place matters: Full Disk Access and other privacy lists point at the app there.
# Usage: scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh Release > /dev/null
built="build/Release/ISLe8.app"
target="/Applications/ISLe8.app"

# Quit every running copy, from /Applications or from a build folder.
if pgrep -x ISLe8 > /dev/null; then
    osascript -e 'tell application id "com.lrxe8.isle8" to quit' > /dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x ISLe8 > /dev/null || break
        sleep 0.3
    done
    pkill -x ISLe8 || true
fi

# ditto keeps the code signature intact; replacing in place keeps privacy grants tied to it.
rm -rf "$target"
ditto "$built" "$target"

# The `isle8` command for scripts and agent hooks: a link to the app's own binary.
mkdir -p "$HOME/.local/bin"
ln -sf "$target/Contents/MacOS/ISLe8" "$HOME/.local/bin/isle8"

open "$target"
echo "$target"
