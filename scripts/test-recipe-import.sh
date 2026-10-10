#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES tests/Recipes/IngredientScalingTests.swift -o "$TEST_DIR/ingredient-scaling-tests"
swiftc -parse-as-library $MODEL_SOURCES tests/Recipes/UnitConversionTests.swift -o "$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/ingredient-scaling-tests"
swiftc -parse-as-library $MODEL_SOURCES tests/Recipes/UnitConversionTests.swift -o "$TEST_DIR/unit-conversion-tests"
"$TEST_DIR/unit-conversion-tests"
swiftc -parse-as-library calendish-ios/Features/Recipes/IngredientParser.swift tests/Recipes/IngredientParserTests.swift -o "$TEST_DIR/ingredient-parser-tests"
"$TEST_DIR/ingredient-parser-tests"
IMPORTERS=($MODEL_SOURCES $COOKED_HISTORY_SOURCES calendish-ios/Features/Recipes/RecipeStats.swift $PREFERENCE_SOURCES $RECIPE_LINK_IMPORTER_SOURCES calendish-ios/Features/Recipes/Import/SocialPost.swift calendish-ios/Features/Recipes/Import/RecipeTextImporter.swift Shared/RecipeImport.swift)
swiftc -parse-as-library -enable-bare-slash-regex $IMPORTERS tests/Recipes/SocialRecipeImportTests.swift -o "$TEST_DIR/social-recipe-import-tests"
"$TEST_DIR/social-recipe-import-tests"
swiftc -enable-bare-slash-regex $IMPORTERS tests/Recipes/RecipeLinkImporterTests.swift -o "$TEST_DIR/recipe-import-tests"
"$TEST_DIR/recipe-import-tests" "$@"
