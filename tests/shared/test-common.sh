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

resolve_workspace "/tmp/My Workspace"
assert_eq "/tmp/My Workspace" "$WORKSPACE_INPUT" "workspace input preserves absolute path"
assert_eq "/tmp/My Workspace" "$WORKSPACE_ROOT" "absolute workspace uses direct path"
assert_eq "My Workspace" "$WORKSPACE_NAME" "absolute workspace derives basename"

EXPECTED_HASH="$(hash_workspace_path "/tmp/My Workspace")"
assert_eq "opencode-my-workspace-$EXPECTED_HASH" "$CONTAINER_NAME" "absolute workspace container name is unique and sanitized"

resolve_workspace "/tmp/My Workspace/"
assert_eq "/tmp/My Workspace" "$WORKSPACE_INPUT" "absolute workspace input is normalized"
assert_eq "/tmp/My Workspace" "$WORKSPACE_ROOT" "absolute workspace root drops trailing slash"
assert_eq "opencode-my-workspace-$EXPECTED_HASH" "$CONTAINER_NAME" "absolute workspace trailing slash does not change container name"

resolve_workspace "/tmp/./My Workspace"
assert_eq "/tmp/My Workspace" "$WORKSPACE_ROOT" "absolute workspace root normalizes current directory segments"
assert_eq "opencode-my-workspace-$EXPECTED_HASH" "$CONTAINER_NAME" "absolute workspace current directory alias keeps container name"

resolve_workspace "/tmp/folder/../My Workspace"
assert_eq "/tmp/My Workspace" "$WORKSPACE_ROOT" "absolute workspace root normalizes parent directory segments"
assert_eq "opencode-my-workspace-$EXPECTED_HASH" "$CONTAINER_NAME" "absolute workspace parent directory alias keeps container name"

resolve_workspace "/var/tmp/My Workspace"
assert_eq "/var/tmp/My Workspace" "$WORKSPACE_ROOT" "second absolute workspace uses direct path"

SECOND_HASH="$(hash_workspace_path "/var/tmp/My Workspace")"
assert_eq "opencode-my-workspace-$SECOND_HASH" "$CONTAINER_NAME" "second absolute workspace gets its own hashed container name"

if [[ "$EXPECTED_HASH" == "$SECOND_HASH" ]]; then
  printf 'assertion failed: absolute workspace hashes should differ\n' >&2
  exit 1
fi

echo "Common helper checks passed"
