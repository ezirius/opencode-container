#!/usr/bin/env bash

set -euo pipefail

# This test checks that the run script selects a workspace and project, then mounts the fixed OpenCode paths.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

CONFIG_PATH="$ROOT/config/agent/shared/opencode-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
TEST_HOME="$TMP_DIR/home"
DEVELOPMENT_ROOT="$TEST_HOME/development"
cleanup_done=0
IMAGE_ID='1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
IMAGE_NAME="opencode-1.14.21-20260418-120000-${IMAGE_ID}"
OLD_IMAGE_NAME='opencode-1.14.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321'

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
names_file="${OPENCODE_TEST_PODMAN_LOG}.names"

# This keeps shared runtime state separate from project container state.
shared_name="opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha"
shared_mode="${OPENCODE_TEST_SHARED_MODE:-absent}"
shared_running_mode="${OPENCODE_TEST_SHARED_RUNNING_MODE:-$shared_mode}"

  case "$1" in
  images)
    printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef\n'
    ;;
  ps)
    if [[ "${2-}" == '-aq' ]]; then
      if [[ "$shared_mode" == 'running' || "$shared_mode" == 'stopped' ]]; then
        printf '%s\n' "$shared_name"
      fi
      if [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'present' ]]; then
        printf 'stale-1\nstale-2\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'prefix-collision' ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-prod-beta\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'project-workspace-collision' ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-beta-alpha-prod\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-workspace-different-project' ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-alpha\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'old-version' ]]; then
        printf 'opencode-1.14.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321-alpha-beta\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name' ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name-with-stale' ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
        printf 'opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-legacy\n'
      elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name-with-same-project-sibling' ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
        printf 'opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'running' ]]; then
      ps_args="$*"
      name_filter=''
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --filter)
            name_filter="$2"
            shift 2
            ;;
          *)
            shift
            ;;
        esac
      done

      normalized_filter="$name_filter"
      normalized_filter="${normalized_filter#name=^}"
      normalized_filter="${normalized_filter%\$}"
      normalized_filter="$(printf '%s' "$normalized_filter" | sed 's/\\\././g')"

      if [[ "$shared_running_mode" == 'running' ]]; then
        if [[ -z "$name_filter" || "$normalized_filter" == 'opencode-' || "$normalized_filter" == "$shared_name" ]]; then
          printf '%s\n' "$shared_name"
        fi
      fi

      if [[ "$ps_args" == *'next-'* ]]; then
        next_name="$(printf '%s' "$ps_args" | sed -n 's/.*name=^\(.*\)\$$/\1/p' | sed 's/\\\././g')"
        printf '%s\n' "$next_name"
       elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name' || "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name-with-stale' ]]; then
         if [[ -z "$name_filter" || "$name_filter" == 'name=^opencode-'* || "$name_filter" == 'name=^opencode-1\.14\.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta$' ]]; then
           printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
         fi
       elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-name-with-same-project-sibling' ]]; then
         if [[ "$name_filter" == 'name=^opencode-1\.14\.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta$' ]]; then
           printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
         elif [[ "$name_filter" == 'name=^opencode-1\.13\.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta$' ]]; then
           printf 'opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta\n'
         elif [[ -z "$name_filter" || "$name_filter" == 'name=^opencode-'* ]]; then
           printf 'opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta\n'
           printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
         fi
       elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'same-workspace-different-project' ]]; then
         printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-alpha\n'
       elif [[ "${OPENCODE_TEST_STALE_MODE:-present}" == 'old-version' ]]; then
        if [[ -z "$name_filter" || "$name_filter" == 'name=^opencode-'* || "$name_filter" == 'name=^opencode-1\.14\.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321-alpha-beta$' ]]; then
          printf 'opencode-1.14.20-20260417-120000-fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321-alpha-beta\n'
        fi
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'dies-before-attach' ]]; then
      if [[ "$*" == *'next-'* && ! -f "${OPENCODE_TEST_PODMAN_LOG}.next-running-once" ]]; then
        : >"${OPENCODE_TEST_PODMAN_LOG}.next-running-once"
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta-next-999\n'
      elif [[ "$*" != *'next-'* ]]; then
        printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
      fi
    elif [[ "${OPENCODE_TEST_RUNNING_MODE:-running}" == 'stopped' ]]; then
      if [[ -f "${OPENCODE_TEST_PODMAN_LOG}.started" || -f "${OPENCODE_TEST_PODMAN_LOG}.ran" ]]; then
        if [[ "$*" == *'next-'* ]]; then
          next_name="$(printf '%s' "$*" | sed -n 's/.*name=^\(.*\)\$$/\1/p' | sed 's/\\\././g')"
          printf '%s\n' "$next_name"
        else
          printf 'opencode-1.14.21-20260418-120000-1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef-alpha-beta\n'
        fi
      fi
    fi
    ;;
  run)
    container_name=''
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name)
          container_name="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    if [[ -n "$container_name" ]] && grep -Fqx -- "$container_name" "$names_file" 2>/dev/null; then
      exit 125
    fi

    if [[ "${OPENCODE_TEST_PREEXISTING_NEXT:-0}" == '1' && "$container_name" == *'-next-'* && ! -f "${OPENCODE_TEST_PODMAN_LOG}.cleaned-next" ]]; then
      exit 125
    fi

    if [[ "${OPENCODE_TEST_RUN_FAIL:-0}" == '1' ]]; then
      exit 1
    fi

    if [[ -n "$container_name" ]]; then
      printf '%s\n' "$container_name" >>"$names_file"
      if [[ "$container_name" == "$shared_name" ]]; then
        shared_mode='running'
        shared_running_mode='running'
      fi
    fi

    if [[ "$container_name" != "$shared_name" ]]; then
      : >"${OPENCODE_TEST_PODMAN_LOG}.ran"
    fi
    printf 'new-container\n'
    ;;
  rename)
    if [[ $# -ge 3 ]]; then
      old_name="$2"
      new_name="$3"
      if [[ -f "$names_file" ]]; then
        grep -Fvx -- "$old_name" "$names_file" >"${names_file}.tmp" || true
        mv "${names_file}.tmp" "$names_file"
      fi
      printf '%s\n' "$new_name" >>"$names_file"
    fi
    : >"${OPENCODE_TEST_PODMAN_LOG}.renamed"
    ;;
  rm)
    removed_next=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -*) shift ;;
        *)
          if [[ -f "$names_file" ]]; then
            grep -Fvx -- "$1" "$names_file" >"${names_file}.tmp" || true
            mv "${names_file}.tmp" "$names_file"
          fi
          if [[ "$1" == *'-next-'* ]]; then
            removed_next=1
          fi
          shift
          ;;
      esac
    done
    if [[ "$removed_next" == '1' ]]; then
      : >"${OPENCODE_TEST_PODMAN_LOG}.cleaned-next"
    fi
    ;;
  start)
    if [[ "${OPENCODE_TEST_START_FAIL:-0}" == '1' ]]; then
      exit 1
    fi
    if [[ "${2-}" == "$shared_name" ]]; then
      shared_running_mode='running'
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
      container_name="${@: -1}"
      workspace_mount="${OPENCODE_TEST_WORKSPACE_MOUNT:-}"
      project_mount="${OPENCODE_TEST_PROJECT_MOUNT:-}"

      if [[ "$container_name" == "$shared_name" ]]; then
        printf '%s\n' "$OPENCODE_TEST_DEVELOPMENT_ROOT : /workspace/projects"
      elif [[ -z "$workspace_mount" || -z "$project_mount" ]]; then
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
  /bin/sleep 0.2
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
  /bin/sleep 0.2
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
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_IMAGE_REPOSITORY="ghcr.io/anomalyco/opencode"
OPENCODE_VERSION="1.14.21"
OPENCODE_TARGET_ARCH="arm64"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="~/development"
OPENCODE_WORKSPACES="alpha:10000 alpha-prod:15000 beta:20000"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/general"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECTS="/workspace/projects"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-general"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="sh"
EOF

