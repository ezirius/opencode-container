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

BUILD_HELP="$($ROOT/scripts/shared/opencode-build --help 2>&1)"
[[ "$BUILD_HELP" == *'Description:'* ]]
[[ "$BUILD_HELP" == *'Accepted [upstream] values:'* ]]

BOOTSTRAP_HELP="$($ROOT/scripts/shared/opencode-bootstrap --help 2>&1)"
[[ "$BOOTSTRAP_HELP" == *'Behaviour:'* ]]
[[ "$BOOTSTRAP_HELP" == *'Examples:'* ]]

START_HELP="$($ROOT/scripts/shared/opencode-start --help 2>&1)"
[[ "$START_HELP" == *'Notes:'* ]]
[[ "$START_HELP" == *'use `--`'* ]]

OPEN_HELP="$($ROOT/scripts/shared/opencode-open --help 2>&1)"
[[ "$OPEN_HELP" == *'Description:'* ]]
[[ "$OPEN_HELP" == *'use `--`'* ]]

SHELL_HELP="$($ROOT/scripts/shared/opencode-shell --help 2>&1)"
[[ "$SHELL_HELP" == *'Description:'* ]]
[[ "$SHELL_HELP" == *'interactive shell'* ]]

LOGS_HELP="$($ROOT/scripts/shared/opencode-logs --help 2>&1)"
[[ "$LOGS_HELP" == *'podman logs'* ]]
[[ "$LOGS_HELP" == *'--tail 50'* ]]

STATUS_HELP="$($ROOT/scripts/shared/opencode-status --help 2>&1)"
[[ "$STATUS_HELP" == *'resolved workspace container'* ]]

STOP_HELP="$($ROOT/scripts/shared/opencode-stop --help 2>&1)"
[[ "$STOP_HELP" == *'already stopped'* ]]

REMOVE_HELP="$($ROOT/scripts/shared/opencode-remove --help 2>&1)"
[[ "$REMOVE_HELP" == *'All, but newest'* ]]
[[ "$REMOVE_HELP" == *'containers first and then all images'* ]]

echo "Argument contract checks passed"
