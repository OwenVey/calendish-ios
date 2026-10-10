#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES tests/IngredientScalingTests.swift -o "$TEST_DIR/ingredient-scaling-tests"
swiftc -parse-as-library $MODEL_SOURCES tests/UnitConversionTests.swift -o "$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/ingredient-scaling-tests"
swiftc -parse-as-library $MODEL_SOURCES tests/UnitConversionTests.swift -o "$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/unit-conversion-tests"
swiftc -parse-as-library calendish-ios/IngredientParser.swift tests/IngredientParserTests.swift -o "$TEST_DIR/ingredient-parser-tests"
"$TEST_DIR/ingredient-parser-tests"
IMPORTERS=($MODEL_SOURCES $COOKED_HISTORY_SOURCES calendish-ios/RecipeStats.swift $PREFERENCE_SOURCES $RECIPE_LINK_IMPORTER_SOURCES calendish-ios/SocialPost.swift calendish-ios/RecipeTextImporter.swift Shared/RecipeImport.swift)
swiftc -parse-as-library -enable-bare-slash-regex $IMPORTERS tests/SocialRecipeImportTests.swift -o "$TEST_DIR/social-recipe-import-tests"
"$TEST_DIR/social-recipe-import-tests"
swiftc -enable-bare-slash-regex $IMPORTERS tests/RecipeLinkImporterTests.swift -o "$TEST_DIR/recipe-import-tests"
"$TEST_DIR/recipe-import-tests" "$@"
