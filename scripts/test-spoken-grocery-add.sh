#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES calendish-ios/Features/Groceries/GrocerySyncState.swift \
  $GROCERY_TRANSPORT_SOURCES calendish-ios/Features/Groceries/SpokenGroceryAdd.swift \
  tests/Groceries/SpokenGroceryAddTests.swift -o "$TEST_DIR/spoken-grocery-add-tests"
"$TEST_DIR/spoken-grocery-add-tests"
