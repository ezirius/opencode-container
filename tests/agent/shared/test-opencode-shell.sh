#!/usr/bin/env bash

set -euo pipefail

# This test checks that the shell script prompts for missing choices and execs commands inside a running project container.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

CONFIG_PATH="$ROOT/config/agent/shared/opencode-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
IMAGE_ID='1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
IMAGE_NAME="opencode-1.14.24-20260418-120000-${IMAGE_ID}"
OLD_IMAGE_NAME='opencode-1.14.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321'

cleanup() {
  cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT
cp "$CONFIG_PATH" "$CONFIG_BACKUP"

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman returns a single running container and records exec calls.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$OPENCODE_TEST_PODMAN_LOG"

case "$1" in
  ps)
    case "${OPENCODE_TEST_CONTAINER_MODE:-present}" in
      multiple)
        printf 'opencode-1.14.24-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
        printf 'opencode-1.14.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321-alpha-beta\n'
        ;;
      project-workspace-collision)
        printf 'opencode-1.14.24-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-beta-alpha-prod\n'
        ;;
      *)
        printf 'opencode-1.14.24-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
        ;;
    esac
    ;;
  inspect)
    if [[ "$*" == *'{{range .Mounts}}'* ]]; then
      container_name="${@: -1}"
      workspace_mount="${OPENCODE_TEST_WORKSPACE_MOUNT:-}"
      project_mount="${OPENCODE_TEST_PROJECT_MOUNT:-}"

      if [[ -z "$workspace_mount" || -z "$project_mount" ]]; then
        case "$container_name" in
          *-alpha-prod-*)
            workspace_mount="${workspace_mount:-$OPENCODE_TEST_BASE_PATH/alpha-prod/opencode-general}"
            project_mount="${project_mount:-$OPENCODE_TEST_DEVELOPMENT_ROOT/beta}"
            ;;
          *-beta-*)
            workspace_mount="${workspace_mount:-$OPENCODE_TEST_BASE_PATH/beta/opencode-general}"
            project_mount="${project_mount:-$OPENCODE_TEST_DEVELOPMENT_ROOT/alpha-prod}"
            ;;
          *)
            workspace_mount="${workspace_mount:-$OPENCODE_TEST_BASE_PATH/alpha/opencode-general}"
            project_mount="${project_mount:-$OPENCODE_TEST_DEVELOPMENT_ROOT/beta}"
            ;;
        esac
      fi

      printf '%s\n' "$workspace_mount : /workspace/general"
      printf '%s\n' "$project_mount : /workspace/project"
    fi
    ;;
  exec)
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman"

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_IMAGE_REPOSITORY="ghcr.io/anomalyco/opencode"
OPENCODE_VERSION="1.14.24"
OPENCODE_TARGET_ARCH="arm64"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_WORKSPACES="alpha:10000 alpha-prod:15000 beta:20000"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/general"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-general"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="nu"
EOF

mkdir -p "$TMP_DIR/development/alpha" "$TMP_DIR/development/beta"
PODMAN_LOG="$TMP_DIR/podman.log"
export OPENCODE_TEST_BASE_PATH="$TMP_DIR/base"
export OPENCODE_TEST_DEVELOPMENT_ROOT="$TMP_DIR/development"

# This verifies the fully prompted path before checking explicit argument handling.
: >"$PODMAN_LOG"
printf '1\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" >"$TMP_DIR/no-args.out" 2>"$TMP_DIR/no-args.err"
assert_file_contains 'Pick a workspace:' "$TMP_DIR/no-args.err" 'shell without arguments prompts for a workspace'
assert_file_contains 'Pick a project:' "$TMP_DIR/no-args.err" 'shell without arguments prompts for a project'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell without arguments opens the configured shell in the prompted project container'

# This verifies that a workspace argument still prompts for the project.
: >"$PODMAN_LOG"
printf '2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >"$TMP_DIR/workspace-only.out" 2>"$TMP_DIR/workspace-only.err"
assert_file_contains 'Pick a project:' "$TMP_DIR/workspace-only.err" 'shell with only a workspace prompts for a project'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell with only a workspace opens the configured shell in the prompted project container'

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta >"$TMP_DIR/shell.out" 2>"$TMP_DIR/shell.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell opens nu in the running workspace container by default'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta env >"$TMP_DIR/command.out" 2>"$TMP_DIR/command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell forwards extra command words directly into the container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta opencode -c comment >"$TMP_DIR/opencode-command.out" 2>"$TMP_DIR/opencode-command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode -c comment" "$PODMAN_LOG" 'shell forwards opencode command arguments exactly once'
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode opencode -c comment" "$PODMAN_LOG" 'shell does not duplicate the opencode command'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha -- env >"$TMP_DIR/legacy-command.out" 2>"$TMP_DIR/legacy-command.err"; then
  fail 'shell should not support legacy workspace-plus-command usage behind --'
fi
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell does not treat legacy -- as workspace-plus-command separator'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta >"$TMP_DIR/multiple.out" 2>"$TMP_DIR/multiple.err"
assert_file_contains 'ps --sort created --format {{.Names}} --filter name=^opencode-' "$PODMAN_LOG" 'shell asks Podman to sort running OpenCode containers by creation time before workspace matching'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell uses the newest container returned by Podman when multiple canonical containers match'

: >"$PODMAN_LOG"
printf '2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >"$TMP_DIR/multiple-prompt.out" 2>"$TMP_DIR/multiple-prompt.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell prompts for project instead of rejecting workspace-only attach when multiple containers are running'

rm -rf "$TMP_DIR/development/beta"
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta env >"$TMP_DIR/missing-project.out" 2>"$TMP_DIR/missing-project.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell still attaches to a running container when the host project directory no longer exists'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='project-workspace-collision' OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/beta/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha-prod" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha-prod alpha >"$TMP_DIR/project-workspace-collision.out" 2>"$TMP_DIR/project-workspace-collision.err"; then
  fail 'shell should reject a container whose project token collides with the requested workspace name'
fi
assert_file_contains 'No running OpenCode container found for alpha-prod.' "$TMP_DIR/project-workspace-collision.err" 'shell does not mistake a project token for the requested workspace name'

printf 'opencode-shell behavior checks passed\n'
