#!/usr/bin/env bash

set -euo pipefail

# This test runs the OpenCode shell test suite sequentially.

# This finds the repo root so each script runs from one stable path.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# These tests run one at a time because some of them rewrite shared config.
bash "$ROOT/tests/shared/opencode/test-opencode-layout.sh"
bash "$ROOT/tests/shared/opencode/test-opencode-build.sh"
bash "$ROOT/tests/shared/opencode/test-opencode-run.sh"
bash "$ROOT/tests/shared/opencode/test-opencode-shell.sh"

echo "All OpenCode wrapper checks passed"
