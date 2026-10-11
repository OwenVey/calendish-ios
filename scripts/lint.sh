#!/bin/zsh
# Check formatting with SwiftFormat, then lint with SwiftLint (.swiftlint.yml).
# Pass --fix to apply SwiftFormat and SwiftLint autocorrections first.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--fix" ]]; then
  ./scripts/swift-tool.sh swiftformat . --quiet
  ./scripts/swift-tool.sh swiftlint lint --fix --quiet
fi
./scripts/swift-tool.sh swiftformat --lint .
./scripts/swift-tool.sh swiftlint lint --quiet