export HOME="$TEST_HOME"
mkdir -p "$DEVELOPMENT_ROOT/alpha" "$DEVELOPMENT_ROOT/beta" "$DEVELOPMENT_ROOT/my project"

PODMAN_LOG="$TMP_DIR/podman.log"
CHOWN_LOG="$TMP_DIR/chown.log"
OPEN_LOG="$TMP_DIR/open.log"
XDG_OPEN_LOG="$TMP_DIR/xdg-open.log"
GIO_LOG="$TMP_DIR/gio.log"
CURL_LOG="$TMP_DIR/curl.log"
EVENT_LOG="$TMP_DIR/event.log"
export OPENCODE_TEST_BASE_PATH="$TMP_DIR/base"
export OPENCODE_TEST_DEVELOPMENT_ROOT="$DEVELOPMENT_ROOT"

: >"$OPEN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
: >"$CURL_LOG"

latest_image="$(PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; opencode_latest_image')"
assert_equals "$IMAGE_NAME" "$latest_image" 'run helper accepts the full image id naming contract when resolving the newest local image'

nullglob_state="$(ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; shopt -s nullglob; project_names_from_development_root >/dev/null; shopt -p nullglob')"
assert_equals 'shopt -s nullglob' "$nullglob_state" 'run helper preserves an already enabled nullglob shell option after project discovery'

