#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift calendish-ios/GrocerySyncState.swift tests/GrocerySyncTests.swift -o "$TEST_DIR/grocery-sync-tests"
"$TEST_DIR/grocery-sync-tests"
swiftc -parse-as-library calendish-ios/Models.swift calendish-ios/GrocerySyncState.swift \
  calendish-ios/GrocerySync.swift calendish-ios/GroceryMerge.swift calendish-ios/IngredientParser.swift tests/GrocerySyncWorkflowTests.swift -o "$TEST_DIR/grocery-sync-workflow-tests"
"$TEST_DIR/grocery-sync-workflow-tests"
