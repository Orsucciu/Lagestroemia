#!/usr/bin/env bash
# Register the Lagestroemia native messaging host.
#
# Usage:
#   ./install-native.sh chrome   [extension_id]
#   ./install-native.sh firefox
#   ./install-native.sh edge     [extension_id]
#
# For Chrome/Edge, you need the extension ID (visible on the
# extensions page after loading the unpacked extension).
# For Firefox, the extension ID is in the manifest (lagestroemia@orsucciu.github.io).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$(dirname "$SCRIPT_DIR")/extension"
NATIVE_HOST_PATH="$EXT_DIR/native_host.py"
WRAPPER_SCRIPT="$EXT_DIR/native_host_wrapper.sh"

# Create a wrapper script.
# The wrapper doesn't set LAGESTROEMIA_HOST — native_host.py defaults
# to 0.0.0.0 (all IPv4 interfaces), which works for WSL2 + same-machine
# use out of the box. Auth is disabled by default too.
#
# To restrict to loopback only, edit the wrapper to add:
#   export LAGESTROEMIA_HOST=127.0.0.1
cat > "$WRAPPER_SCRIPT" << EOF
#!/usr/bin/env bash
# Lagestroemia native host wrapper.
#
# Defaults: binds to 0.0.0.0:8081, no auth. Works for WSL2 and
# same-machine use. To restrict to loopback only, uncomment:
# export LAGESTROEMIA_HOST=127.0.0.1
exec python3 "$NATIVE_HOST_PATH"
EOF
chmod +x "$WRAPPER_SCRIPT"

# Determine the browser.
BROWSER="${1:-chrome}"
EXTENSION_ID="${2:-}"

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
    EXTENSION_ID="lagestroemia@orsucciu.github.io"
    ;;
  *)
    echo "Usage: $0 [chrome|firefox|chromium|edge] [extension_id]"
    exit 1
    ;;
esac

# For Chrome/Edge, ask for the extension ID if not provided.
if [ "$BROWSER" != "firefox" ] && [ -z "$EXTENSION_ID" ]; then
  echo ""
  echo "To find the extension ID:"
  echo "  1. Open chrome://extensions (or edge://extensions)"
  echo "  2. Enable Developer mode"
  echo "  3. Load the extension/ directory"
  echo "  4. Copy the ID (a 32-char string like abcdefghijklmnopqrstuvwxyz123456)"
  echo ""
  read -p "Paste the extension ID: " EXTENSION_ID
fi

# Build the native messaging host manifest.
if [ "$BROWSER" = "firefox" ]; then
  MANIFEST=$(cat << EOF
{
  "name": "lagestroemia",
  "description": "Lagestroemia local proxy server for chat.z.ai",
  "path": "$WRAPPER_SCRIPT",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
EOF
)
else
  MANIFEST=$(cat << EOF
{
  "name": "lagestroemia",
  "description": "Lagestroemia local proxy server for chat.z.ai",
  "path": "$WRAPPER_SCRIPT",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
EOF
)
fi

mkdir -p "$MANIFEST_DIR"
MANIFEST_FILE="$MANIFEST_DIR/lagestroemia.json"
echo "$MANIFEST" > "$MANIFEST_FILE"

echo ""
echo "✅ Native messaging host registered for $BROWSER"
echo "   Manifest: $MANIFEST_FILE"
echo "   Script:   $WRAPPER_SCRIPT"
echo "   Extension ID: $EXTENSION_ID"
echo ""
echo "The local HTTP server will start automatically when the extension"
echo "connects. It listens on http://0.0.0.0:8081 (all IPv4 interfaces)"
echo "so both WSL2 and same-machine callers work out of the box."
echo ""
echo "After reloading the extension, check:"
echo "  curl http://127.0.0.1:8081/health"
echo ""
echo "You should see a 🌺 badge on chat.z.ai saying 'Server on :8081'"
