#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES tests/RecipeObservationTests.swift -o "$TEST_DIR/recipe-observation-tests"
"$TEST_DIR/recipe-observation-tests"
