#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift tests/RecipeObservationTests.swift -o "$TEST_DIR/recipe-observation-tests"
"$TEST_DIR/recipe-observation-tests"
