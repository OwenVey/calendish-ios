#!/bin/zsh
# Run hands-free cook mode workflow tests: a controlled speech boundary drives the real
# cooking session and timers inside a simulator harness built from production sources.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE_ID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v]; print(d[0]["udid"] if d else "")')"
[[ -n "$DEVICE_ID" ]] || { echo "No booted simulator." >&2; exit 1; }
BUNDLE_ID=owenvey.calendish-hands-free-workflow
python3 scripts/support/household-test-project.py tests/Cooking/HandsFreeCookingWorkflowTests.swift hands-free-workflow HandsFreeWorkflow "$BUNDLE_ID"
LOG="$PWD/.build/hands-free-workflow/build.log"
xcodebuild -project .build/hands-free-workflow/Workflow.xcodeproj -scheme HandsFreeWorkflow \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath .build/sim \
  -onlyUsePackageVersionsFromResolvedFile build -quiet > "$LOG" 2>&1 || { tail -60 "$LOG"; exit 1; }
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" .build/sim/Build/Products/Debug-iphonesimulator/HandsFreeWorkflow.app
CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"
python3 -c 'import pathlib,sys; pathlib.Path(sys.argv[1], "Documents/result.txt").unlink(missing_ok=True)' "$CONTAINER"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
python3 - "$CONTAINER" <<'PY'
import pathlib, sys, time
result = pathlib.Path(sys.argv[1]) / 'Documents/result.txt'
for _ in range(45):
    if result.exists():
        message = result.read_text()
        print('Hands-free cooking workflow tests: ' + message)
        sys.exit(0 if message.startswith('PASS') else 1)
    time.sleep(1)
sys.exit('Hands-free cooking workflow tests timed out')
PY
