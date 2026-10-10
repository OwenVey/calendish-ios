#!/bin/zsh
# Run the ingredient-tap regression against the installed app in the booted simulator.
# Fixture: Sheet pan lemon chicken, whose first step mentions potatoes.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$PWD/.build/cook-mode-ui"
DEVICE_ID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; devices=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["state"] == "Booted"]; print(devices[0]["udid"] if devices else "")')"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No booted iOS simulator." >&2
  exit 1
fi
mkdir -p "$TEST_DIR/CookModeUITests.xcodeproj/xcshareddata/xcschemes"
cp tests/Cooking/CookModeUITests.swift "$TEST_DIR/CookModeUITests.swift"
cat > "$TEST_DIR/CookModeUITests.xcodeproj/project.pbxproj" <<'EOF'
// !$*UTF8*$!
{
archiveVersion = 1; classes = {}; objectVersion = 56;
objects = {
A00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; mainGroup = A00000000000000000000003; productRefGroup = A00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000005); };
A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000006); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000007, A00000000000000000000004); sourceTree = "<group>"; };
A00000000000000000000004 = {isa = PBXGroup; children = (A00000000000000000000008); name = Products; sourceTree = "<group>"; };
A00000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000009; buildPhases = (A0000000000000000000000A); buildRules = (); dependencies = (); name = CookModeUITests; productName = CookModeUITests; productReference = A00000000000000000000008; productType = "com.apple.product-type.bundle.ui-testing"; };
A00000000000000000000006 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphonesimulator; IPHONEOS_DEPLOYMENT_TARGET = 26.0;}; name = Debug; };
A00000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CookModeUITests.swift; sourceTree = "<group>"; };
A00000000000000000000008 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CookModeUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
A00000000000000000000009 = {isa = XCConfigurationList; buildConfigurations = (A0000000000000000000000B); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
A0000000000000000000000A = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000000C); runOnlyForDeploymentPostprocessing = 0; };
A0000000000000000000000B = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGNING_ALLOWED = NO; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = "owenvey.calendish-ios.cookmode-uitests"; PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2";}; name = Debug; };
A0000000000000000000000C = {isa = PBXBuildFile; fileRef = A00000000000000000000007; };
}; rootObject = A00000000000000000000001;
}
EOF
cat > "$TEST_DIR/CookModeUITests.xcodeproj/xcshareddata/xcschemes/CookModeUITests.xcscheme" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="CookModeUITests.xctest" BlueprintName="CookModeUITests" ReferencedContainer="container:CookModeUITests.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="CookModeUITests.xctest" BlueprintName="CookModeUITests" ReferencedContainer="container:CookModeUITests.xcodeproj"/></TestableReference></Testables></TestAction>
</Scheme>
EOF
xcodebuild test -project "$TEST_DIR/CookModeUITests.xcodeproj" -scheme CookModeUITests \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$TEST_DIR/derived" \
  -parallel-testing-enabled NO > "$TEST_DIR/test.log" 2>&1 || {
    tail -60 "$TEST_DIR/test.log"
    exit 1
  }
rg -a 'Test Case.*(passed|failed)|Executed|\*\* TEST' "$TEST_DIR/test.log"
