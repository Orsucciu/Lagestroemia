#!/bin/bash
# Build the extension for Chrome/Edge or Firefox.
#
# Usage:
#   ./build.sh chrome    # creates extension-chrome/ ready to load
#   ./build.sh firefox   # creates extension-firefox/ ready to load
#   ./build.sh all       # creates both

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$(dirname "$SCRIPT_DIR")/extension"

build_chrome() {
    local OUT="$SCRIPT_DIR/extension-chrome"
    rm -rf "$OUT"
    mkdir -p "$OUT"

    # Copy all files (excluding tests, __pycache__, .pyc).
    cp "$EXT_DIR"/background.js "$OUT"/
    cp "$EXT_DIR"/content.js "$OUT"/
    cp "$EXT_DIR"/sidepanel.html "$OUT"/
    cp "$EXT_DIR"/sidepanel.js "$OUT"/
    cp "$EXT_DIR"/native_host.py "$OUT"/
    cp -r "$EXT_DIR"/icons "$OUT"/

    # Use the Chrome manifest (with sidePanel).
    cp "$EXT_DIR"/manifest.json "$OUT"/manifest.json

    echo "✅ Chrome/Edge extension built at: $OUT"
    echo "   Load it: chrome://extensions → Developer mode → Load unpacked → $OUT"
}

build_firefox() {
    local OUT="$SCRIPT_DIR/extension-firefox"
    rm -rf "$OUT"
    mkdir -p "$OUT"

    # Copy all files (excluding tests, __pycache__, .pyc).
    cp "$EXT_DIR"/background.js "$OUT"/
    cp "$EXT_DIR"/content.js "$OUT"/
    cp "$EXT_DIR"/sidepanel.html "$OUT"/
    cp "$EXT_DIR"/sidepanel.js "$OUT"/
    cp "$EXT_DIR"/native_host.py "$OUT"/
    cp -r "$EXT_DIR"/icons "$OUT"/

    # Use the Firefox manifest (with sidebar_action).
    cp "$EXT_DIR"/manifest.firefox.json "$OUT"/manifest.json

    echo "✅ Firefox extension built at: $OUT"
    echo "   Load it: about:debugging → This Firefox → Load Temporary Add-on → $OUT/manifest.json"
}

case "${1:-all}" in
    chrome)
        build_chrome
        ;;
    firefox)
        build_firefox
        ;;
    all)
        build_chrome
        build_firefox
        ;;
    *)
        echo "Usage: $0 {chrome|firefox|all}"
        exit 1
        ;;
esac
