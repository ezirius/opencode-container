#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
	local file="$1" needle="$2" message="$3"
	grep -Fq -- "$needle" "$file" || {
		printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2
		exit 1
	}
}

assert_exit_zero() {
	local command="$1"
	local output_file="$2"
	if ! sh -lc "$command" >"$output_file" 2>&1; then
		printf 'assertion failed: command should have succeeded\ncommand: %s\n' "$command" >&2
		exit 1
	fi
}

assert_rejects() {
	local script_path="$1" expected="$2"
	shift 2
	local err="$TMPDIR/$(basename "$script_path").err"
	if "$script_path" "$@" >/dev/null 2>"$err"; then
		printf 'assertion failed: %s should reject invalid arguments\n' "$script_path" >&2
		exit 1
	fi
	assert_contains "$err" "$expected" "script reports invalid usage clearly"
}

assert_command_rejects() {
	local command="$1" expected="$2" err="$3"
	if sh -lc "$command" >/dev/null 2>"$err"; then
		printf 'assertion failed: command should reject invalid arguments\ncommand: %s\n' "$command" >&2
		exit 1
	fi
	assert_contains "$err" "$expected" "command reports invalid usage clearly"
}

assert_rejects "$ROOT/scripts/shared/opencode-start" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-open" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-shell" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-stop" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-status" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" container
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" image
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" wrong
assert_rejects "$ROOT/scripts/shared/opencode-logs" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-bootstrap" 'no workspaces found under'
assert_rejects "$ROOT/scripts/shared/opencode-start" '<workspace> <production|test> <upstream>' demo production
assert_rejects "$ROOT/scripts/shared/opencode-open" '<workspace> <production|test> <upstream>' demo production
assert_rejects "$ROOT/scripts/shared/opencode-shell" '<workspace> <production|test> <upstream>' demo production
assert_rejects "$ROOT/scripts/shared/opencode-build" 'lane must be one of <production|test>' staging
assert_command_rejects "OPENCODE_SKIP_BUILD_CONTEXT_CHECK=1 '$ROOT/scripts/shared/opencode-build' test nonsense" "upstream selector must be 'main', 'latest', or an exact release tag" "$TMPDIR/build-invalid-upstream.err"
assert_rejects "$ROOT/scripts/shared/opencode-status" 'Usage: opencode-status <workspace>' demo extra
assert_rejects "$ROOT/scripts/shared/opencode-stop" 'Usage: opencode-stop <workspace>' demo extra

BUILD_HELP="$($ROOT/scripts/shared/opencode-build --help 2>&1)"
[[ "$BUILD_HELP" == *'Usage: opencode-build <production|test> [upstream]'* ]]
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

assert_exit_zero "'$ROOT/scripts/shared/opencode-start' --help ignored trailing args" "$TMPDIR/start-help.out"
assert_contains "$TMPDIR/start-help.out" 'Usage: opencode-start [<workspace>] [opencode args...]' 'help output wins even when extra trailing args are present'
assert_exit_zero "OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-build' --help" "$TMPDIR/build-help-config.out"
assert_contains "$TMPDIR/build-help-config.out" 'Usage: opencode-build <shipit|try> [upstream]' 'build help reflects configured lane names'
assert_exit_zero "OPENCODE_UPSTREAM_MAIN_SELECTOR=trunk OPENCODE_DEFAULT_UPSTREAM_SELECTOR=stable '$ROOT/scripts/shared/opencode-build' --help" "$TMPDIR/build-help-upstream.out"
assert_contains "$TMPDIR/build-help-upstream.out" '- trunk' 'build help reflects configured main upstream selector'
assert_contains "$TMPDIR/build-help-upstream.out" '- stable' 'build help reflects configured default upstream selector'

echo "Argument contract checks passed"
