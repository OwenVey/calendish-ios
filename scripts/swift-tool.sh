#!/bin/zsh
# Run a tool pinned in BuildTools/Package.swift: ./scripts/swift-tool.sh swiftlint lint
# Builds it on first use (SwiftLint takes a few minutes) and again whenever the pins change.
set -euo pipefail

TOOL="$1"; shift
PACKAGE="$(cd "$(dirname "$0")/.." && pwd)/BuildTools"
BIN="$PACKAGE/.build/release/$TOOL"

if [[ ! -x "$BIN" || "$PACKAGE/Package.resolved" -nt "$BIN" || "$PACKAGE/Package.swift" -nt "$BIN" ]]; then
  echo "Building $TOOL from BuildTools (first run takes a while)..." >&2
  swift build -c release --package-path "$PACKAGE" --product "$TOOL" >&2
  touch "$BIN"
fi

exec "$BIN" "$@"
