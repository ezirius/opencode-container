#!/usr/bin/env bash

set -euo pipefail

# This test checks that the run script selects a workspace and project, then mounts the fixed OpenCode paths.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

CONFIG_PATH="$ROOT/config/agent/shared/opencode-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
cleanup_done=0

# This restores the shared config and temp files exactly once.
cleanup() {
  if [[ "$cleanup_done" == '1' ]]; then
    return 0
  fi
  cleanup_done=1
  cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  rm -rf "$TMP_DIR"
}

# This waits briefly for asynchronous log lines from detached browser opener processes.
wait_for_file_contains() {
  local needle="$1"
  local file_path="$2"
  local message="$3"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if grep -Fq -- "$needle" "$file_path"; then
      return 0
    fi
    /bin/sleep 0.1
  done

  fail "$message: missing [$needle] in $file_path"
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
    printf 'opencode-1.4.3-20260418-120000-123 3a9b2af6f1938c45f6c169c1949a1a071e90cdd9311cb2d182a82712d9474b9c\n'
    ;;
  ps)
    if [[ "${2-}" == '-aq' ]]; then
      if [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'present' ]]; then
        printf 'stale-1\nstale-2\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'prefix-collision' ]]; then
        printf 'opencode-1.4.3-20260417-120000-123-aaaaaaaaaaaa-alpha-prod\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'old-version' ]]; then
        printf 'opencode-1.4.2-20260417-120000-123-8f7e6d5c4b3a-alpha\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name' ]]; then
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'running' ]]; then
      if [[ "$*" == *'next-'* ]]; then
        next_name="$(printf '%s' "$*" | sed -n 's/.*name=^\(.*\)\$$/\1/p' | sed 's/\\\././g')"
        printf '%s\n' "$next_name"
      else
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'dies-before-attach' ]]; then
      if [[ "$*" == *'next-'* && ! -f "${OPENCODE_TEST_PODMAN_LOG}.next-running-once" ]]; then
        : >"${OPENCODE_TEST_PODMAN_LOG}.next-running-once"
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-999\n'
      elif [[ "$*" != *'next-'* ]]; then
        printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'stopped' ]]; then
      if [[ -f "${OPENCODE_TEST_PODMAN_LOG}.started" || -f "${OPENCODE_TEST_PODMAN_LOG}.ran" ]]; then
        if [[ "$*" == *'next-'* ]]; then
          next_name="$(printf '%s' "$*" | sed -n 's/.*name=^\(.*\)\$$/\1/p' | sed 's/\\\././g')"
          printf '%s\n' "$next_name"
        else
          printf 'opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha\n'
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
    if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
      printf 'attach %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
    fi
    printf 'mock exec\n'
    ;;
  inspect)
    if [[ "$*" == *'.State.Status'* ]]; then
      printf 'status=running running=true exit_code=0\n'
    elif [[ "$*" == *'{{range .Mounts}}'* ]]; then
      if [[ "${OPENCODE_TEST_INCLUDE_WORKSPACE_MOUNT:-1}" == '1' ]]; then
        printf '%s\n' "${OPENCODE_TEST_WORKSPACE_MOUNT:-/tmp/base/alpha/opencode-general} : /workspace/general"
      fi
      printf '%s\n' "${OPENCODE_TEST_PROJECT_MOUNT:-/tmp/development/beta} : /workspace/project"
    elif [[ "$*" == *'.NetworkSettings.Ports'* ]]; then
      if [[ -n "${OPENCODE_TEST_PUBLISHED_PORT:-}" ]]; then
        printf '4096/tcp %s\n' "$OPENCODE_TEST_PUBLISHED_PORT"
      fi
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

# This fake uname lets each test case choose the host OS.
cat >"$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${OPENCODE_TEST_UNAME:-Linux}"
EOF

# This fake open records browser-open requests from macOS hosts.
cat >"$FAKE_BIN/open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'open-start %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi

printf '%s\n' "$*" >>"$OPENCODE_TEST_OPEN_LOG"

if [[ "${OPENCODE_TEST_OPEN_BLOCK:-0}" == '1' ]]; then
  sleep 2
fi

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'open-done %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi
exit "${OPENCODE_TEST_OPEN_EXIT_CODE:-0}"
EOF

# This fake xdg-open records browser-open requests from Linux hosts.
cat >"$FAKE_BIN/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'xdg-open-start %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi

