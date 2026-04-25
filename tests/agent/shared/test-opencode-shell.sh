#!/usr/bin/env bash

set -euo pipefail

# This test checks that the shell script finds the running workspace container and execs commands inside it.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

CONFIG_PATH="$ROOT/config/agent/shared/opencode-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
IMAGE_ID='1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
IMAGE_NAME="opencode-1.14.21-20260418-120000-${IMAGE_ID}"
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
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
        printf 'opencode-1.14.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321-alpha-beta\n'
        ;;
      project-workspace-collision)
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-beta-alpha-prod\n'
        ;;
      *)
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
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
OPENCODE_VERSION="1.14.21"
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

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta >"$TMP_DIR/shell.out" 2>"$TMP_DIR/shell.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell opens nu in the running workspace container by default'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta env >"$TMP_DIR/command.out" 2>"$TMP_DIR/command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell forwards extra command words directly into the container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha -- env >"$TMP_DIR/legacy-command.out" 2>"$TMP_DIR/legacy-command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell supports legacy workspace-plus-command usage behind --'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha -- /bin/sh >"$TMP_DIR/slash-command.out" 2>"$TMP_DIR/slash-command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta /bin/sh" "$PODMAN_LOG" 'shell preserves slash-prefixed commands after --'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha beta >"$TMP_DIR/multiple.out" 2>"$TMP_DIR/multiple.err"
assert_file_contains 'ps --sort created --format {{.Names}} --filter name=^opencode-' "$PODMAN_LOG" 'shell asks Podman to sort running OpenCode containers by creation time before workspace matching'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell uses the newest container returned by Podman when multiple canonical containers match'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >/dev/null 2>"$TMP_DIR/multiple-ambiguous.err"; then
  fail 'shell should reject workspace-only attach when multiple project containers are running'
fi
assert_file_contains 'Multiple running OpenCode containers found for alpha.' "$TMP_DIR/multiple-ambiguous.err" 'shell requires an explicit project when more than one project container is running for a workspace'

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