shared_runtime_name="${IMAGE_NAME}-alpha"

# This checks the shared runtime helper contract before lifecycle behavior changes land.
shared_container_name="$(ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; opencode_shared_container_name "$1" "$2"' _ "$IMAGE_NAME" alpha)"
assert_equals "${IMAGE_NAME}-alpha" "$shared_container_name" 'run helper derives one shared runtime container name per workspace'

shared_projects_mount="$(ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; opencode_shared_projects_mount_spec' )"
assert_equals "$DEVELOPMENT_ROOT:/workspace/projects" "$shared_projects_mount" 'run helper mounts the expanded host development root at the shared projects path'

shared_publish_spec="$(ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; opencode_shared_container_publish_spec alpha')"
assert_equals '14096:4096' "$shared_publish_spec" 'run helper always publishes the stable workspace port for shared runtime containers'

project_publish_spec="$(ROOT="$ROOT" bash -c 'source "$ROOT/lib/shell/shared/common.sh"; opencode_project_container_publish_spec alpha')"
assert_equals '' "$project_publish_spec" 'run helper never publishes ports for project containers'

printf '1\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" >"$TMP_DIR/run.out" 2>"$TMP_DIR/run.err"

assert_file_contains 'Selection:' "$TMP_DIR/run.err" 'run shows the interactive picker prompts'
assert_file_contains "Creating shared runtime container: ${shared_runtime_name}" "$TMP_DIR/run.err" 'run reports when it creates the shared runtime container for a workspace'
assert_file_contains "Creating new container: ${IMAGE_NAME}-alpha-beta" "$TMP_DIR/run.err" 'run reports when it creates a new canonical workspace container through the staged path'
assert_file_contains "run -d --name ${shared_runtime_name}" "$PODMAN_LOG" 'run creates the shared runtime container before handling the project container'
assert_file_contains '-p 14096:4096' "$PODMAN_LOG" 'run publishes the stable workspace server port from the shared runtime container by default'
assert_file_contains "$DEVELOPMENT_ROOT:/workspace/projects" "$PODMAN_LOG" 'run mounts the expanded development root at the shared runtime projects path'
assert_file_contains "Promoting new container: ${IMAGE_NAME}-alpha-beta-next-" "$TMP_DIR/run.err" 'run reports when it promotes a healthy staged container into the canonical workspace name'
# This checks that the default path reaches podman run with published ports enabled.
assert_file_contains 'images --sort created --format {{.Repository}}' "$PODMAN_LOG" 'run looks up the newest locally built image before starting a workspace'
assert_file_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run stages a newly created workspace container under a temporary name on the default path'
assert_file_contains "rename ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run renames a healthy staged default-path container into the canonical name'
assert_file_contains "--name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run derives the staged container name from the canonical container name plus a temporary pid suffix during creation'
assert_file_not_contains '--arch arm64' "$PODMAN_LOG" 'run does not pass a separate runtime arch flag when using the built local image'
assert_file_contains "$IMAGE_NAME" "$PODMAN_LOG" 'run uses the newest locally built OpenCode image'
assert_file_contains '--userns keep-id' "$PODMAN_LOG" 'run keeps the container root user aligned to the host user namespace'
assert_file_contains '-w /workspace/project' "$PODMAN_LOG" 'run sets the project path as the working directory'
assert_file_not_contains '-w /workspace/project -p 14096:4096' "$PODMAN_LOG" 'run never publishes ports from the project container'
assert_file_contains "$TMP_DIR/base/alpha/opencode-home:/root" "$PODMAN_LOG" 'run mounts the concrete host home path at /root'
assert_file_contains "$TMP_DIR/base/alpha/opencode-general:/workspace/general" "$PODMAN_LOG" 'run mounts the concrete host general path'
assert_file_contains "$DEVELOPMENT_ROOT:/workspace/development" "$PODMAN_LOG" 'run mounts the expanded development root'
assert_file_contains "$DEVELOPMENT_ROOT/beta:/workspace/project" "$PODMAN_LOG" 'run mounts the selected project at the fixed project path'
assert_file_contains 'serve --hostname 0.0.0.0 --port 4096' "$PODMAN_LOG" 'run starts the long-lived upstream server mode inside the workspace container'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run attaches to the long-lived OpenCode server after the container is ready'
assert_file_contains 'http://127.0.0.1:14096' "$CURL_LOG" 'run probes the published browser URL by default'
assert_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run opens the published browser URL by default on Linux hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
# This checks that invalid picker input stays in the loop until a valid choice arrives.
printf '0\n1\ngamma\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" >"$TMP_DIR/retry.out" 2>"$TMP_DIR/retry.err"
assert_file_contains 'Please pick one of the configured workspaces.' "$TMP_DIR/retry.err" 'run retries workspace selection after out-of-range input'
assert_file_contains 'Please pick one of the discovered projects.' "$TMP_DIR/retry.err" 'run retries project selection after invalid input'
assert_file_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run still creates the requested container after picker retries'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
# This checks that q is the only interactive quit key during project selection.
if printf '1\nnope\nq\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" >"$TMP_DIR/project-quit.out" 2>"$TMP_DIR/project-quit.err"; then
  fail 'run should let q cancel project selection'
