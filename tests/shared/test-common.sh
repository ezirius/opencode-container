#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
    printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

resolve_workspace "general"
assert_eq "general" "$WORKSPACE_INPUT" "workspace input preserves named workspace"
assert_eq "$OPENCODE_BASE_ROOT/general" "$WORKSPACE_ROOT" "named workspace resolves under base root"
assert_eq "general" "$WORKSPACE_NAME" "named workspace keeps its name"
EXPECTED_NAMED_HASH="$(hash_workspace_path "$OPENCODE_BASE_ROOT/general")"
assert_eq "opencode-general-$EXPECTED_NAMED_HASH" "$CONTAINER_NAME" "named workspace container name includes workspace path"

OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT/"
resolve_workspace "general"
assert_eq "${OPENCODE_BASE_ROOT%/}/general" "$WORKSPACE_ROOT" "named workspace ignores trailing slash in base root"
assert_eq "opencode-general-$EXPECTED_NAMED_HASH" "$CONTAINER_NAME" "named workspace ignores trailing slash in base root for container name"

if (resolve_workspace "nested/general") >/dev/null 2>&1; then
  printf 'assertion failed: named workspace with path separators should fail\n' >&2
  exit 1
fi

if (resolve_workspace "..") >/dev/null 2>&1; then
  printf 'assertion failed: parent directory workspace name should fail\n' >&2
  exit 1
fi

OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT%/}"

ORIGINAL_BASE_ROOT="$OPENCODE_BASE_ROOT"
OPENCODE_BASE_ROOT="/tmp/alternate-opencode-root"
resolve_workspace "general"
ALTERNATE_HASH="$(hash_workspace_path "/tmp/alternate-opencode-root/general")"
assert_eq "opencode-general-$ALTERNATE_HASH" "$CONTAINER_NAME" "named workspace container name changes with base root"
OPENCODE_BASE_ROOT="$ORIGINAL_BASE_ROOT"

assert_eq "false" "$(bash -lc 'source "$1" && if use_exec_tty; then printf true; else printf false; fi' bash "$ROOT/lib/shell/common.sh")" "non-interactive exec keeps stdin only"

ORIGINAL_HOME="$HOME"
HOME="/tmp/opencode-home"
OPENCODE_BASE_ROOT='~/workspace-root'
resolve_workspace "general"
assert_eq "/tmp/opencode-home/workspace-root/general" "$WORKSPACE_ROOT" "named workspace expands tilde in base root"
HOME="$ORIGINAL_HOME"
OPENCODE_BASE_ROOT="$ORIGINAL_BASE_ROOT"

UBUNTU_VERSION="24.04"
assert_eq "24.04" "$(resolve_ubuntu_version)" "explicit Ubuntu version is returned unchanged"

OPENCODE_VERSION="1.2.27"
assert_eq "1.2.27" "$(resolve_opencode_version)" "explicit OpenCode version is returned unchanged"

if (resolve_workspace "/tmp/My Workspace") >/dev/null 2>&1; then
  printf 'assertion failed: absolute workspace path should fail\n' >&2
  exit 1
fi

echo "Common helper checks passed"
