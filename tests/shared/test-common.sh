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
assert_eq "opencode-general" "$CONTAINER_NAME" "named workspace container name is stable"

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

resolve_workspace "/var/tmp/My Workspace"
assert_eq "/var/tmp/My Workspace" "$WORKSPACE_ROOT" "second absolute workspace uses direct path"

SECOND_HASH="$(hash_workspace_path "/var/tmp/My Workspace")"
assert_eq "opencode-my-workspace-$SECOND_HASH" "$CONTAINER_NAME" "second absolute workspace gets its own hashed container name"

if [[ "$EXPECTED_HASH" == "$SECOND_HASH" ]]; then
  printf 'assertion failed: absolute workspace hashes should differ\n' >&2
  exit 1
fi

echo "Common helper checks passed"