fi
assert_file_contains 'Please pick one of the discovered projects.' "$TMP_DIR/project-quit.err" 'run does not treat other project input as a quit request'
assert_file_contains 'Selection cancelled.' "$TMP_DIR/project-quit.err" 'run reports an explicit cancel when q quits project selection'
assert_file_not_contains 'run -d --name' "$PODMAN_LOG" 'run does not create containers when q cancels project selection'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
# This checks that EOF during interactive selection fails with a clean message.
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" >"$TMP_DIR/project-eof.out" 2>"$TMP_DIR/project-eof.err"; then
  fail 'run should fail cleanly when project selection hits EOF'
fi
assert_file_contains 'Selection aborted.' "$TMP_DIR/project-eof.err" 'run reports a clean EOF failure during project selection'
assert_file_not_contains 'run -d --name' "$PODMAN_LOG" 'run does not create containers when project selection hits EOF'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_SHARED_MODE='stopped' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/shared-start.out" 2>"$TMP_DIR/shared-start.err"
assert_file_contains "Starting shared runtime container: ${shared_runtime_name}" "$TMP_DIR/shared-start.err" 'run starts the existing shared runtime container when it is present but stopped'
assert_file_contains "start ${shared_runtime_name}" "$PODMAN_LOG" 'run starts the stopped shared runtime container before attaching the project container'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_SHARED_MODE='running' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/shared-reuse.out" 2>"$TMP_DIR/shared-reuse.err"
assert_file_not_contains "run -d --name ${shared_runtime_name} --userns keep-id -w /workspace/general" "$PODMAN_LOG" 'run does not recreate a running shared runtime container'

: >"$PODMAN_LOG"
: >"$OPEN_LOG"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
: >"$CURL_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" --no-ports alpha beta >"$TMP_DIR/no-ports.out" 2>"$TMP_DIR/no-ports.err"; then
  fail 'run should reject the removed --no-ports flag'
