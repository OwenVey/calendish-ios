#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift tests/IngredientScalingTests.swift -o "$TEST_DIR/ingredient-scaling-tests"
swiftc -parse-as-library calendish-ios/Models.swift tests/UnitConversionTests.swift -o "$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/ingredient-scaling-tests"
swiftc -parse-as-library calendish-ios/Models.swift tests/UnitConversionTests.swift -o "$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/unit-conversion-tests"
swiftc -parse-as-library calendish-ios/IngredientParser.swift tests/IngredientParserTests.swift -o "$TEST_DIR/ingredient-parser-tests"
"$TEST_DIR/ingredient-parser-tests"
swiftc -enable-bare-slash-regex calendish-ios/Models.swift calendish-ios/Preferences.swift calendish-ios/RecipeLinkImporter.swift tests/RecipeLinkImporterTests.swift -o "$TEST_DIR/recipe-import-tests"
"$TEST_DIR/recipe-import-tests" "$@"
