#!/usr/bin/env bash

set -euo pipefail

# This test checks that the shell script prompts for missing choices and runs commands inside a running project container.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/shared/shared/test-asserts.sh"

CONFIG_PATH="$ROOT/configs/shared/opencode/opencode-settings.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
IMAGE_ID='1234567890ab'
IMAGE_NAME="opencode-1.14.25-20260418-120000-${IMAGE_ID}"
OLD_IMAGE_ID='fedcba098765'
OLD_IMAGE_NAME="opencode-1.14.20-20260417-120000-${OLD_IMAGE_ID}"

# This restores the shared config and temp files after the shell checks finish.
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
      absent)
        ;;
      multiple)
        printf 'opencode-1.14.25-20260418-120000-1234567890ab-alpha-beta\n'
        printf 'opencode-1.14.20-20260417-120000-fedcba098765-alpha-beta\n'
        ;;
      project-workspace-collision)
        printf 'opencode-1.14.25-20260418-120000-1234567890ab-beta-alpha-prod\n'
        ;;
      *)
        printf 'opencode-1.14.25-20260418-120000-1234567890ab-alpha-beta\n'
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
            workspace_mount="${workspace_mount:-$OPENCODE_TEST_BASE_PATH/alpha-prod/opencode-documents}"
            project_mount="${project_mount:-$OPENCODE_TEST_DEVELOPMENT_ROOT/beta}"
            ;;
          *-beta-*)
            workspace_mount="${workspace_mount:-$OPENCODE_TEST_BASE_PATH/beta/opencode-documents}"
            project_mount="${project_mount:-$OPENCODE_TEST_DEVELOPMENT_ROOT/alpha-prod}"
            ;;
          *)
            workspace_mount="${workspace_mount:-$OPENCODE_TEST_BASE_PATH/alpha/opencode-documents}"
            project_mount="${project_mount:-$OPENCODE_TEST_DEVELOPMENT_ROOT/beta}"
            ;;
        esac
      fi

      printf '%s\n' "$workspace_mount : /workspace/documents"
      printf '%s\n' "$project_mount : /workspace/project"
    fi
    ;;
  exec)
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman"

# This fake curl fails if the shell wrapper ever tries a release lookup.
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$OPENCODE_TEST_CURL_LOG"
exit 99
EOF

chmod +x "$FAKE_BIN/curl"

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.14.25"
OPENCODE_SERVER_PORT="4096"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_WORKSPACES="alpha:10000 alpha-prod:15000 beta:20000"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/documents"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECTS="/workspace/projects"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_SHARED_CONTAINER_SCOPE="infrastructure"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-documents"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="nu"
OPENCODE_RELEASE_API_URL="https://api.github.com/repos/anomalyco/opencode/releases/latest"
OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS="2"
OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS="5"
OPENCODE_SERVER_HOSTNAME="0.0.0.0"
OPENCODE_ATTACH_HOST="127.0.0.1"
OPENCODE_RUNNING_WAIT_ATTEMPTS="10"
OPENCODE_RUNNING_WAIT_SECONDS="1"
OPENCODE_STABLE_WAIT_ATTEMPTS="2"
OPENCODE_STABLE_WAIT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS="5"
OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_SECONDS="1"
EOF

mkdir -p "$TMP_DIR/development/alpha" "$TMP_DIR/development/beta"
PODMAN_LOG="$TMP_DIR/podman.log"
curl_log="$TMP_DIR/curl.log"
export OPENCODE_TEST_BASE_PATH="$TMP_DIR/base"
export OPENCODE_TEST_DEVELOPMENT_ROOT="$TMP_DIR/development"

: >"$PODMAN_LOG"
: >"$curl_log"
if ! PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" --help >"$TMP_DIR/help.out" 2>"$TMP_DIR/help.err"; then
  fail 'shell --help should succeed'
fi
assert_file_contains 'Usage: scripts/shared/opencode/opencode-shell [workspace] [project] [command...]' "$TMP_DIR/help.out" 'shell prints usage text for --help'
test ! -s "$TMP_DIR/help.err" || fail 'shell --help should not print stderr output'
test ! -s "$PODMAN_LOG" || fail 'shell --help should not invoke podman'

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.14.25"
OPENCODE_SERVER_PORT="4096"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_WORKSPACES="alpha"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/documents"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECTS="/workspace/projects"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_SHARED_CONTAINER_SCOPE="infrastructure"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-documents"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="nu"
OPENCODE_RELEASE_API_URL="https://api.github.com/repos/anomalyco/opencode/releases/latest"
OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS="2"
OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS="5"
OPENCODE_SERVER_HOSTNAME="0.0.0.0"
OPENCODE_ATTACH_HOST="127.0.0.1"
OPENCODE_RUNNING_WAIT_ATTEMPTS="10"
OPENCODE_RUNNING_WAIT_SECONDS="1"
OPENCODE_STABLE_WAIT_ATTEMPTS="2"
OPENCODE_STABLE_WAIT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS="5"
OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_SECONDS="1"
EOF