fi
assert_file_contains 'Unsupported option: --no-ports' "$TMP_DIR/no-ports.err" 'run rejects the removed --no-ports flag'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='old-version' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/version-bump.out" 2>"$TMP_DIR/version-bump.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not replace a running canonical container just because a newer image exists'
assert_file_not_contains "rm -f ${OLD_IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run keeps the existing canonical container when only the image drifts'
assert_file_contains "exec -i ${OLD_IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run attaches to the sticky canonical container even when its image name no longer matches the newest local image'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='prefix-collision' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/prefix-collision.out" 2>"$TMP_DIR/prefix-collision.err"
assert_file_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run ignores a different hyphenated workspace container with a colliding name prefix and still stages the new container first'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
rm -f "${PODMAN_LOG}.cleaned-next"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_PREEXISTING_NEXT='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/preexisting-next.out" 2>"$TMP_DIR/preexisting-next.err"
assert_file_contains "rm -f ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run removes a stale staged container name before creating a new staged container'
assert_file_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run retries staged creation cleanly after clearing a stale staged container name'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='project-workspace-collision' OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/beta/opencode-general" OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/alpha-prod" bash "$ROOT/scripts/agent/shared/opencode-run" alpha-prod alpha >"$TMP_DIR/project-workspace-collision.out" 2>"$TMP_DIR/project-workspace-collision.err"
assert_file_not_contains "rm -f ${IMAGE_NAME}-beta-alpha-prod" "$PODMAN_LOG" 'run does not remove a different workspace container when a project token matches the requested workspace name'
assert_file_contains "run -d --name ${IMAGE_NAME}-alpha-prod-alpha-next-" "$PODMAN_LOG" 'run creates the requested workspace container even when another workspace uses the same project token by staging it first'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-workspace-different-project' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/alpha" bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/same-workspace-different-project.out" 2>"$TMP_DIR/same-workspace-different-project.err"
assert_file_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run creates the requested canonical project container instead of reusing a different running project from the same workspace'
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-alpha opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run does not attach to a different running project container from the same workspace'
assert_file_not_contains "rm -f ${IMAGE_NAME}-alpha-alpha" "$PODMAN_LOG" 'run leaves the other project container in the same workspace alone during canonical project selection'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
rm -f "${PODMAN_LOG}.ran" "${PODMAN_LOG}.started"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='14096' OPENCODE_TEST_RUNNING_MODE='stopped' OPENCODE_TEST_START_FAIL='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/start-fail.out" 2>"$TMP_DIR/start-fail.err"; then
  fail 'run should fail cleanly when the canonical container exists but podman start fails'
