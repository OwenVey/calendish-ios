#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift calendish-ios/IngredientParser.swift \
  calendish-ios/GroceryImportReview.swift calendish-ios/GroceryMerge.swift tests/GroceryImportReviewTests.swift \
  -o "$TEST_DIR/grocery-import-review-tests"
"$TEST_DIR/grocery-import-review-tests"
