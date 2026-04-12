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

assert_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2; exit 1; }
}

assert_function_rejects() {
  local command="$1"
  local expected="$2"
  local output_file="$3"
  if bash -lc "source '$ROOT/lib/shell/common.sh'; OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT'; OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT'; $command" > "$output_file" 2>&1; then
    printf 'assertion failed: command should have failed\ncommand: %s\n' "$command" >&2
    exit 1
  fi
  assert_contains "$output_file" "$expected" 'function reports the expected validation failure'
}

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
MOCK_BIN="$TMPROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "-C" ]]; then
  cd "$2"
  shift 2
fi

case "$1" in
  rev-parse)
    case "${2-}" in
      --git-dir|--git-common-dir)
        if [[ "${2-}" == "--git-dir" && -n "${GIT_MOCK_GIT_DIR:-}" ]]; then
          printf '%s\n' "$GIT_MOCK_GIT_DIR"
        elif [[ "${2-}" == "--git-common-dir" && -n "${GIT_MOCK_COMMON_DIR:-}" ]]; then
          printf '%s\n' "$GIT_MOCK_COMMON_DIR"
        else
          printf '.git\n'
        fi
        ;;
      --show-toplevel)
        printf '%s' "${GIT_MOCK_TOPLEVEL:-$(pwd)}"
        printf '\n'
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$MOCK_BIN/git"
PATH="$MOCK_BIN:$PATH"

OPENCODE_BASE_ROOT="$TMPROOT/workspaces"
OPENCODE_DEVELOPMENT_ROOT="$TMPROOT/opencode-development"
mkdir -p "$OPENCODE_DEVELOPMENT_ROOT"

assert_eq "$TMPROOT/workspaces/general" "$(workspace_root_dir general)" "workspace root follows base root"
assert_eq "$TMPROOT/workspaces/general/opencode-home" "$(workspace_home_dir general)" "workspace home path is correct"
assert_eq "$TMPROOT/workspaces/general/opencode-workspace" "$(workspace_dir general)" "workspace dir path is correct"
assert_eq "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode" "$(workspace_config_dir general)" "workspace config dir path is correct"
assert_eq "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" "$(workspace_config_env_file general)" "workspace config env path is correct"
assert_eq "/workspace/opencode-workspace" "$(container_workspace_dir)" "container workspace dir is correct"
assert_eq "/workspace/opencode-workspace/.config/opencode" "$(container_config_dir)" "container config dir is correct"
assert_eq "$TMPROOT/opencode-development:/workspace/opencode-development" "$(development_mount_spec)" "development mount uses configured root"
assert_eq "opencode-general-production-1.4.3-main" "$(container_name general production 1.4.3 main)" "container name uses deterministic identity"
assert_eq "opencode-local:test-1.4.3-main-20260410-163440-ab12cd3" "$(image_ref test 1.4.3 main 20260410-163440-ab12cd3)" "image ref uses immutable identity"
assert_eq "1.4.3" "$(resolve_upstream_selector 1.4.3)" "exact upstream selector stays unchanged"
assert_eq "1.4.3" "$(resolve_upstream_selector v1.4.3)" "v-prefixed upstream selector normalizes"
assert_eq "v1.4.3" "$(upstream_ref_for_selector 1.4.3)" "exact upstream ref gets v prefix"
mkdir -p "$TMPROOT/alternate-primary-checkout"
assert_eq "main" "$(current_wrapper_context "$TMPROOT/alternate-primary-checkout")" "primary checkouts use wrapper context main even when the directory name differs"
mkdir -p "$TMPROOT/opencode-container-worktrees/feature.alpha"
export GIT_MOCK_GIT_DIR='.git/worktrees/feature.alpha'
export GIT_MOCK_COMMON_DIR='.git'
export GIT_MOCK_TOPLEVEL="$TMPROOT/opencode-container-worktrees/feature.alpha"
assert_eq 'feature.alpha' "$(current_wrapper_context "$TMPROOT/opencode-container-worktrees/feature.alpha")" "linked worktrees use the sanitised worktree directory name as the wrapper context"
unset GIT_MOCK_GIT_DIR GIT_MOCK_COMMON_DIR GIT_MOCK_TOPLEVEL

ensure_workspace_layout general
seed_workspace_config_env_file general
test -d "$TMPROOT/workspaces/general/opencode-home"
test -d "$TMPROOT/workspaces/general/opencode-workspace"
test -f "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env"

cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5096
MALICIOUS=$(touch /tmp/opencode-common-test-malicious)
EOF
cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/secrets.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5097
EOF
assert_eq '5097' "$(workspace_server_port general)" "workspace server port uses parsed assignment values with secrets overriding config"
test ! -e /tmp/opencode-common-test-malicious

cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
export   OPENCODE_HOST_SERVER_PORT=5098
OPENCODE_HOST_SERVER_PORT=5099
EOF
rm -f "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/secrets.env"
assert_eq '5099' "$(workspace_server_port general)" "workspace env parsing keeps the last matching assignment and accepts spaced export syntax"

cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
export OPENCODE_HOST_SERVER_PORT="5100" # comment
EOF
assert_eq '5100' "$(workspace_server_port general)" "workspace server port parsing accepts quoted values with inline comments"

cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=abc
EOF
assert_function_rejects 'workspace_server_port general' 'OPENCODE_HOST_SERVER_PORT must be numeric' "$TMPROOT/invalid-port-alpha.out"

cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=65536
EOF
assert_function_rejects 'workspace_server_port general' 'OPENCODE_HOST_SERVER_PORT must be between 1 and 65535' "$TMPROOT/invalid-port-range.out"

cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5098
EOF
cat > "$TMPROOT/workspaces/general/opencode-workspace/.config/opencode/secrets.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=
EOF
assert_eq '' "$(workspace_env_value general OPENCODE_HOST_SERVER_PORT)" "empty secrets assignments override config assignments"

ENTRYPOINT_CONFIG="$TMPROOT/entrypoint-config.env"
ENTRYPOINT_SECRETS="$TMPROOT/entrypoint-secrets.env"
ENTRYPOINT_RUNTIME="$TMPROOT/entrypoint-runtime.env"
ENTRYPOINT_TARGET="$TMPROOT/entrypoint-target.txt"

printf 'OPENCODE_HOST_SERVER_PORT="5101" # comment\r\nTOKEN=$(touch /tmp/opencode-entrypoint-test)\r\n' > "$ENTRYPOINT_CONFIG"
printf 'SECRET_TOKEN=abc123\r\n' > "$ENTRYPOINT_SECRETS"
OPENCODE_WRAPPER_RUNTIME_ENV_FILE="$ENTRYPOINT_RUNTIME" \
OPENCODE_WRAPPER_CONFIG_ENV_FILE="$ENTRYPOINT_CONFIG" \
OPENCODE_WRAPPER_SECRETS_ENV_FILE="$ENTRYPOINT_SECRETS" \
  sh "$ROOT/config/containers/entrypoint.sh" sh -c '. "$OPENCODE_WRAPPER_RUNTIME_ENV_FILE"; printf "%s\n%s\n%s\n" "$OPENCODE_HOST_SERVER_PORT" "$TOKEN" "$SECRET_TOKEN"' > "$TMPROOT/entrypoint-values.out"
assert_contains "$TMPROOT/entrypoint-values.out" '5101' 'entrypoint exports quoted config values with inline comments correctly'
assert_contains "$TMPROOT/entrypoint-values.out" '$(touch /tmp/opencode-entrypoint-test)' 'entrypoint treats command substitutions as literal values'
assert_contains "$TMPROOT/entrypoint-values.out" 'abc123' 'entrypoint loads secrets after config'
test ! -e /tmp/opencode-entrypoint-test
assert_contains "$ENTRYPOINT_RUNTIME" "export OPENCODE_HOST_SERVER_PORT='5101'" 'entrypoint writes exported runtime assignments'

printf 'SECRET_TOKEN=base\nMESSAGE="value # kept"\nSPACED="  keep me  "\nNAME_WITH_QUOTE="O'"'"'Brien"\n' > "$ENTRYPOINT_CONFIG"
printf 'SECRET_TOKEN=override\nSPACED=\n' > "$ENTRYPOINT_SECRETS"
OPENCODE_WRAPPER_RUNTIME_ENV_FILE="$ENTRYPOINT_RUNTIME" \
OPENCODE_WRAPPER_CONFIG_ENV_FILE="$ENTRYPOINT_CONFIG" \
OPENCODE_WRAPPER_SECRETS_ENV_FILE="$ENTRYPOINT_SECRETS" \
  sh "$ROOT/config/containers/entrypoint.sh" true
bash -n "$ENTRYPOINT_RUNTIME"
assert_contains "$ENTRYPOINT_RUNTIME" "export SECRET_TOKEN='override'" 'entrypoint keeps the last matching secret assignment'
assert_contains "$ENTRYPOINT_RUNTIME" "export MESSAGE='value # kept'" 'entrypoint preserves literal hash characters inside quoted values'
assert_contains "$ENTRYPOINT_RUNTIME" "export SPACED=''" 'entrypoint allows empty secret overrides'
assert_contains "$ENTRYPOINT_RUNTIME" "export NAME_WITH_QUOTE='O'\\''Brien'" 'entrypoint escapes embedded single quotes safely'

printf 'protected\n' > "$ENTRYPOINT_TARGET"
ln -sf "$ENTRYPOINT_TARGET" "$ENTRYPOINT_RUNTIME"
OPENCODE_WRAPPER_RUNTIME_ENV_FILE="$ENTRYPOINT_RUNTIME" \
OPENCODE_WRAPPER_CONFIG_ENV_FILE="$ENTRYPOINT_CONFIG" \
OPENCODE_WRAPPER_SECRETS_ENV_FILE="$ENTRYPOINT_SECRETS" \
  sh "$ROOT/config/containers/entrypoint.sh" true
assert_eq 'protected' "$(tr -d '\n' < "$ENTRYPOINT_TARGET")" "entrypoint does not overwrite symlink targets when recreating the runtime env file"

assert_eq "false" "$(bash -lc 'source "$1" && if use_exec_tty; then printf true; else printf false; fi' bash "$ROOT/lib/shell/common.sh")" "non-interactive exec keeps stdin only"

echo "Common helper checks passed"