fi
assert_file_contains "start ${IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run first attempts to start a stopped exact-match container'
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not stage a replacement when starting the canonical container fails'
assert_file_not_contains "rename ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not rename a replacement into the canonical name after a failed canonical start'
assert_file_not_contains "rm -f ${IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run keeps the canonical container untouched when its start fails'
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run does not attach after a failed canonical start'
assert_file_contains 'OpenCode container failed to stay running' "$TMP_DIR/start-fail.err" 'run reports the failed canonical startup through the existing diagnostics path'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/alpha" bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-success.out" 2>"$TMP_DIR/project-change-success.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not stage a replacement when the canonical container has a different project mount'
assert_file_not_contains "rm -f ${IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run keeps the existing canonical container when only the project mount drifts'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches to the sticky canonical container when the project mount drifts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_SHARED_MODE='running' OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/alpha" OPENCODE_TEST_RUN_FAIL='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-fail.out" 2>"$TMP_DIR/project-change-fail.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not try to create a replacement when project drift exists'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run is unaffected by replacement-create failures because sticky project drift does not create replacements'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
rm -f "${PODMAN_LOG}.next-running-once"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/alpha" OPENCODE_TEST_RUNNING_MODE='dies-before-attach' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/project-change-dies.out" 2>"$TMP_DIR/project-change-dies.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not create a staged replacement when project drift exists'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run stays attached to the sticky canonical container instead of depending on a replacement startup'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='14096' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse.out" 2>"$TMP_DIR/reuse.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run reuses an exact matching container when the project mount already matches'
assert_file_contains "Reusing running container: ${IMAGE_NAME}-alpha-beta" "$TMP_DIR/reuse.err" 'run reports when it reuses an already running canonical container'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches to the long-lived server after reusing an exact matching container'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name-with-stale' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='14096' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-cleanup.out" 2>"$TMP_DIR/reuse-cleanup.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run still reuses the exact matching container when stale siblings exist'
assert_file_not_contains 'rm -f opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-legacy' "$PODMAN_LOG" 'run leaves stale sibling project containers alone when reusing the canonical container'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name-with-same-project-sibling' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='14096' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-canonical-priority.out" 2>"$TMP_DIR/reuse-canonical-priority.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run does not stage a replacement when the running canonical container already exists beside a same-project sibling'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run prefers the exact canonical container over a same-project running sibling'
assert_file_not_contains 'exec -i opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run does not attach to a same-project sibling when the exact canonical container is already running'
assert_file_not_contains 'rm -f opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta' "$PODMAN_LOG" 'run leaves same-project siblings untouched when the canonical container is already running'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
rm -f "${PODMAN_LOG}.started"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name-with-same-project-sibling' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='14096' OPENCODE_TEST_RUNNING_MODE='stopped' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-stopped-canonical-priority.out" 2>"$TMP_DIR/reuse-stopped-canonical-priority.err"
assert_file_contains "start ${IMAGE_NAME}-alpha-beta" "$PODMAN_LOG" 'run starts the stopped canonical container even when a same-project sibling is already running'
assert_file_contains "Starting existing container: ${IMAGE_NAME}-alpha-beta" "$TMP_DIR/reuse-stopped-canonical-priority.err" 'run reports when it starts a stopped canonical container'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run attaches to the canonical container after starting it'
assert_file_not_contains 'exec -i opencode-1.13.99-20260401-010101-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-alpha-beta opencode attach http://127.0.0.1:4096' "$PODMAN_LOG" 'run does not fall back to a same-project sibling when the canonical container exists but is stopped'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$OPEN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='14096' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-published.out" 2>"$TMP_DIR/reuse-published.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run reuses an exact matching published container when the project mount already matches'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-publish-mismatch.out" 2>"$TMP_DIR/reuse-publish-mismatch.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run keeps the canonical container when default publish mode drifts from the existing container'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches to the sticky canonical container when it does not publish the default host port'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_STALE_MODE='same-name' OPENCODE_TEST_PROJECT_MOUNT="$DEVELOPMENT_ROOT/beta" OPENCODE_TEST_PUBLISHED_PORT='15000' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/reuse-wrong-port-mismatch.out" 2>"$TMP_DIR/reuse-wrong-port-mismatch.err"
assert_file_not_contains "run -d --name ${IMAGE_NAME}-alpha-beta-next-" "$PODMAN_LOG" 'run keeps the canonical container when it publishes a different host port than the default one'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches to the sticky canonical container when the published host port drifts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that macOS waits for the published URL before opening the browser.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Darwin' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/macos-open.out" 2>"$TMP_DIR/macos-open.err"
assert_file_contains '--connect-timeout 1 --max-time 1 http://127.0.0.1:14096' "$CURL_LOG" 'run bounds each published browser URL probe on Darwin hosts'
assert_file_contains 'http://127.0.0.1:14096' "$CURL_LOG" 'run probes the published browser URL before opening it on Darwin hosts'
wait_for_file_contains 'http://127.0.0.1:14096' "$OPEN_LOG" 'run opens the published browser URL on Darwin hosts'
assert_equals 'http://127.0.0.1:14096' "$(tr -d '\n' < "$OPEN_LOG")" 'run passes the published browser URL as the open command argument on Darwin hosts'
wait_for_file_contains 'open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts browser open after probing the published URL on Darwin hosts'
wait_for_file_contains 'open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run finishes browser open on Darwin hosts'
wait_for_file_contains "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" 'run still reaches attach alongside browser open on Darwin hosts'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches after opening the browser on Darwin hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that attach starts before a blocking macOS browser opener finishes.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Darwin' OPENCODE_TEST_OPEN_BLOCK='1' OPENCODE_TEST_DISABLE_SLEEP='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/macos-open-blocking.out" 2>"$TMP_DIR/macos-open-blocking.err"
wait_for_file_contains 'open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts the blocking Darwin opener'
wait_for_file_contains 'open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run lets the blocking Darwin opener finish eventually'
wait_for_file_contains "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" 'run reaches attach during the blocking Darwin opener case'
macos_attach_line="$(grep -n "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
macos_open_done_line="$(grep -n 'open-done http://127.0.0.1:14096' "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
(( macos_attach_line < macos_open_done_line )) || fail 'run starts attach before the blocking Darwin opener finishes'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
# This checks that a failed browser launch does not break macOS attach.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_UNAME='Darwin' OPENCODE_TEST_OPEN_EXIT_CODE='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/macos-open-fail.out" 2>"$TMP_DIR/macos-open-fail.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$OPEN_LOG" 'run still attempts to open the published browser URL on Darwin hosts when open fails'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches after open fails on Darwin hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$OPEN_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
# This checks that attach still works when the published URL never becomes ready.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_OPEN_LOG="$OPEN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='99' OPENCODE_TEST_UNAME='Darwin' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/macos-not-ready.out" 2>"$TMP_DIR/macos-not-ready.err"
assert_file_contains 'http://127.0.0.1:14096' "$CURL_LOG" 'run keeps probing the published browser URL when it is not ready on Darwin hosts'
test ! -s "$OPEN_LOG" || fail 'run does not open the browser before the published URL becomes ready on Darwin hosts'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches when the published browser URL never becomes ready on Darwin hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that Linux waits for readiness before opening the browser with xdg-open.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/linux-xdg-open.out" 2>"$TMP_DIR/linux-xdg-open.err"
assert_file_contains '--connect-timeout 1 --max-time 1 http://127.0.0.1:14096' "$CURL_LOG" 'run bounds each published browser URL probe on Linux hosts before xdg-open'
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run opens the published browser URL with xdg-open on Linux hosts'
test ! -s "$GIO_LOG" || fail 'run does not fall back to gio when xdg-open succeeds on Linux hosts'
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts xdg-open after probing the published URL on Linux hosts'
wait_for_file_contains 'xdg-open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run finishes xdg-open on Linux hosts'
wait_for_file_contains "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" 'run still reaches attach alongside xdg-open on Linux hosts'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches after xdg-open on Linux hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that attach starts before a blocking Linux browser opener finishes.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_BLOCK='1' OPENCODE_TEST_DISABLE_SLEEP='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/linux-xdg-open-blocking.out" 2>"$TMP_DIR/linux-xdg-open-blocking.err"
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run starts the blocking Linux opener'
wait_for_file_contains 'xdg-open-done http://127.0.0.1:14096' "$EVENT_LOG" 'run lets the blocking Linux opener finish eventually'
wait_for_file_contains "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" 'run reaches attach during the blocking Linux opener case'
linux_attach_line="$(grep -n "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
linux_open_done_line="$(grep -n 'xdg-open-done http://127.0.0.1:14096' "$EVENT_LOG" | cut -d: -f1 | head -n 1)"
(( linux_attach_line < linux_open_done_line )) || fail 'run starts attach before the blocking Linux opener finishes'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that Linux falls back to gio open when xdg-open is unavailable.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_EXIT_CODE='127' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/linux-gio-fallback.out" 2>"$TMP_DIR/linux-gio-fallback.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run first tries xdg-open before Linux fallback'
wait_for_file_contains 'open http://127.0.0.1:14096' "$GIO_LOG" 'run falls back to gio open for the published browser URL on Linux hosts'
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run first tries xdg-open before Linux fallback'
wait_for_file_contains 'gio-start open http://127.0.0.1:14096' "$EVENT_LOG" 'run falls back to gio after xdg-open on Linux hosts'
wait_for_file_contains "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" 'run still reaches attach after gio fallback on Linux hosts'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches after gio fallback on Linux hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
: >"$EVENT_LOG"
# This checks that Linux also falls back when xdg-open exists but fails.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_EVENT_LOG="$EVENT_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_EXIT_CODE='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/linux-gio-after-fail.out" 2>"$TMP_DIR/linux-gio-after-fail.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run still tries xdg-open before Linux fallback when xdg-open fails'
wait_for_file_contains 'open http://127.0.0.1:14096' "$GIO_LOG" 'run falls back to gio open when xdg-open fails on Linux hosts'
wait_for_file_contains 'xdg-open-start http://127.0.0.1:14096' "$EVENT_LOG" 'run still tries xdg-open before Linux fallback when xdg-open fails'
wait_for_file_contains 'gio-start open http://127.0.0.1:14096' "$EVENT_LOG" 'run falls back to gio after failed xdg-open on Linux hosts'
wait_for_file_contains "attach exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$EVENT_LOG" 'run still reaches attach after failed xdg-open fallback on Linux hosts'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches after failed xdg-open fallback on Linux hosts'

