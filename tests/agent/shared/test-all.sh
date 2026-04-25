#!/usr/bin/env bash

set -euo pipefail

# This test runs the OpenCode shell test suite sequentially.

# This finds the repo root so each script runs from one stable path.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# These tests run one at a time because some of them rewrite shared config.
bash "$ROOT/tests/agent/shared/test-opencode-layout.sh"
bash "$ROOT/tests/agent/shared/test-opencode-build.sh"
bash "$ROOT/tests/agent/shared/test-opencode-run.sh"
bash "$ROOT/tests/agent/shared/test-opencode-shell.sh"

echo "All OpenCode wrapper checks passed"
