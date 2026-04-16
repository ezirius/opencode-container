#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

grep -q '^    git \\' "$ROOT/config/containers/Containerfile.wrapper"

echo "Image package checks passed"