: >"$PODMAN_LOG"
: >"$curl_log"
if ! PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" --help >"$TMP_DIR/help-bad-config.out" 2>"$TMP_DIR/help-bad-config.err"; then
  fail 'shell --help should ignore invalid workspace config'
fi
assert_file_contains 'Usage: scripts/shared/opencode/opencode-shell [workspace] [project] [command...]' "$TMP_DIR/help-bad-config.out" 'shell help still prints with invalid workspace config'
test ! -s "$TMP_DIR/help-bad-config.err" || fail 'shell --help should not print stderr output when config is invalid'
test ! -s "$PODMAN_LOG" || fail 'shell --help should not invoke podman when config is invalid'

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.14.25"
OPENCODE_SERVER_PORT="4096"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_WORKSPACES="alpha:10000 alpha-prod:15000 beta:20000"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/documents"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECTS="/workspace/projects"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_SHARED_CONTAINER_SCOPE="infrastructure"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-documents"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="nu"
OPENCODE_RELEASE_API_URL="https://api.github.com/repos/anomalyco/opencode/releases/latest"
OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS="2"
OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS="5"
OPENCODE_SERVER_HOSTNAME="0.0.0.0"
OPENCODE_ATTACH_HOST="127.0.0.1"
OPENCODE_RUNNING_WAIT_ATTEMPTS="10"
OPENCODE_RUNNING_WAIT_SECONDS="1"
OPENCODE_STABLE_WAIT_ATTEMPTS="2"
OPENCODE_STABLE_WAIT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS="5"
OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_SECONDS="1"
EOF

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" --bad >"$TMP_DIR/bad-option.out" 2>"$TMP_DIR/bad-option.err"; then
  fail 'shell should reject unsupported options clearly'
fi
assert_file_contains 'Unsupported option: --bad. See --help.' "$TMP_DIR/bad-option.err" 'shell directs unsupported options to help'
test ! -s "$PODMAN_LOG" || fail 'shell should fail before invoking podman for unsupported options'

# This verifies the fully prompted path before checking explicit argument handling.
: >"$PODMAN_LOG"
printf '1\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" >"$TMP_DIR/no-args.out" 2>"$TMP_DIR/no-args.err"
assert_file_contains 'Pick a workspace:' "$TMP_DIR/no-args.err" 'shell without arguments prompts for a workspace'
assert_file_contains 'Pick a project:' "$TMP_DIR/no-args.err" 'shell without arguments prompts for a project'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell without arguments opens the configured shell in the prompted project container'

: >"$PODMAN_LOG"
# This checks that q also cancels before project selection begins.
if printf 'q\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" >"$TMP_DIR/workspace-quit.out" 2>"$TMP_DIR/workspace-quit.err"; then
  fail 'shell should let q cancel workspace selection'
fi
assert_file_contains 'Selection cancelled.' "$TMP_DIR/workspace-quit.err" 'shell reports an explicit cancel when q quits workspace selection'
assert_file_not_contains 'exec -i ' "$PODMAN_LOG" 'shell does not attach when q cancels workspace selection'

: >"$PODMAN_LOG"
# This checks that EOF during workspace selection fails with a clean message.
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" < /dev/null >"$TMP_DIR/workspace-eof.out" 2>"$TMP_DIR/workspace-eof.err"; then
  fail 'shell should fail cleanly when workspace selection hits EOF'
fi
assert_file_contains 'Selection aborted.' "$TMP_DIR/workspace-eof.err" 'shell reports a clean EOF failure during workspace selection'
assert_file_not_contains 'exec -i ' "$PODMAN_LOG" 'shell does not attach when workspace selection hits EOF'

# This verifies that a workspace argument still prompts for the project.
: >"$PODMAN_LOG"
printf '2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha >"$TMP_DIR/workspace-only.out" 2>"$TMP_DIR/workspace-only.err"
assert_file_contains 'Pick a project:' "$TMP_DIR/workspace-only.err" 'shell with only a workspace prompts for a project'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell with only a workspace opens the configured shell in the prompted project container'

