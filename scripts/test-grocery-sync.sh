#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES calendish-ios/GrocerySyncState.swift tests/GrocerySyncTests.swift -o "$TEST_DIR/grocery-sync-tests"
"$TEST_DIR/grocery-sync-tests"
swiftc -parse-as-library $MODEL_SOURCES calendish-ios/GrocerySyncState.swift \
  $GROCERY_SYNC_SOURCES $GROCERY_MERGE_SOURCES calendish-ios/IngredientParser.swift tests/GrocerySyncWorkflowTests.swift -o "$TEST_DIR/grocery-sync-workflow-tests"
"$TEST_DIR/grocery-sync-workflow-tests"
