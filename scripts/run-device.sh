#!/bin/zsh
# Build, install, and relaunch the app on a paired physical iPhone.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="calendish-ios"
BUNDLE_ID="owenvey.calendish-ios"
DERIVED_DATA="$PROJECT_ROOT/.build/device"
DEVICE="${1:-${IPHONE_DEVICE:-Owen’s iPhone}}"

xcodebuild -project "$PROJECT_ROOT/calendish-ios.xcodeproj" \
  -scheme "$SCHEME" -configuration Debug \
  -destination "platform=iOS,name=$DEVICE" \
  -derivedDataPath "$DERIVED_DATA" -allowProvisioningUpdates build -quiet

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Calendish.app"
xcrun devicectl device install app --device "$DEVICE" "$APP" --timeout 60
xcrun devicectl device process launch --device "$DEVICE" \
  --terminate-existing "$BUNDLE_ID" --timeout 30
