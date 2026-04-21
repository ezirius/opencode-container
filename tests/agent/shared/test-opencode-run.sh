#!/usr/bin/env bash

set -euo pipefail

# This test checks that the run script selects a workspace and project, then mounts the fixed OpenCode paths.

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

# This fake Podman records create and exec behavior for the run flow.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$OPENCODE_TEST_PODMAN_LOG"

case "$1" in
  images)
    printf 'opencode-1.4.3-20260418-120000-123\n'
    ;;
  ps)
    if [[ "${2-}" == '-aq' ]]; then
      if [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'present' ]]; then
        printf 'stale-1\nstale-2\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'prefix-collision' ]]; then
        printf 'opencode-alpha-prod-1.4.3-20260417-120000-123\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'old-version' ]]; then
        printf 'opencode-alpha-1.4.2-20260417-120000-123\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name' ]]; then
        printf 'opencode-alpha-1.4.3-20260418-120000-123\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'running' ]]; then
      if [[ "$*" == *'next-'* ]]; then
        next_name="$(printf '%s' "$*" | sed -n 's/.*name=^\(.*\)\$$/\1/p' | sed 's/\\\././g')"
        printf '%s\n' "$next_name"
      else
        printf 'opencode-alpha-1.4.3-20260418-120000-123\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'dies-before-attach' ]]; then
      if [[ "$*" == *'next-'* && ! -f "${OPENCODE_TEST_PODMAN_LOG}.next-running-once" ]]; then
        : >"${OPENCODE_TEST_PODMAN_LOG}.next-running-once"
        printf 'opencode-alpha-1.4.3-20260418-120000-123-next-999\n'
      elif [[ "$*" != *'next-'* ]]; then
        printf 'opencode-alpha-1.4.3-20260418-120000-123\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'stopped' ]]; then
      if [[ -f "${OPENCODE_TEST_PODMAN_LOG}.started" || -f "${OPENCODE_TEST_PODMAN_LOG}.ran" ]]; then
        if [[ "$*" == *'next-'* ]]; then
          next_name="$(printf '%s' "$*" | sed -n 's/.*name=^\(.*\)\$$/\1/p' | sed 's/\\\././g')"
          printf '%s\n' "$next_name"
        else
          printf 'opencode-alpha-1.4.3-20260418-120000-123\n'
        fi
      fi
    fi
    ;;
  run)
    if [[ "${OPENCODE_TEST_RUN_FAIL:-0}" == '1' ]]; then
      exit 1
    fi
    : >"${OPENCODE_TEST_PODMAN_LOG}.ran"
    printf 'new-container\n'
    ;;
  rename)
    ;;
  start)
    if [[ "${OPENCODE_TEST_START_FAIL:-0}" == '1' ]]; then
      exit 1
    fi
    : >"${OPENCODE_TEST_PODMAN_LOG}.started"
    ;;
  exec)
    printf 'mock exec\n'
    ;;
  inspect)
    if [[ "$*" == *'.State.Status'* ]]; then
      printf 'status=running running=true exit_code=0\n'
    elif [[ "$*" == *'{{range .Mounts}}'* ]]; then
      printf '%s\n' "${OPENCODE_TEST_PROJECT_MOUNT:-$OPENCODE_DEVELOPMENT_ROOT/beta} : /workspace/project"
    fi
    ;;
  logs)
    printf 'boot line 1\n'
    ;;
esac
EOF

cat >"$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1-}" in
  -u) printf '%s\n' "${OPENCODE_TEST_HOST_UID:-1001}" ;;
  -g) printf '%s\n' "${OPENCODE_TEST_HOST_GID:-1001}" ;;
  *) printf 'unexpected id invocation\n' >&2; exit 1 ;;
esac
EOF

cat >"$FAKE_BIN/chown" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$OPENCODE_TEST_CHOWN_LOG"
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/id" "$FAKE_BIN/chown"

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime and build configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.4.3"
OPENCODE_RELEASE_TAG="v1.4.3"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_ALPINE_VERSION="3.23"
OPENCODE_ALPINE_DIGEST="sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11"
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
CHOWN_LOG="$TMP_DIR/chown.log"

printf '1\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" >"$TMP_DIR/run.out" 2>"$TMP_DIR/run.err"

