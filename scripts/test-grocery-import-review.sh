#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES calendish-ios/IngredientParser.swift \
  $GROCERY_IMPORT_REVIEW_SOURCES $GROCERY_MERGE_SOURCES tests/GroceryImportReviewTests.swift \
  -o "$TEST_DIR/grocery-import-review-tests"
"$TEST_DIR/grocery-import-review-tests"
