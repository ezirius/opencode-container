#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

README_DOC="$ROOT/README.md"
USAGE_DOC="$ROOT/docs/shared/usage.md"

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
[[ "$START_HELP" == *'[project]'* ]]

OPEN_HELP="$($ROOT/scripts/shared/opencode-open --help 2>&1)"
[[ "$OPEN_HELP" == *'Description:'* ]]
[[ "$OPEN_HELP" == *'use `--`'* ]]
[[ "$OPEN_HELP" == *'[project]'* ]]

SHELL_HELP="$($ROOT/scripts/shared/opencode-shell --help 2>&1)"
[[ "$SHELL_HELP" == *'Description:'* ]]
[[ "$SHELL_HELP" == *'interactive shell'* ]]
[[ "$SHELL_HELP" == *'selected project directory'* ]]

LOGS_HELP="$($ROOT/scripts/shared/opencode-logs --help 2>&1)"
[[ "$LOGS_HELP" == *'podman logs'* ]]
[[ "$LOGS_HELP" == *'--tail 50'* ]]

STATUS_HELP="$($ROOT/scripts/shared/opencode-status --help 2>&1)"
[[ "$STATUS_HELP" == *'grouped diagnostic summary'* ]]
[[ "$STATUS_HELP" == *'status never prints secret values'* ]]

STOP_HELP="$($ROOT/scripts/shared/opencode-stop --help 2>&1)"
[[ "$STOP_HELP" == *'already stopped'* ]]

REMOVE_HELP="$($ROOT/scripts/shared/opencode-remove --help 2>&1)"
[[ "$REMOVE_HELP" == *'All, but newest'* ]]
[[ "$REMOVE_HELP" == *'containers first and then all images'* ]]

assert_exit_zero "'$ROOT/scripts/shared/opencode-start' --help ignored trailing args" "$TMPDIR/start-help.out"
assert_contains "$TMPDIR/start-help.out" 'Usage: opencode-start [<workspace>] [project] [opencode args...]' 'help output wins even when extra trailing args are present'
assert_exit_zero "OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-build' --help" "$TMPDIR/build-help-config.out"
assert_contains "$TMPDIR/build-help-config.out" 'Usage: opencode-build <shipit|try> [upstream]' 'build help reflects configured lane names'
assert_exit_zero "OPENCODE_UPSTREAM_MAIN_SELECTOR=trunk OPENCODE_DEFAULT_UPSTREAM_SELECTOR=stable '$ROOT/scripts/shared/opencode-build' --help" "$TMPDIR/build-help-upstream.out"
assert_contains "$TMPDIR/build-help-upstream.out" '- trunk' 'build help reflects configured main upstream selector'
assert_contains "$TMPDIR/build-help-upstream.out" '- stable' 'build help reflects configured default upstream selector'

assert_contains "$README_DOC" 'OpenCode global config in `~/.config/opencode/opencode.json`' 'README documents OpenCode global config path'
assert_contains "$README_DOC" 'OpenCode project-scoped session and message data remains app-owned under `~/.local/share/opencode/project/<project-slug>/storage/`' 'README documents upstream project-scoped session storage under the runtime home'
assert_contains "$README_DOC" 'Container identity includes the selected project so multiple projects in one workspace can run concurrently without sharing the same container name.' 'README documents project-aware container identity'
assert_contains "$README_DOC" 'selected direct-child project root under `OPENCODE_DEVELOPMENT_ROOT` -> `/workspace/opencode-project`' 'README documents the project mount and in-container workdir'
assert_contains "$README_DOC" 'picker order for project-facing commands is workspace, then target or container, then project' 'README documents picker order'
assert_contains "$README_DOC" 'Keep the current pin and continue' 'README documents the Ubuntu LTS keep option'
assert_contains "$README_DOC" 'Update `config/shared/opencode.conf` to the newer Ubuntu LTS pin and continue' 'README documents the Ubuntu LTS update option'
assert_contains "$README_DOC" 'Cancel the build without changing the pin' 'README documents the Ubuntu LTS cancel option'

assert_contains "$USAGE_DOC" 'selected direct-child project root under `OPENCODE_DEVELOPMENT_ROOT`, mounted at `/workspace/opencode-project`' 'usage documents the project mount'
assert_contains "$USAGE_DOC" 'project-facing command picker order is workspace, then target or container, then project' 'usage documents picker order'
assert_contains "$USAGE_DOC" '`opencode-open` starts in `/workspace/opencode-project`' 'usage documents open workdir'
assert_contains "$USAGE_DOC" '`opencode-shell` runs commands in `/workspace/opencode-project`' 'usage documents shell workdir'
assert_contains "$USAGE_DOC" 'OpenCode global config in `~/.config/opencode/opencode.json`' 'usage documents OpenCode global config path'
assert_contains "$USAGE_DOC" 'OpenCode project config in the selected project root as `opencode.json` and `.opencode/`' 'usage documents OpenCode project config paths'
assert_contains "$USAGE_DOC" 'OpenCode project-scoped session and message data stays under `~/.local/share/opencode/project/<project-slug>/storage/` inside the mounted runtime home.' 'usage documents upstream project-scoped session storage'
assert_contains "$USAGE_DOC" 'The selected project is part of container identity, so different projects in the same workspace resolve to different container names even when they share the same runtime home.' 'usage documents project-aware container identity'

echo "Argument contract checks passed"
