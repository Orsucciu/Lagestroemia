#!/usr/bin/env bash
# Register the Lagestroemia native messaging host on Linux/macOS.
#
# This tells Chrome/Firefox where to find native_host.py so the
# extension can communicate with the local HTTP server.
#
# Usage: ./install-native.sh [chrome|firefox|chromium|edge]
# Default: chrome

set -e

EXT_DIR="$(cd "$(dirname "$0")/.." && pwd)/extension"
NATIVE_HOST_PATH="$EXT_DIR/native_host.py"
WRAPPER_SCRIPT="$EXT_DIR/native_host_wrapper.sh"

# Create a wrapper script (needed because Chrome doesn't run .py directly).
cat > "$WRAPPER_SCRIPT" << EOF
#!/usr/bin/env bash
exec python3 "$NATIVE_HOST_PATH"
EOF
chmod +x "$WRAPPER_SCRIPT"

# The native messaging host manifest.
MANIFEST=$(cat << EOF
{
  "name": "lagestroemia",
  "description": "Lagestroemia local proxy server for chat.z.ai",
  "path": "$WRAPPER_SCRIPT",
  "type": "stdio",
  "allowed_extensions": [
    "lagestroemia@orsucciu.github.io"
  ]
}
EOF
)

# Determine the browser.
BROWSER="${1:-chrome}"

case "$BROWSER" in
  chrome|chromium)
    MANIFEST_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
    [ "$BROWSER" = "chromium" ] && MANIFEST_DIR="$HOME/.config/chromium/NativeMessagingHosts"
    ;;
  edge)
    MANIFEST_DIR="$HOME/.config/microsoft-edge/NativeMessagingHosts"
    ;;
  firefox)
    MANIFEST_DIR="$HOME/.mozilla/native-messaging-hosts"
    ;;
  *)
    echo "Usage: $0 [chrome|firefox|chromium|edge]"
    exit 1
    ;;
esac

mkdir -p "$MANIFEST_DIR"
MANIFEST_FILE="$MANIFEST_DIR/lagestroemia.json"
echo "$MANIFEST" > "$MANIFEST_FILE"

echo "✅ Native messaging host registered for $BROWSER"
echo "   Manifest: $MANIFEST_FILE"
echo "   Script:   $WRAPPER_SCRIPT"
echo ""
echo "The local HTTP server will start automatically when the extension"
echo "connects. It listens on http://127.0.0.1:8081"
echo ""
echo "Test with:"
echo "  curl http://127.0.0.1:8081/health"
echo "  curl http://127.0.0.1:8081/v1/models"
