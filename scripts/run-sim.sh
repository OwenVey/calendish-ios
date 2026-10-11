#!/bin/zsh
# Build the app and relaunch it in the booted iOS simulator.
set -euo pipefail

SCHEME="calendish-ios"
BUNDLE_ID="owenvey.calendish-ios"
DERIVED_DATA="$(cd "$(dirname "$0")/.." && pwd)/.build/sim"

DEVICE_ID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v]; print(d[0]["udid"] if d else "")')"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No booted simulator. Open Simulator.app and boot a device first." >&2
  exit 1
fi

xcodebuild -scheme "$SCHEME" -destination "id=$DEVICE_ID" -derivedDataPath "$DERIVED_DATA" build -quiet

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Calendish.app"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