printf '%s\n' "$*" >>"$OPENCODE_TEST_XDG_OPEN_LOG"

if [[ "${OPENCODE_TEST_XDG_OPEN_BLOCK:-0}" == '1' ]]; then
  sleep 2
fi

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'xdg-open-done %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi
exit "${OPENCODE_TEST_XDG_OPEN_EXIT_CODE:-0}"
EOF

# This fake gio records Linux fallback browser-open requests.
cat >"$FAKE_BIN/gio" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'gio-start %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi

printf '%s\n' "$*" >>"$OPENCODE_TEST_GIO_LOG"

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'gio-done %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi
exit "${OPENCODE_TEST_GIO_EXIT_CODE:-0}"
EOF

# This fake curl records readiness probes and can fail before succeeding.
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPENCODE_TEST_EVENT_LOG:-}" ]]; then
  printf 'curl %s\n' "$*" >>"$OPENCODE_TEST_EVENT_LOG"
fi

printf '%s\n' "$*" >>"$OPENCODE_TEST_CURL_LOG"

attempt_file="${OPENCODE_TEST_CURL_LOG}.attempts"
attempt_count=0
if [[ -f "$attempt_file" ]]; then
  attempt_count="$(tr -d '\n' < "$attempt_file")"
fi
attempt_count="$((attempt_count + 1))"
printf '%s\n' "$attempt_count" >"$attempt_file"

if (( attempt_count <= ${OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS:-0} )); then
  exit 7
fi

printf '%s\n' 'ok'
EOF

# This fake sleep can be disabled so blocking opener tests stay fast.
cat >"$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${OPENCODE_TEST_DISABLE_SLEEP:-0}" == '1' ]]; then
  exit 0
fi

exec /bin/sleep "$@"
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/id" "$FAKE_BIN/chown" "$FAKE_BIN/uname" "$FAKE_BIN/open" "$FAKE_BIN/xdg-open" "$FAKE_BIN/gio" "$FAKE_BIN/curl" "$FAKE_BIN/sleep"

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
OPEN_LOG="$TMP_DIR/open.log"
XDG_OPEN_LOG="$TMP_DIR/xdg-open.log"
GIO_LOG="$TMP_DIR/gio.log"
CURL_LOG="$TMP_DIR/curl.log"
EVENT_LOG="$TMP_DIR/event.log"

: >"$OPEN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
: >"$CURL_LOG"

printf '1\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" bash "$ROOT/scripts/agent/shared/opencode-run" >"$TMP_DIR/run.out" 2>"$TMP_DIR/run.err"

