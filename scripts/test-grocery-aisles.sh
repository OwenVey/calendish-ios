#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish/Features/Groceries/GroceryAisle.swift tests/Groceries/GroceryAisleTests.swift -o "$TEST_DIR/grocery-aisle-tests"
"$TEST_DIR/grocery-aisle-tests"
