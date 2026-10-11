#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES $COOKED_HISTORY_SOURCES calendish/Features/Recipes/RecipeStats.swift $PREFERENCE_SOURCES tests/Recipes/RecipeStatsTests.swift -o "$TEST_DIR/recipe-stats-tests"
"$TEST_DIR/recipe-stats-tests"
