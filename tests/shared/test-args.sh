#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

EMPTY_BASE_ROOT="$TMPDIR/empty-base-root"
EMPTY_DEVELOPMENT_ROOT="$TMPDIR/empty-development-root"
mkdir -p "$EMPTY_BASE_ROOT" "$EMPTY_DEVELOPMENT_ROOT"
ISOLATED_EMPTY_ENV="OPENCODE_BASE_ROOT='$EMPTY_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$EMPTY_DEVELOPMENT_ROOT'"

README_DOC="$ROOT/README.md"
USAGE_DOC="$ROOT/docs/shared/usage.md"

assert_contains() {
	local file="$1" needle="$2" message="$3"
	grep -Fq -- "$needle" "$file" || {
		printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2
		exit 1
	}
}

assert_output_contains() {
	local output="$1" needle="$2" message="$3"
	[[ "$output" == *"$needle"* ]] || {
		printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2
		exit 1
	}
}

assert_not_contains() {
	local file="$1" needle="$2" message="$3"
	if grep -Fq -- "$needle" "$file"; then
		printf 'assertion failed: %s\nunexpected: %s\n' "$message" "$needle" >&2
		exit 1
	fi
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

assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-start'" 'no workspaces found under' "$TMPDIR/start-no-workspaces.err"
assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-open'" 'no workspaces found under' "$TMPDIR/open-no-workspaces.err"
assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-shell'" 'no workspaces found under' "$TMPDIR/shell-no-workspaces.err"
assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-stop'" 'no workspaces found under' "$TMPDIR/stop-no-workspaces.err"
assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-status'" 'no workspaces found under' "$TMPDIR/status-no-workspaces.err"
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" container
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" image
assert_rejects "$ROOT/scripts/shared/opencode-remove" "mode must be 'mixed', 'containers', or 'images'" wrong
assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-logs'" 'no workspaces found under' "$TMPDIR/logs-no-workspaces.err"
assert_command_rejects "$ISOLATED_EMPTY_ENV '$ROOT/scripts/shared/opencode-bootstrap'" 'no workspaces found under' "$TMPDIR/bootstrap-no-workspaces.err"
assert_command_rejects "OPENCODE_DEVELOPMENT_ROOT='$EMPTY_DEVELOPMENT_ROOT' OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-start' demo shipit" '<workspace> <shipit|try> <upstream>' "$TMPDIR/start-invalid-lane.err"
assert_command_rejects "OPENCODE_DEVELOPMENT_ROOT='$EMPTY_DEVELOPMENT_ROOT' OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-open' demo shipit" '<workspace> <shipit|try> <upstream>' "$TMPDIR/open-invalid-lane.err"
assert_command_rejects "OPENCODE_DEVELOPMENT_ROOT='$EMPTY_DEVELOPMENT_ROOT' OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-shell' demo shipit" '<workspace> <shipit|try> <upstream>' "$TMPDIR/shell-invalid-lane.err"
assert_command_rejects "OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-build' staging" 'lane must be one of <shipit|try>' "$TMPDIR/build-invalid-lane.err"
assert_command_rejects "OPENCODE_SKIP_BUILD_CONTEXT_CHECK=1 OPENCODE_UPSTREAM_MAIN_SELECTOR=trunk OPENCODE_DEFAULT_UPSTREAM_SELECTOR=stable '$ROOT/scripts/shared/opencode-build' test nonsense" "upstream selector must be 'trunk', 'stable', or an exact release tag" "$TMPDIR/build-invalid-upstream.err"
assert_rejects "$ROOT/scripts/shared/opencode-status" 'Usage: opencode-status [<workspace>]' demo extra
assert_rejects "$ROOT/scripts/shared/opencode-stop" 'Usage: opencode-stop [<workspace>]' demo extra

BUILD_HELP="$($ROOT/scripts/shared/opencode-build --help 2>&1)"
[[ "$BUILD_HELP" == *"Usage: opencode-build <${OPENCODE_LANE_PRODUCTION:-production}|${OPENCODE_LANE_TEST:-test}> [upstream]"* ]]
[[ "$BUILD_HELP" == *'Accepted [upstream] values:'* ]]

BOOTSTRAP_HELP="$($ROOT/scripts/shared/opencode-bootstrap --help 2>&1)"
[[ "$BOOTSTRAP_HELP" == *'Usage: opencode-bootstrap [<workspace>] [project] [opencode args...]'* ]]
[[ "$BOOTSTRAP_HELP" == *'opencode-bootstrap [<workspace>] [project] -- [opencode args...]'* ]]

START_HELP="$($ROOT/scripts/shared/opencode-start --help 2>&1)"
[[ "$START_HELP" == *'[project]'* ]]

OPEN_HELP="$($ROOT/scripts/shared/opencode-open --help 2>&1)"
[[ "$OPEN_HELP" == *'[project]'* ]]

SHELL_HELP="$($ROOT/scripts/shared/opencode-shell --help 2>&1)"
[[ "$SHELL_HELP" == *'Usage: opencode-shell [<workspace>] [project] [command args...]'* ]]

LOGS_HELP="$($ROOT/scripts/shared/opencode-logs --help 2>&1)"
[[ "$LOGS_HELP" == *'Usage: opencode-logs [<workspace>] [podman logs args...]'* ]]

STATUS_HELP="$($ROOT/scripts/shared/opencode-status --help 2>&1)"
[[ "$STATUS_HELP" == *'Usage: opencode-status [<workspace>]'* ]]

STOP_HELP="$($ROOT/scripts/shared/opencode-stop --help 2>&1)"
assert_output_contains "$STOP_HELP" 'Usage: opencode-stop [<workspace>]' 'stop help includes usage'
assert_output_contains "$STOP_HELP" 'OPENCODE_BASE_ROOT' 'stop help mentions workspace root cleanly'
assert_output_contains "$STOP_HELP" 'which container to stop' 'stop help documents container prompting'
assert_output_contains "$STOP_HELP" 'only one matching container exists' 'stop help documents prompting even for one match'
[[ "$STOP_HELP" != *'syntax error'* ]]
[[ "$STOP_HELP" != *'command not found'* ]]
[[ "$STOP_HELP" != *'No such file or directory'* ]]

REMOVE_HELP="$($ROOT/scripts/shared/opencode-remove --help 2>&1)"
[[ "$REMOVE_HELP" == *'Usage: opencode-remove [mixed|containers|images]'* ]]
[[ "$REMOVE_HELP" == *'opencode-remove mixed'* ]]
assert_output_contains "$REMOVE_HELP" 'All, but newest keeps one retained container per workspace' 'remove help documents retained container behaviour'
assert_output_contains "$REMOVE_HELP" 'lane rank, newest commitstamp, then lexical container name' 'remove help documents the deterministic tie-break rule'
[[ "$REMOVE_HELP" != *'lane and commit ordering produce a single first match'* ]]

assert_exit_zero "'$ROOT/scripts/shared/opencode-start' --help ignored trailing args" "$TMPDIR/start-help.out"
assert_contains "$TMPDIR/start-help.out" 'Usage: opencode-start [<workspace>] [project] [opencode args...]' 'help output wins even when extra trailing args are present'
assert_exit_zero "OPENCODE_LANE_PRODUCTION=shipit OPENCODE_LANE_TEST=try '$ROOT/scripts/shared/opencode-build' --help" "$TMPDIR/build-help-config.out"
assert_contains "$TMPDIR/build-help-config.out" 'Usage: opencode-build <shipit|try> [upstream]' 'build help reflects configured lane names'
assert_exit_zero "OPENCODE_UPSTREAM_MAIN_SELECTOR=trunk OPENCODE_DEFAULT_UPSTREAM_SELECTOR=stable '$ROOT/scripts/shared/opencode-build' --help" "$TMPDIR/build-help-upstream.out"
assert_contains "$TMPDIR/build-help-upstream.out" '- trunk' 'build help reflects configured main upstream selector'
assert_contains "$TMPDIR/build-help-upstream.out" '- stable' 'build help reflects configured default upstream selector'

assert_contains "$README_DOC" 'fixed home `/home/opencode`' 'README makes the fixed runtime home explicit'
assert_not_contains "$README_DOC" 'configured `OPENCODE_CONTAINER_RUNTIME_HOME`' 'README no longer describes the runtime home as configurable'
assert_contains "$README_DOC" '`opencode-<workspace>-<lane>-<upstream>-<wrapper>-<project>`' 'README documents project-aware container naming format'
assert_contains "$README_DOC" '`/workspace/opencode-project`' 'README documents the fixed project path inside the container'
assert_contains "$README_DOC" './scripts/shared/opencode-bootstrap [<workspace>] [project]' 'README bootstrap command documents optional project argument'
assert_contains "$README_DOC" './scripts/shared/opencode-start [<workspace>] [project]' 'README start command documents optional project argument'
assert_contains "$README_DOC" './scripts/shared/opencode-build <lane> [upstream]' 'README build command documents configurable lane selector'
assert_contains "$README_DOC" './scripts/shared/opencode-remove mixed' 'README documents explicit mixed remove mode'
assert_contains "$README_DOC" 'one retained container per workspace' 'README documents retained container behaviour'
assert_contains "$README_DOC" 'lane rank, newest commitstamp, then lexical container name' 'README documents the deterministic tie-break rule'
assert_not_contains "$README_DOC" 'lane and commit ordering produce a single first match' 'README no longer describes retention as an implicit first match'
assert_contains "$README_DOC" '`./tests/shared/test-all.sh`' 'README verification command uses repo-relative script format'

assert_contains "$USAGE_DOC" 'fixed home `/home/opencode`' 'usage makes the fixed runtime home explicit'
assert_contains "$USAGE_DOC" '`/workspace/opencode-project`' 'usage documents the fixed project path inside the container'
assert_contains "$USAGE_DOC" './scripts/shared/opencode-bootstrap [<workspace>] [project]' 'usage bootstrap command documents optional project argument'
assert_contains "$USAGE_DOC" './scripts/shared/opencode-start [<workspace>] [project]' 'usage start command documents optional project argument'
assert_contains "$USAGE_DOC" './scripts/shared/opencode-build <lane> <upstream>' 'usage build command documents configurable lane selector'
assert_not_contains "$USAGE_DOC" 'source builds for upstream `main`' 'usage no longer hard-codes source builds to upstream main'
assert_contains "$USAGE_DOC" 'configured main selector builds from upstream source' 'usage documents configurable main upstream selector'
assert_contains "$USAGE_DOC" 'configured default selector resolves to an exact stable release before naming' 'usage documents configurable default upstream selector'
assert_contains "$USAGE_DOC" './scripts/shared/opencode-remove mixed' 'usage documents explicit mixed remove mode'
assert_contains "$USAGE_DOC" 'one retained container per workspace' 'usage documents retained container behaviour'
assert_contains "$USAGE_DOC" 'lane rank, newest commitstamp, then lexical container name' 'usage documents the deterministic tie-break rule'
assert_not_contains "$USAGE_DOC" 'lane and commit ordering produce a single first match' 'usage no longer describes retention as an implicit first match'
assert_contains "$USAGE_DOC" '`./tests/shared/test-all.sh`' 'usage verification command uses repo-relative script format'

echo "Argument contract checks passed"
