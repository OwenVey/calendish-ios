#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift tests/IngredientScalingTests.swift -o "$TEST_DIR/ingredient-scaling-tests"
"$TEST_DIR/ingredient-scaling-tests"
swiftc calendish-ios/Models.swift calendish-ios/RecipeLinkImporter.swift tests/RecipeLinkImporterTests.swift -o "$TEST_DIR/recipe-import-tests"
"$TEST_DIR/recipe-import-tests" "$@"
