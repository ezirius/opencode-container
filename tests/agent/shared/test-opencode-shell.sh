#!/usr/bin/env bash

set -euo pipefail

# This test checks that the shell script finds the running workspace container and execs commands inside it.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

CONFIG_PATH="$ROOT/config/agent/shared/opencode-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"

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
        printf 'opencode-1.4.3-20260419-120000-123-bbbbbbbbbbbb-alpha\n'
        printf 'opencode-1.4.3-20260418-120000-123-aaaaaaaaaaaa-alpha\n'
        ;;
      next-only)
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-999\n'
        ;;
      staged)
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-999\n'
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha\n'
        ;;
      *)
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha\n'
        ;;
    esac
    ;;
  exec)
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman"

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime and build configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.4.3"
OPENCODE_RELEASE_TAG="v1.4.3"
OPENCODE_ALPINE_VERSION="3.23"
OPENCODE_ALPINE_DIGEST="sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11"
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

mkdir -p "$TMP_DIR/development/alpha"
PODMAN_LOG="$TMP_DIR/podman.log"

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >"$TMP_DIR/shell.out" 2>"$TMP_DIR/shell.err"
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha nu' "$PODMAN_LOG" 'shell opens nu in the running workspace container by default'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-shell" alpha env >"$TMP_DIR/command.out" 2>"$TMP_DIR/command.err"
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha env' "$PODMAN_LOG" 'shell forwards extra command words directly into the container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='staged' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >"$TMP_DIR/staged.out" 2>"$TMP_DIR/staged.err"
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha nu' "$PODMAN_LOG" 'shell ignores staged replacement containers and attaches to the canonical workspace container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >"$TMP_DIR/multiple.out" 2>"$TMP_DIR/multiple.err"
assert_file_contains 'ps --sort created --format {{.Names}} --filter name=^opencode-1\.4\.3-' "$PODMAN_LOG" 'shell asks Podman to sort running containers by creation time instead of sorting names lexically'
assert_file_contains 'exec -i opencode-1.4.3-20260419-120000-123-bbbbbbbbbbbb-alpha nu' "$PODMAN_LOG" 'shell uses the newest container returned by Podman when multiple canonical containers match'
assert_file_contains '--filter name=^opencode-1\.4\.3-' "$PODMAN_LOG" 'shell uses a workspace filter that does not collide with prefix-matching workspace names'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='next-only' bash "$ROOT/scripts/agent/shared/opencode-shell" alpha >/dev/null 2>"$TMP_DIR/next-only.err"; then
  fail 'shell should fail cleanly when only staged replacement containers are running'
fi
assert_file_contains 'No running OpenCode container found for alpha.' "$TMP_DIR/next-only.err" 'shell keeps the friendly missing-container error when only staged replacements exist'

printf 'opencode-shell behavior checks passed\n'
