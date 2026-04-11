#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

bash -n \
  "$ROOT/scripts/shared/opencode-build" \
  "$ROOT/scripts/shared/opencode-bootstrap" \
  "$ROOT/scripts/shared/opencode-start" \
  "$ROOT/scripts/shared/opencode-open" \
  "$ROOT/scripts/shared/opencode-shell" \
  "$ROOT/scripts/shared/opencode-status" \
  "$ROOT/scripts/shared/opencode-stop" \
  "$ROOT/scripts/shared/opencode-remove" \
  "$ROOT/scripts/shared/opencode-logs" \
  "$ROOT/lib/shell/common.sh" \
  "$ROOT/tests/shared/test-args.sh" \
  "$ROOT/tests/shared/test-layout.sh" \
  "$ROOT/tests/shared/test-common.sh" \
  "$ROOT/tests/shared/test-runtime.sh"

"$ROOT/tests/shared/test-args.sh"
"$ROOT/tests/shared/test-layout.sh"
"$ROOT/tests/shared/test-common.sh"
"$ROOT/tests/shared/test-runtime.sh"

echo "All checks passed"