: >"$PODMAN_LOG"
# This checks that invalid picker input stays in the loop until a valid choice arrives.
printf '0\n1\ngamma\n2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" >"$TMP_DIR/retry.out" 2>"$TMP_DIR/retry.err"
assert_file_contains 'Please pick one of the configured workspaces.' "$TMP_DIR/retry.err" 'shell retries workspace selection after out-of-range input'
assert_file_contains 'Please pick one of the discovered projects.' "$TMP_DIR/retry.err" 'shell retries project selection after invalid input'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell still opens the requested container after picker retries'

: >"$PODMAN_LOG"
# This checks that q is the only interactive quit key during project selection.
if printf '1\nnope\nq\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" >"$TMP_DIR/project-quit.out" 2>"$TMP_DIR/project-quit.err"; then
  fail 'shell should let q cancel project selection'
fi
assert_file_contains 'Please pick one of the discovered projects.' "$TMP_DIR/project-quit.err" 'shell does not treat other project input as a quit request'
assert_file_contains 'Selection cancelled.' "$TMP_DIR/project-quit.err" 'shell reports an explicit cancel when q quits project selection'
assert_file_not_contains 'exec -i ' "$PODMAN_LOG" 'shell does not attach when q cancels project selection'

: >"$PODMAN_LOG"
# This checks that EOF during interactive selection fails with a clean message.
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" >"$TMP_DIR/project-eof.out" 2>"$TMP_DIR/project-eof.err"; then
  fail 'shell should fail cleanly when project selection hits EOF'
fi
assert_file_contains 'Selection aborted.' "$TMP_DIR/project-eof.err" 'shell reports a clean EOF failure during project selection'
assert_file_not_contains 'exec -i ' "$PODMAN_LOG" 'shell does not attach when project selection hits EOF'

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta >"$TMP_DIR/shell.out" 2>"$TMP_DIR/shell.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell opens nu in the running workspace container by default'
test ! -s "$curl_log" || fail 'shell must not check the latest upstream release'

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.14.25"
OPENCODE_SERVER_PORT="4096"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_WORKSPACES="alpha:10000 alpha-prod:15000 beta:20000"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/documents"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECTS="/workspace/projects"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_SHARED_CONTAINER_SCOPE="infrastructure"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-documents"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="bash"
OPENCODE_RELEASE_API_URL="https://api.github.com/repos/anomalyco/opencode/releases/latest"
OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS="2"
OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS="5"
OPENCODE_SERVER_HOSTNAME="0.0.0.0"
OPENCODE_ATTACH_HOST="127.0.0.1"
OPENCODE_RUNNING_WAIT_ATTEMPTS="10"
OPENCODE_RUNNING_WAIT_SECONDS="1"
OPENCODE_STABLE_WAIT_ATTEMPTS="2"
OPENCODE_STABLE_WAIT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS="5"
OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_SECONDS="1"
EOF

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta >"$TMP_DIR/custom-shell.out" 2>"$TMP_DIR/custom-shell.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta bash" "$PODMAN_LOG" 'shell opens the configured OPENCODE_SHELL_COMMAND by default'

cat >"$CONFIG_PATH" <<EOF
# OpenCode runtime configuration.
# Scripts and shell helpers must read these values instead of embedding repo config.
OPENCODE_IMAGE_BASENAME="opencode"
OPENCODE_VERSION="1.14.25"
OPENCODE_SERVER_PORT="4096"
OPENCODE_BASE_PATH="${TMP_DIR}/base"
OPENCODE_DEVELOPMENT_ROOT="${TMP_DIR}/development"
OPENCODE_WORKSPACES="alpha:10000 alpha-prod:15000 beta:20000"
OPENCODE_CONTAINER_HOME="/root"
OPENCODE_CONTAINER_WORKSPACE="/workspace/documents"
OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"
OPENCODE_CONTAINER_PROJECTS="/workspace/projects"
OPENCODE_CONTAINER_PROJECT="/workspace/project"
OPENCODE_SHARED_CONTAINER_SCOPE="infrastructure"
OPENCODE_HOST_HOME_DIRNAME="opencode-home"
OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-documents"
OPENCODE_DEFAULT_COMMAND="opencode"
OPENCODE_SHELL_COMMAND="nu"
OPENCODE_RELEASE_API_URL="https://api.github.com/repos/anomalyco/opencode/releases/latest"
OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS="2"
OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS="5"
OPENCODE_SERVER_HOSTNAME="0.0.0.0"
OPENCODE_ATTACH_HOST="127.0.0.1"
OPENCODE_RUNNING_WAIT_ATTEMPTS="10"
OPENCODE_RUNNING_WAIT_SECONDS="1"
OPENCODE_STABLE_WAIT_ATTEMPTS="2"
OPENCODE_STABLE_WAIT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS="5"
OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="1"
OPENCODE_PUBLISHED_URL_WAIT_SECONDS="1"
EOF

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta env >"$TMP_DIR/command.out" 2>"$TMP_DIR/command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell runs extra arguments as a direct container command'
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-beta nu env" "$PODMAN_LOG" 'shell does not append extra arguments to nu argv'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta opencode -c >"$TMP_DIR/opencode-command.out" 2>"$TMP_DIR/opencode-command.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta opencode -c" "$PODMAN_LOG" 'shell runs opencode command arguments inside the project container'
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-beta nu opencode -c" "$PODMAN_LOG" 'shell does not append opencode arguments to nu argv'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha -- env >"$TMP_DIR/legacy-command.out" 2>"$TMP_DIR/legacy-command.err"; then
  fail 'shell should not support legacy workspace-plus-command usage behind --'
