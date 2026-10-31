#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES calendish/Features/Groceries/GrocerySyncState.swift \
  $GROCERY_TRANSPORT_SOURCES calendish/Features/Groceries/SpokenGroceryAdd.swift \
  calendish/Features/Groceries/GroceryFood.swift calendish/Features/Recipes/IngredientParser.swift \
  tests/Groceries/SpokenGroceryAddTests.swift -o "$TEST_DIR/spoken-grocery-add-tests"
"$TEST_DIR/spoken-grocery-add-tests"
