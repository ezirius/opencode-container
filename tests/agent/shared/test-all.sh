#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

bash "$ROOT/tests/agent/shared/test-opencode-layout.sh"
bash "$ROOT/tests/agent/shared/test-opencode-build.sh"
bash "$ROOT/tests/agent/shared/test-opencode-run.sh"
bash "$ROOT/tests/agent/shared/test-opencode-shell.sh"

echo "All OpenCode wrapper checks passed"
