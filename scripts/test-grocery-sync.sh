#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES calendish-ios/Features/Groceries/GrocerySyncState.swift tests/Groceries/GrocerySyncTests.swift -o "$TEST_DIR/grocery-sync-tests"
"$TEST_DIR/grocery-sync-tests"
swiftc -parse-as-library $MODEL_SOURCES calendish-ios/Features/Groceries/GrocerySyncState.swift \
  $GROCERY_SYNC_SOURCES $GROCERY_MERGE_SOURCES calendish-ios/Features/Recipes/IngredientParser.swift tests/Groceries/GrocerySyncWorkflowTests.swift -o "$TEST_DIR/grocery-sync-workflow-tests"
"$TEST_DIR/grocery-sync-workflow-tests"
