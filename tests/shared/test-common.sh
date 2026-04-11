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

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

OPENCODE_BASE_ROOT="$TMPROOT/workspaces"

assert_eq "$TMPROOT/workspaces/general" "$(workspace_root_dir general)" "workspace root follows base root"
assert_eq "$TMPROOT/workspaces/general/opencode-home" "$(workspace_home_dir general)" "workspace home path is correct"
assert_eq "$TMPROOT/workspaces/general/opencode-workspace" "$(workspace_dir general)" "workspace dir path is correct"
assert_eq "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode" "$(workspace_config_dir general)" "workspace config dir path is correct"
assert_eq "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" "$(workspace_config_env_file general)" "workspace config env path is correct"
assert_eq "/workspace/opencode-workspace" "$(container_workspace_dir)" "container workspace dir is correct"
assert_eq "/workspace/opencode-workspace/.config/opencode" "$(container_config_dir)" "container config dir is correct"
assert_eq "opencode-general-production-1.4.3-main" "$(container_name general production 1.4.3 main)" "container name uses deterministic identity"
assert_eq "opencode-local:test-1.4.3-main-20260410-163440-ab12cd3" "$(image_ref test 1.4.3 main 20260410-163440-ab12cd3)" "image ref uses immutable identity"
assert_eq "1.4.3" "$(resolve_upstream_selector 1.4.3)" "exact upstream selector stays unchanged"
assert_eq "1.4.3" "$(resolve_upstream_selector v1.4.3)" "v-prefixed upstream selector normalizes"
assert_eq "v1.4.3" "$(upstream_ref_for_selector 1.4.3)" "exact upstream ref gets v prefix"

ensure_workspace_layout general
seed_workspace_config_env_file general
test -d "$TMPROOT/workspaces/general/opencode-home"
test -d "$TMPROOT/workspaces/general/opencode-workspace"
test -f "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env"

assert_eq "false" "$(bash -lc 'source "$1" && if use_exec_tty; then printf true; else printf false; fi' bash "$ROOT/lib/shell/common.sh")" "non-interactive exec keeps stdin only"

echo "Common helper checks passed"