assert_file_contains 'Selection:' "$TMP_DIR/run.err" 'run shows the interactive picker prompts'
# This checks that the default path reaches podman run without tripping over an empty publish argument expansion.
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run reaches podman run on the default non-publish path'
assert_file_contains '--name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run derives the workspace container name from the image name plus the short image id'
assert_file_contains '--userns keep-id' "$PODMAN_LOG" 'run keeps the container root user aligned to the host user namespace'
assert_file_contains '-w /workspace/project' "$PODMAN_LOG" 'run sets the project path as the working directory'
assert_file_not_contains '-p 14096:4096' "$PODMAN_LOG" 'run does not publish the stable workspace server port unless --publish is requested'
assert_file_contains "$TMP_DIR/base/alpha/opencode-home:/root" "$PODMAN_LOG" 'run mounts the concrete host home path at /root'
assert_file_contains "$TMP_DIR/base/alpha/opencode-general:/workspace/general" "$PODMAN_LOG" 'run mounts the concrete host general path'
assert_file_contains "$TMP_DIR/development:/workspace/development" "$PODMAN_LOG" 'run mounts the development root'
assert_file_contains "$TMP_DIR/development/beta:/workspace/project" "$PODMAN_LOG" 'run mounts the selected project at the fixed project path'
assert_file_contains 'serve --hostname 0.0.0.0 --port 4096' "$PODMAN_LOG" 'run starts the long-lived upstream server mode inside the workspace container'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run attaches to the long-lived OpenCode server after the container is ready'
test ! -s "$OPEN_LOG" || fail 'run does not open a browser on macOS unless --publish is requested'
test ! -s "$XDG_OPEN_LOG" || fail 'run does not open a browser on Linux unless --publish is requested'
test ! -s "$GIO_LOG" || fail 'run does not fall back to gio on Linux unless --publish is requested'
test ! -s "$CURL_LOG" || fail 'run does not probe the published browser URL unless --publish is requested'
assert_file_not_contains 'Published OpenCode server:' "$TMP_DIR/run.err" 'run does not print published access details unless --publish created or started a container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/publish.out" 2>"$TMP_DIR/publish.err"
assert_file_contains '-p 14096:4096' "$PODMAN_LOG" 'run publishes the stable workspace server port when --publish is requested'
assert_file_contains "$TMP_DIR/base/alpha/opencode-general:/workspace/general" "$PODMAN_LOG" 'run also mounts the general workspace path for published containers'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches to the long-lived OpenCode server when --publish is requested'
assert_file_contains 'Published OpenCode server: http://127.0.0.1:14096' "$TMP_DIR/publish.err" 'run prints the published URL when it creates a published container'
assert_file_contains 'Host port: 14096' "$TMP_DIR/publish.err" 'run prints the published host port when it creates a published container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='old-version' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/version-bump.out" 2>"$TMP_DIR/version-bump.err"
assert_file_contains 'rm -f opencode-1.4.2-20260417-120000-123-8f7e6d5c4b3a-alpha' "$PODMAN_LOG" 'run removes an older-version workspace container after the new container proves stable'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='prefix-collision' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/prefix-collision.out" 2>"$TMP_DIR/prefix-collision.err"
assert_file_contains '--filter name=^opencode-1\.4\.3-' "$PODMAN_LOG" 'run uses a workspace filter anchored by the workspace suffix so prefix-matching workspace names do not collide'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.ran" "${PODMAN_LOG}.started"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_RUNNING_MODE='stopped' OPENCODE_TEST_START_FAIL='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/start-fail.out" 2>"$TMP_DIR/start-fail.err"
assert_file_contains 'start opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run first attempts to start a stopped exact-match container'
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run recovers from a failed start by recreating the canonical workspace container'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${PODMAN_LOG}.ran" "${PODMAN_LOG}.started"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_RUNNING_MODE='stopped' OPENCODE_TEST_PUBLISHED_PORT='14096' OPENCODE_TEST_UNAME='Darwin' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/start-publish.out" 2>"$TMP_DIR/start-publish.err"
assert_file_contains 'start opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run starts a stopped exact-match published container when publish settings already match'
wait_for_file_contains 'http://127.0.0.1:14096' "$OPEN_LOG" 'run opens the published browser URL after starting a stopped published container'
assert_file_contains 'Published OpenCode server: http://127.0.0.1:14096' "$TMP_DIR/start-publish.err" 'run prints the published URL after starting a stopped published container'
assert_file_contains 'Host port: 14096' "$TMP_DIR/start-publish.err" 'run prints the published host port after starting a stopped published container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha" OPENCODE_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-success.out" 2>"$TMP_DIR/project-change-success.err"
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run stages a replacement container under a temporary name when the project mount changes'
assert_file_contains 'rename opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run renames a healthy staged replacement into the canonical workspace container name'
assert_file_contains 'rm -f opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run removes the old canonical workspace container only after the staged replacement is ready'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_RUN_FAIL='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-fail.out" 2>"$TMP_DIR/project-change-fail.err"; then
  fail 'run should fail when replacement creation fails during a project change'
fi
assert_file_not_contains 'rm -f opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run keeps the existing exact-match container until the replacement project container is proven viable'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.next-running-once"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_RUNNING_MODE='dies-before-attach' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-dies.out" 2>"$TMP_DIR/project-change-dies.err"; then
  fail 'run should fail when a staged replacement dies before attach during a project change'
fi
assert_file_not_contains 'rm -f opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run keeps the existing exact-match container when a staged replacement dies before attach'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse.out" 2>"$TMP_DIR/reuse.err"
assert_file_not_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha' "$PODMAN_LOG" 'run reuses an exact matching container when the project mount already matches'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches to the long-lived server after reusing an exact matching container'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-closed.out" 2>"$TMP_DIR/reuse-closed.err"
assert_file_not_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run reuses an exact matching non-published container when --publish is not requested'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/reuse-publish-mismatch.out" 2>"$TMP_DIR/reuse-publish-mismatch.err"
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run replaces an exact matching container when --publish is requested and the existing container has no published host port'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PUBLISHED_PORT='14096' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-unpublish-mismatch.out" 2>"$TMP_DIR/reuse-unpublish-mismatch.err"
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run replaces an exact matching container when the existing container still publishes a host port but --publish was not requested'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PUBLISHED_PORT='15000' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-wrong-port-mismatch.out" 2>"$TMP_DIR/reuse-wrong-port-mismatch.err"
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run replaces an exact matching container when the existing container publishes the server on a different host port but --publish was not requested'

