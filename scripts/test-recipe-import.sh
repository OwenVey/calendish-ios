#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc calendish-ios/Models.swift calendish-ios/RecipeLinkImporter.swift tests/RecipeLinkImporterTests.swift -o "$TEST_DIR/recipe-import-tests"
"$TEST_DIR/recipe-import-tests" "$@"
