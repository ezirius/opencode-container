#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -f "$ROOT/README.md"
test -f "$ROOT/config/container/Dockerfile"
test -f "$ROOT/lib/opencode/common.sh"
test -f "$ROOT/scripts/opencode-build"
echo "Layout checks passed"