: >"$PODMAN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$OPEN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PUBLISHED_PORT='14096' OPENCODE_TEST_UNAME='Darwin' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/reuse-publish.out" 2>"$TMP_DIR/reuse-publish.err"
assert_file_not_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run reuses an exact matching published container when the published port already matches'
test ! -s "$OPEN_LOG" || fail 'run does not reopen the browser when reusing an already-running published container'
test ! -s "$CURL_LOG" || fail 'run does not reprobe the published browser URL when reusing an already-running published container'
assert_file_not_contains 'Published OpenCode server:' "$TMP_DIR/reuse-publish.err" 'run does not reprint published access details when reusing an already-running published container'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_INCLUDE_WORKSPACE_MOUNT='0' OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-missing-general.out" 2>"$TMP_DIR/reuse-missing-general.err"
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run replaces an exact matching container when the general workspace mount is missing'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/wrong-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PUBLISHED_PORT='14096' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/reuse-wrong-general-publish.out" 2>"$TMP_DIR/reuse-wrong-general-publish.err"
assert_file_contains 'run -d --name opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha-next-' "$PODMAN_LOG" 'run replaces an exact matching published container when the general workspace mount points to the wrong host path'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that macOS waits for the published URL before opening the browser.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Darwin' OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/alpha/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/beta" bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/macos-open.out" 2>"$TMP_DIR/macos-open.err"
assert_file_contains '--connect-timeout 1 --max-time 1 http://127.0.0.1:14096' "$CURL_LOG" 'run bounds each published browser URL probe on Darwin hosts'
assert_file_contains 'http://127.0.0.1:14096' "$CURL_LOG" 'run probes the published browser URL before opening it on Darwin hosts'
wait_for_file_contains 'http://127.0.0.1:14096' "$OPEN_LOG" 'run opens the published browser URL on Darwin hosts'
assert_equals 'http://127.0.0.1:14096' "$(tr -d '\n' < "$OPEN_LOG")" 'run passes the published browser URL as the open command argument on Darwin hosts'
wait_for_file_contains 'open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts browser open after probing the published URL on Darwin hosts'
wait_for_file_contains 'open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run finishes browser open on Darwin hosts'
wait_for_file_contains 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" 'run still reaches attach alongside browser open on Darwin hosts'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches after opening the browser on Darwin hosts'
assert_file_contains 'Published OpenCode server: http://127.0.0.1:14096' "$TMP_DIR/macos-open.err" 'run prints the published URL when it creates a published Darwin container'
assert_file_contains 'Host port: 14096' "$TMP_DIR/macos-open.err" 'run prints the published host port when it creates a published Darwin container'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that attach starts before a blocking macOS browser opener finishes.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Darwin' OPENCODE_TEST_OPEN_BLOCK='1' OPENCODE_TEST_DISABLE_SLEEP='1' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/macos-open-blocking.out" 2>"$TMP_DIR/macos-open-blocking.err"
wait_for_file_contains 'open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts the blocking Darwin opener'
wait_for_file_contains 'open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run lets the blocking Darwin opener finish eventually'
wait_for_file_contains 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" 'run reaches attach during the blocking Darwin opener case'
macos_attach_line="$(grep -n 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
macos_open_done_line="$(grep -n 'open-done http://127.0.0.1:14096' "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
(( macos_attach_line < macos_open_done_line )) || fail 'run starts attach before the blocking Darwin opener finishes'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
# This checks that a failed browser launch does not break macOS attach.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_UNAME='Darwin' OPENCODE_TEST_OPEN_EXIT_CODE='1' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/macos-open-fail.out" 2>"$TMP_DIR/macos-open-fail.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$OPEN_LOG" 'run still attempts to open the published browser URL on Darwin hosts when open fails'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches after open fails on Darwin hosts'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
# This checks that attach still works when the published URL never becomes ready.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='99' OPENCODE_TEST_UNAME='Darwin' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/macos-not-ready.out" 2>"$TMP_DIR/macos-not-ready.err"
assert_file_contains 'http://127.0.0.1:14096' "$CURL_LOG" 'run keeps probing the published browser URL when it is not ready on Darwin hosts'
test ! -s "$OPEN_LOG" || fail 'run does not open the browser before the published URL becomes ready on Darwin hosts'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches when the published browser URL never becomes ready on Darwin hosts'

