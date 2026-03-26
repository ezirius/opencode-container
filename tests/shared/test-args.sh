#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_rejects() {
  local script_path="$1" expected="$2"
  shift 2
  local err="$TMPDIR/$(basename "$script_path").err"
  if "$script_path" "$@" >/dev/null 2> "$err"; then
    printf 'assertion failed: %s should reject invalid arguments\n' "$script_path" >&2
    exit 1
  fi
  assert_contains "$err" "$expected" "script reports invalid usage clearly"
}

assert_rejects "$ROOT/scripts/shared/opencode-build" 'takes no arguments' unexpected
assert_rejects "$ROOT/scripts/shared/opencode-upgrade" 'takes no arguments' unexpected
assert_rejects "$ROOT/scripts/shared/opencode-start" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/opencode-start" 'requires exactly 1 argument' one two
assert_rejects "$ROOT/scripts/shared/opencode-open" 'requires at least 1 argument'
assert_rejects "$ROOT/scripts/shared/opencode-shell" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/opencode-stop" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/opencode-remove" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/opencode-logs" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/bootstrap" 'requires at least 1 argument'

echo "Argument contract checks passed"
