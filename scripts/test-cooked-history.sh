#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library calendish-ios/Models.swift calendish-ios/CookedHistory.swift tests/CookedHistoryTests.swift -o "$TEST_DIR/cooked-history-tests"
"$TEST_DIR/cooked-history-tests"
