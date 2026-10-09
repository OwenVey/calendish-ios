#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift calendish-ios/CookedHistory.swift calendish-ios/RecipeStats.swift calendish-ios/Preferences.swift tests/RecipeStatsTests.swift -o "$TEST_DIR/recipe-stats-tests"
"$TEST_DIR/recipe-stats-tests"