assert_file_contains 'Selection:' "$TMP_DIR/run.err" 'run shows the interactive picker prompts'
assert_file_contains '--name opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run derives the workspace container name from the image suffix'
assert_file_contains '--userns keep-id' "$PODMAN_LOG" 'run keeps the container root user aligned to the host user namespace'
assert_file_contains '-w /workspace/project' "$PODMAN_LOG" 'run sets the project path as the working directory'
assert_file_contains '-p 14096:4096' "$PODMAN_LOG" 'run publishes the stable workspace server port derived from the offset'
assert_file_contains "$TMP_DIR/base/alpha/opencode-home:/root" "$PODMAN_LOG" 'run mounts the concrete host home path at /root'
assert_file_contains "$TMP_DIR/base/alpha/opencode-general:/workspace/general" "$PODMAN_LOG" 'run mounts the concrete host general path'
assert_file_contains "$TMP_DIR/development:/workspace/development" "$PODMAN_LOG" 'run mounts the development root'
assert_file_contains "$TMP_DIR/development/beta:/workspace/project" "$PODMAN_LOG" 'run mounts the selected project at the fixed project path'
assert_file_contains 'serve --hostname 0.0.0.0 --port 4096' "$PODMAN_LOG" 'run starts the long-lived upstream server mode inside the workspace container'
assert_file_contains 'exec -i opencode-alpha-1.4.3-20260418-120000-123 opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run attaches to the long-lived OpenCode server after the container is ready'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='old-version' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/version-bump.out" 2>"$TMP_DIR/version-bump.err"
assert_file_contains 'rm -f opencode-alpha-1.4.2-20260417-120000-123' "$PODMAN_LOG" 'run removes an older-version workspace container after the new container proves stable'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='prefix-collision' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/prefix-collision.out" 2>"$TMP_DIR/prefix-collision.err"
assert_file_contains 'ps -aq --format {{.Names}} --filter name=^opencode-alpha-[0-9]' "$PODMAN_LOG" 'run uses a workspace filter that does not collide with prefix-matching workspace names'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.ran" "${PODMAN_LOG}.started"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_RUNNING_MODE='stopped' OPENCODE_TEST_START_FAIL='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/start-fail.out" 2>"$TMP_DIR/start-fail.err"
assert_file_contains 'start opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run first attempts to start a stopped exact-match container'
assert_file_contains 'run -d --name opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run recovers from a failed start by recreating the canonical workspace container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha" bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-success.out" 2>"$TMP_DIR/project-change-success.err"
assert_file_contains 'run -d --name opencode-alpha-1.4.3-20260418-120000-123-next-' "$PODMAN_LOG" 'run stages a replacement container under a temporary name when the project mount changes'
assert_file_contains 'rename opencode-alpha-1.4.3-20260418-120000-123-next-' "$PODMAN_LOG" 'run renames a healthy staged replacement into the canonical workspace container name'
assert_file_contains 'rm -f opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run removes the old canonical workspace container only after the staged replacement is ready'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha" OPENCODE_TEST_RUN_FAIL='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-fail.out" 2>"$TMP_DIR/project-change-fail.err"; then
  fail 'run should fail when replacement creation fails during a project change'
fi
assert_file_not_contains 'rm -f opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run keeps the existing exact-match container until the replacement project container is proven viable'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.next-running-once"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha" OPENCODE_TEST_RUNNING_MODE='dies-before-attach' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-dies.out" 2>"$TMP_DIR/project-change-dies.err"; then
  fail 'run should fail when a staged replacement dies before attach during a project change'
fi
assert_file_not_contains 'rm -f opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run keeps the existing exact-match container when a staged replacement dies before attach'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse.out" 2>"$TMP_DIR/reuse.err"
assert_file_not_contains 'run -d --name opencode-alpha-1.4.3-20260418-120000-123' "$PODMAN_LOG" 'run reuses an exact matching container when the project mount already matches'
assert_file_contains 'exec -i opencode-alpha-1.4.3-20260418-120000-123 opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches to the long-lived server after reusing an exact matching container'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" gamma beta >"$TMP_DIR/unconfigured.out" 2>"$TMP_DIR/unconfigured.err"; then
  fail 'run should reject a workspace that is not configured'
fi

assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/unconfigured.err" 'run rejects unconfigured workspace arguments before container creation'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" .. beta >"$TMP_DIR/dotdot.out" 2>"$TMP_DIR/dotdot.err"; then
  fail 'run should reject dot-dot workspace arguments'
fi

assert_file_contains "Workspace name .. may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.' or '..'." "$TMP_DIR/dotdot.err" 'run rejects dot-dot workspace names before touching host paths'

: >"$CHOWN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_HOST_UID='0' OPENCODE_TEST_HOST_GID='0' SUDO_UID='4242' SUDO_GID='4343' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/root-run.out" 2>"$TMP_DIR/root-run.err"
assert_file_contains '-R 4242:4343' "$CHOWN_LOG" 'run restores caller ownership when sudo created the workspace mount directories'

: >"$CHOWN_LOG"
env -u SUDO_UID -u SUDO_GID PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_HOST_UID='0' OPENCODE_TEST_HOST_GID='0' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/root-nosudo.out" 2>"$TMP_DIR/root-nosudo.err"
assert_file_contains '-R 0:0' "$CHOWN_LOG" 'run preserves true root ownership when invoked directly as root without sudo metadata'

printf 'opencode-run behavior checks passed\n'