: >"$PODMAN_LOG"
rm -f "${PODMAN_LOG}.names"
: >"$XDG_OPEN_LOG"
: >"$GIO_LOG"
rm -f "${CURL_LOG}.attempts"
: >"$CURL_LOG"
# This checks that Linux attach still works when every browser opener fails.
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_XDG_OPEN_LOG="$XDG_OPEN_LOG" OPENCODE_TEST_GIO_LOG="$GIO_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_CURL_FAILS_BEFORE_SUCCESS='1' OPENCODE_TEST_UNAME='Linux' OPENCODE_TEST_XDG_OPEN_EXIT_CODE='127' OPENCODE_TEST_GIO_EXIT_CODE='1' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/linux-open-fail.out" 2>"$TMP_DIR/linux-open-fail.err"
wait_for_file_contains 'http://127.0.0.1:14096' "$XDG_OPEN_LOG" 'run still attempts xdg-open on Linux hosts when all browser launchers fail'
wait_for_file_contains 'open http://127.0.0.1:14096' "$GIO_LOG" 'run still attempts gio open on Linux hosts when xdg-open is unavailable'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode attach http://127.0.0.1:4096" "$PODMAN_LOG" 'run still attaches when Linux browser launchers fail'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" gamma beta >"$TMP_DIR/unconfigured.out" 2>"$TMP_DIR/unconfigured.err"; then
  fail 'run should reject a workspace that is not configured'
