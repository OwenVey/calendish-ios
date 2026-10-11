#!/bin/zsh
# Point git at the repo's hooks in .githooks (run once per clone).
set -euo pipefail
cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
echo "Git hooks installed from .githooks."
