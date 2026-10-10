#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/support/sources.zsh
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library $MODEL_SOURCES $COOKED_HISTORY_SOURCES tests/CookedHistoryTests.swift -o "$TEST_DIR/cooked-history-tests"
"$TEST_DIR/cooked-history-tests"