fi

assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/unconfigured.err" 'run rejects unconfigured workspace arguments before container creation'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" alpha 'my project' >"$TMP_DIR/spaced-project.out" 2>"$TMP_DIR/spaced-project.err"; then
  fail 'run should reject project names that are unsafe for container naming'
fi

assert_file_contains 'project name my project may only contain letters, numbers, dots, underscores, and hyphens' "$TMP_DIR/spaced-project.err" 'run rejects unsafe project names before container creation'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" bash "$ROOT/scripts/agent/shared/opencode-run" .. beta >"$TMP_DIR/dotdot.out" 2>"$TMP_DIR/dotdot.err"; then
  fail 'run should reject dot-dot workspace arguments'
fi

assert_file_contains "Workspace name .. may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.' or '..'." "$TMP_DIR/dotdot.err" 'run rejects dot-dot workspace names before touching host paths'

: >"$CHOWN_LOG"
rm -f "${PODMAN_LOG}.names"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_HOST_UID='0' OPENCODE_TEST_HOST_GID='0' SUDO_UID='4242' SUDO_GID='4343' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/root-run.out" 2>"$TMP_DIR/root-run.err"
assert_file_contains '-R 4242:4343' "$CHOWN_LOG" 'run restores caller ownership when sudo created the workspace mount directories'

: >"$CHOWN_LOG"
rm -f "${PODMAN_LOG}.names"
env -u SUDO_UID -u SUDO_GID PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CHOWN_LOG="$CHOWN_LOG" OPENCODE_TEST_HOST_UID='0' OPENCODE_TEST_HOST_GID='0' bash "$ROOT/scripts/agent/shared/opencode-run" alpha beta >"$TMP_DIR/root-nosudo.out" 2>"$TMP_DIR/root-nosudo.err"
assert_file_contains '-R 0:0' "$CHOWN_LOG" 'run preserves true root ownership when invoked directly as root without sudo metadata'

# This restores the shared config before the test reports success.
cleanup
trap - EXIT

printf 'opencode-run behavior checks passed\n'
