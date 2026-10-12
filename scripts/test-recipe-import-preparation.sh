#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE_ID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v]; print(d[0]["udid"] if d else "")')"
[[ -n "$DEVICE_ID" ]] || { echo "No booted simulator." >&2; exit 1; }
python3 scripts/support/household-test-project.py tests/Recipes/RecipeImportPreparationTests.swift recipe-import-preparation RecipeImportPreparationWorkflow owenvey.calendish-recipe-import-preparation
LOG="$PWD/.build/recipe-import-preparation/build.log"
xcodebuild -project .build/recipe-import-preparation/Workflow.xcodeproj -scheme RecipeImportPreparationWorkflow \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath .build/sim \
  -onlyUsePackageVersionsFromResolvedFile build -quiet > "$LOG" 2>&1 || { tail -60 "$LOG"; exit 1; }
xcrun simctl terminate "$DEVICE_ID" owenvey.calendish-recipe-import-preparation 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" .build/sim/Build/Products/Debug-iphonesimulator/RecipeImportPreparationWorkflow.app
CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" owenvey.calendish-recipe-import-preparation data)"
python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1], "Documents/result.txt").unlink(missing_ok=True)' "$CONTAINER"
xcrun simctl launch "$DEVICE_ID" owenvey.calendish-recipe-import-preparation
python3 - "$CONTAINER" <<'PY'
import pathlib, sys, time
result = pathlib.Path(sys.argv[1]) / 'Documents/result.txt'
for _ in range(45):
    if result.exists():
        message = result.read_text()
        print('Recipe import preparation tests: ' + message)
        sys.exit(0 if message == 'PASS' else 1)
    time.sleep(1)
sys.exit('Recipe import preparation tests timed out')
PY
