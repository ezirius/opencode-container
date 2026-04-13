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

assert_rejects "$ROOT/scripts/shared/opencode-build" '<production|test> [upstream]'
assert_rejects "$ROOT/scripts/shared/opencode-start" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-open" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-shell" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-stop" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-status" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" container
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" image
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" wrong
assert_rejects "$ROOT/scripts/shared/opencode-logs" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-bootstrap" '<workspace>'
assert_rejects "$ROOT/scripts/shared/opencode-start" '<workspace> <production|test> <upstream>' demo production
assert_rejects "$ROOT/scripts/shared/opencode-open" '<workspace> <production|test> <upstream>' demo production
assert_rejects "$ROOT/scripts/shared/opencode-shell" '<workspace> <production|test> <upstream>' demo production

echo "Argument contract checks passed"