: >"$PODMAN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that Linux waits for readiness before opening the browser with xdg-open.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/linux-xdg-open.out" 2>"$TMP_DIR/linux-xdg-open.err"
assert_file_contains '--connect-timeout 1 --max-time 1 http://127.0.0.1:14096' "$CURL_LOG" 'run bounds each published browser URL probe on Linux hosts before xdg-open'
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run opens the published browser URL with xdg-open on Linux hosts'
test ! -s "$GIO_LOG" || fail 'run does not fall back to gio when xdg-open succeeds on Linux hosts'
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts xdg-open after probing the published URL on Linux hosts'
wait_for_file_contains 'xdg-open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run finishes xdg-open on Linux hosts'
wait_for_file_contains 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" 'run still reaches attach alongside xdg-open on Linux hosts'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches after xdg-open on Linux hosts'

: >"$PODMAN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that attach starts before a blocking Linux browser opener finishes.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_BLOCK='1' OPENCODE_TEST_DISABLE_SLEEP='1' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/linux-xdg-open-blocking.out" 2>"$TMP_DIR/linux-xdg-open-blocking.err"
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts the blocking Linux opener'
wait_for_file_contains 'xdg-open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run lets the blocking Linux opener finish eventually'
wait_for_file_contains 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" 'run reaches attach during the blocking Linux opener case'
linux_attach_line="$(grep -n 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
linux_open_done_line="$(grep -n 'xdg-open-done http://127.0.0.1:14096' "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
(( linux_attach_line < linux_open_done_line )) || fail 'run starts attach before the blocking Linux opener finishes'

: >"$PODMAN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that Linux falls back to gio open when xdg-open is unavailable.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_EXIT_CODE='127' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/linux-gio-fallback.out" 2>"$TMP_DIR/linux-gio-fallback.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run first tries xdg-open before Linux fallback'
wait_for_file_contains 'open http://127.0.0.1:14096' "$GIO_LOG" 'run falls back to gio open for the published browser URL on Linux hosts'
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run first tries xdg-open before Linux fallback'
wait_for_file_contains 'gio-start open http://127.0.0.1:14096' "$EVENT_LOG" 'run falls back to gio after xdg-open on Linux hosts'
wait_for_file_contains 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" 'run still reaches attach after gio fallback on Linux hosts'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches after gio fallback on Linux hosts'

: >"$PODMAN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that Linux also falls back when xdg-open exists but fails.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_EXIT_CODE='1' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/linux-gio-after-fail.out" 2>"$TMP_DIR/linux-gio-after-fail.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run still tries xdg-open before Linux fallback when xdg-open fails'
wait_for_file_contains 'open http://127.0.0.1:14096' "$GIO_LOG" 'run falls back to gio open when xdg-open fails on Linux hosts'
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run still tries xdg-open before Linux fallback when xdg-open fails'
wait_for_file_contains 'gio-start open http://127.0.0.1:14096' "$EVENT_LOG" 'run falls back to gio after failed xdg-open on Linux hosts'
wait_for_file_contains 'attach exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$EVENT_LOG" 'run still reaches attach after failed xdg-open fallback on Linux hosts'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches after failed xdg-open fallback on Linux hosts'

: >"$PODMAN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
# This checks that Linux attach still works when every browser opener fails.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_EXIT_CODE='127' OPENCODE_TEST_GIO_EXIT_CODE='1' bash "$ROOT/scripts/agent/shared/opencode-run" --publish alpha beta >"$TMP_DIR/linux-open-fail.out" 2>"$TMP_DIR/linux-open-fail.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run still attempts xdg-open on Linux hosts when all browser launchers fail'
wait_for_file_contains 'open http://127.0.0.1:14096' "$GIO_LOG" 'run still attempts gio open on Linux hosts when xdg-open is unavailable'
assert_file_contains 'exec -i opencode-1.4.3-20260418-120000-123-3a9b2af6f193-alpha opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run still attaches when Linux browser launchers fail'

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

# This restores the shared config before the test reports success.
cleanup
trap - EXIT

printf 'opencode-run behavior checks passed\n'
