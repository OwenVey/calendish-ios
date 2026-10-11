#!/bin/zsh
# Format Swift sources with SwiftFormat (.swiftformat). Pass --lint to check without writing.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/swift-tool.sh swiftformat . "$@"