fi
assert_file_contains "project name -- may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.', '..', or '--'" "$TMP_DIR/legacy-command.err" 'shell rejects -- as an unsafe project token instead of treating it as a command separator'
assert_file_not_contains "exec -i ${IMAGE_NAME}-alpha-beta env" "$PODMAN_LOG" 'shell does not treat legacy -- as workspace-plus-command separator'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta >"$TMP_DIR/multiple.out" 2>"$TMP_DIR/multiple.err"
assert_file_contains 'ps --sort created --format {{.Names}} --filter name=^opencode-' "$PODMAN_LOG" 'shell asks Podman to sort running OpenCode containers by creation time before workspace matching'
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell uses the newest container returned by Podman when multiple canonical containers match'

: >"$PODMAN_LOG"
printf '2\n' | PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='multiple' bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha >"$TMP_DIR/multiple-prompt.out" 2>"$TMP_DIR/multiple-prompt.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell prompts for project instead of rejecting workspace-only attach when multiple containers are running'

rm -rf "$TMP_DIR/development/beta"
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta >"$TMP_DIR/missing-project.out" 2>"$TMP_DIR/missing-project.err"
assert_file_contains "exec -i ${IMAGE_NAME}-alpha-beta nu" "$PODMAN_LOG" 'shell still attaches to a running container when the host project directory no longer exists'

: >"$PODMAN_LOG"
helper_workspace_match_with_trailing_base_path="$(PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; OPENCODE_BASE_PATH="$1/"; if opencode_container_workspace_matches "$2" alpha; then printf yes; else printf no; fi' _ "$TMP_DIR/base" "${IMAGE_NAME}-alpha-beta")"
assert_equals 'yes' "$helper_workspace_match_with_trailing_base_path" 'shell helper still matches the workspace mount when the base path ends with a trailing slash'

helper_project_match_with_trailing_development_root="$(PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; OPENCODE_DEVELOPMENT_ROOT="$1/"; if opencode_container_project_matches "$2" beta; then printf yes; else printf no; fi' _ "$TMP_DIR/development" "${IMAGE_NAME}-alpha-beta")"
assert_equals 'yes' "$helper_project_match_with_trailing_development_root" 'shell helper still matches the project mount when the development root ends with a trailing slash'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='project-workspace-collision' OPENCODE_TEST_WORKSPACE_MOUNT="$TMP_DIR/base/beta/opencode-documents" OPENCODE_TEST_PROJECT_MOUNT="$TMP_DIR/development/alpha-prod" bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha-prod alpha >"$TMP_DIR/project-workspace-collision.out" 2>"$TMP_DIR/project-workspace-collision.err"; then
  fail 'shell should reject a container whose project token collides with the requested workspace name'
fi
assert_file_contains 'No running OpenCode container found for alpha-prod.' "$TMP_DIR/project-workspace-collision.err" 'shell does not mistake a project token for the requested workspace name'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CONTAINER_MODE='absent' bash "$ROOT/scripts/shared/opencode/opencode-shell" alpha beta >"$TMP_DIR/no-running-container.out" 2>"$TMP_DIR/no-running-container.err"; then
  fail 'shell should fail clearly when no running container matches the requested workspace and project'
fi
assert_file_contains 'No running OpenCode container found for alpha. Run scripts/shared/opencode/opencode-run first.' "$TMP_DIR/no-running-container.err" 'shell explains when no running container matches the requested workspace'

printf 'opencode-shell behaviour checks passed\n'
