#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
mkdir -p "$MOCK_BIN" "$STATE_DIR"

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

  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

write_file() {
  local path="$1"
  local content="${2-}"
  printf '%s' "$content" > "$path"
}

reset_state() {
  rm -f "$STATE_DIR"/*
  : > "$STATE_DIR/podman.log"
}

set_podman_failure() {
  local key="$1"
  local message="$2"

  write_file "$STATE_DIR/fail_$key" "$message"
}

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_UNAME:-arm64}"
EOF
chmod +x "$MOCK_BIN/uname"

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${STATE_DIR:?}"
LOG_FILE="$STATE_DIR/podman.log"

log_call() {
  printf '%s\n' "$*" >> "$LOG_FILE"
}

read_value() {
  local name="$1"
  local path="$STATE_DIR/$name"

  if [[ -f "$path" ]]; then
    cat "$path"
  fi
}

write_value() {
  local name="$1"
  local value="$2"
  printf '%s' "$value" > "$STATE_DIR/$name"
}

remove_value() {
  rm -f "$STATE_DIR/$1"
}

subcommand="${1:?podman subcommand required}"
shift || true

case "$subcommand" in
  image)
    action="${1:?podman image action required}"
    shift || true
    case "$action" in
      exists)
        log_call "image exists $*"
        if [[ "$(read_value image_exists)" == "1" ]]; then
          exit 0
        fi
        exit 1
        ;;
      inspect)
        log_call "image inspect $*"
        format="${2-}"
        case "$format" in
          '{{.Id}}')
            printf '%s\n' "$(read_value image_id)"
            ;;
          '{{ index .Labels "opencode.ubuntu_version" }}')
            if [[ -f "$STATE_DIR/image_labels" ]]; then
              grep '^opencode.ubuntu_version=' "$STATE_DIR/image_labels" | sed 's/^[^=]*=//'
            fi
            ;;
          '{{ index .Labels "opencode.version" }}')
            if [[ -f "$STATE_DIR/image_labels" ]]; then
              grep '^opencode.version=' "$STATE_DIR/image_labels" | sed 's/^[^=]*=//'
            fi
            ;;
          *)
            printf 'unexpected podman image inspect format: %s\n' "$format" >&2
            exit 1
            ;;
        esac
        ;;
      rm)
        log_call "image rm $*"
        if [[ -f "$STATE_DIR/fail_image_rm" ]]; then
          cat "$STATE_DIR/fail_image_rm" >&2
          exit 1
        fi
        write_value image_rm_name "$*"
        remove_value image_exists
        remove_value image_id
        ;;
      *)
        printf 'unexpected podman image action: %s\n' "$action" >&2
        exit 1
        ;;
    esac
    ;;
  build)
    log_call "build $*"
    if [[ -f "$STATE_DIR/fail_build" ]]; then
      cat "$STATE_DIR/fail_build" >&2
      exit 1
    fi
    write_value image_exists 1
    write_value image_id mock-image-id
    write_value last_build "$*"
    : > "$STATE_DIR/image_labels"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label)
          printf '%s\n' "$2" >> "$STATE_DIR/image_labels"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    ;;
  container)
    action="${1:?podman container action required}"
    shift || true
    case "$action" in
      exists)
        log_call "container exists $*"
        if [[ "$(read_value container_exists)" == "1" ]]; then
          exit 0
        fi
        exit 1
        ;;
      *)
        printf 'unexpected podman container action: %s\n' "$action" >&2
        exit 1
        ;;
    esac
    ;;
  inspect)
    log_call "inspect $*"
    format="$2"
    case "$format" in
      '{{.Image}}')
        printf '%s\n' "$(read_value container_image_id)"
        ;;
      '{{.State.Running}}')
        printf '%s\n' "$(read_value container_running)"
        ;;
      *)
        printf 'unexpected podman inspect format: %s\n' "$format" >&2
        exit 1
        ;;
    esac
    ;;
  rm)
    log_call "rm $*"
    write_value last_rm "$*"
    remove_value container_exists
    remove_value container_running
    remove_value container_image_id
    ;;
  start)
    log_call "start $*"
    if [[ -f "$STATE_DIR/fail_start" ]]; then
      cat "$STATE_DIR/fail_start" >&2
      exit 1
    fi
    write_value last_start "$*"
    write_value container_exists 1
    write_value container_running true
    ;;
  run)
    log_call "run $*"
    if [[ -f "$STATE_DIR/fail_run" ]]; then
      cat "$STATE_DIR/fail_run" >&2
      exit 1
    fi
    write_value last_run "$*"
    write_value container_exists 1
    write_value container_running true
    write_value container_image_id "$(read_value image_id)"
    ;;
  stop)
    log_call "stop $*"
    if [[ -f "$STATE_DIR/fail_stop" ]]; then
      cat "$STATE_DIR/fail_stop" >&2
      exit 1
    fi
    write_value last_stop "$*"
    write_value container_running false
    ;;
  logs)
    log_call "logs $*"
    printf 'mock logs\n'
    ;;
  exec)
    log_call "exec $*"
    if [[ -f "$STATE_DIR/fail_exec" ]]; then
      cat "$STATE_DIR/fail_exec" >&2
      exit 1
    fi
    write_value last_exec "$*"
    printf 'mock exec\n'
    ;;
  *)
    printf 'unexpected podman subcommand: %s\n' "$subcommand" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"

export PATH="$MOCK_BIN:$PATH"
export STATE_DIR
export OPENCODE_BASE_ROOT="$TMPDIR/workspaces"
export OPENCODE_IMAGE_NAME="mock-opencode-image"
export UBUNTU_VERSION="24.04"
export OPENCODE_VERSION="1.2.27"
export MOCK_UNAME="arm64"

reset_state
write_file "$STATE_DIR/image_exists" "1"
"$ROOT/scripts/shared/opencode-build" > "$STATE_DIR/build-skip.out"
assert_contains "$STATE_DIR/build-skip.out" 'OpenCode image already exists: mock-opencode-image' 'build reports existing image'
assert_contains "$STATE_DIR/build-skip.out" 'Skipping rebuild' 'build skips when image exists'
assert_not_contains "$STATE_DIR/podman.log" 'build ' 'build skip path does not call podman build'

reset_state
write_file "$STATE_DIR/image_exists" "1"
MOCK_UNAME="x86_64" "$ROOT/scripts/shared/opencode-build" > "$STATE_DIR/build-skip-x86.out"
assert_contains "$STATE_DIR/build-skip-x86.out" 'Skipping rebuild' 'build skip path does not require arm64 host'

reset_state
"$ROOT/scripts/shared/opencode-build" > "$STATE_DIR/build-run.out"
assert_contains "$STATE_DIR/build-run.out" 'Build complete: mock-opencode-image' 'build reports completion'
assert_contains "$STATE_DIR/last_build" '--build-arg UBUNTU_VERSION=24.04' 'build passes Ubuntu version'
assert_contains "$STATE_DIR/last_build" '--build-arg OPENCODE_VERSION=1.2.27' 'build passes OpenCode version'
assert_contains "$STATE_DIR/last_build" '--platform=linux/arm64' 'build uses arm64 platform'
assert_contains "$STATE_DIR/image_labels" 'opencode.ubuntu_version=24.04' 'build labels image with Ubuntu version'
assert_contains "$STATE_DIR/image_labels" 'opencode.version=1.2.27' 'build labels image with OpenCode version'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_labels" $'opencode.ubuntu_version=24.04\nopencode.version=1.2.27\n'
"$ROOT/scripts/shared/opencode-upgrade" > "$STATE_DIR/upgrade-skip.out"
assert_contains "$STATE_DIR/upgrade-skip.out" 'No upgrade needed' 'upgrade exits cleanly when versions match'
assert_not_contains "$STATE_DIR/podman.log" 'image rm ' 'upgrade skip path does not remove image'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_labels" $'opencode.ubuntu_version=24.04\nopencode.version=1.2.27\n'
MOCK_UNAME="x86_64" "$ROOT/scripts/shared/opencode-upgrade" > "$STATE_DIR/upgrade-skip-x86.out"
assert_contains "$STATE_DIR/upgrade-skip-x86.out" 'No upgrade needed' 'upgrade skip path does not require arm64 host'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_labels" $'opencode.ubuntu_version=22.04\nopencode.version=1.2.26\n'
"$ROOT/scripts/shared/opencode-upgrade" > "$STATE_DIR/upgrade-run.out"
assert_contains "$STATE_DIR/upgrade-run.out" 'Upgrading OpenCode image:' 'upgrade reports rebuild when versions differ'
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-opencode-image' 'upgrade removes the old image'
assert_contains "$STATE_DIR/last_build" '--build-arg UBUNTU_VERSION=24.04' 'upgrade rebuild passes Ubuntu version'
assert_contains "$STATE_DIR/last_build" '--build-arg OPENCODE_VERSION=1.2.27' 'upgrade rebuild passes OpenCode version'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" "image-a"
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "true"
write_file "$STATE_DIR/container_image_id" "image-a"
"$ROOT/scripts/shared/opencode-start" general > "$STATE_DIR/start-running.out"
assert_contains "$STATE_DIR/start-running.out" 'Container already running:' 'start reports running container'
assert_not_contains "$STATE_DIR/podman.log" 'run ' 'start does not recreate running same-image container'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" "image-a"
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "false"
write_file "$STATE_DIR/container_image_id" "image-a"
"$ROOT/scripts/shared/opencode-start" general > "$STATE_DIR/start-stopped.out"
assert_contains "$STATE_DIR/start-stopped.out" 'Starting existing stopped container:' 'start reports restarting stopped container'
assert_contains "$STATE_DIR/last_start" 'opencode-general-' 'start restarts the existing container by name'
assert_not_contains "$STATE_DIR/podman.log" 'run ' 'start does not recreate stopped same-image container'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" "image-b"
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "false"
write_file "$STATE_DIR/container_image_id" "image-a"
"$ROOT/scripts/shared/opencode-start" general > "$STATE_DIR/start-recreate.out"
assert_contains "$STATE_DIR/start-recreate.out" 'Removing existing container with old image:' 'start removes stale container'
assert_contains "$STATE_DIR/podman.log" 'rm -f opencode-general-' 'start removes old container before run'
assert_contains "$STATE_DIR/podman.log" 'run -d --name opencode-general-' 'start creates a fresh container when image changed'

reset_state
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "false"
"$ROOT/scripts/shared/opencode-stop" general > "$STATE_DIR/stop-stopped.out"
assert_contains "$STATE_DIR/stop-stopped.out" 'Container already stopped:' 'stop reports already-stopped container'
assert_not_contains "$STATE_DIR/podman.log" 'stop ' 'stop does not call podman stop for stopped container'

reset_state
"$ROOT/scripts/shared/opencode-remove" general > "$STATE_DIR/remove-missing.out"
assert_contains "$STATE_DIR/remove-missing.out" 'No container found:' 'remove reports missing container cleanly'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "true"
"$ROOT/scripts/shared/opencode-open" general --help > "$STATE_DIR/open.out"
assert_contains "$STATE_DIR/last_exec" '-i -w /workspace opencode-general-' 'open uses podman exec in non-interactive mode'
assert_contains "$STATE_DIR/last_exec" 'opencode --help' 'open forwards extra opencode arguments'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" "image-c"
write_file "$STATE_DIR/image_labels" $'opencode.ubuntu_version=24.04\nopencode.version=1.2.27\n'
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "false"
write_file "$STATE_DIR/container_image_id" "image-c"
"$ROOT/scripts/shared/bootstrap" general --help > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/bootstrap.out" 'OpenCode image already exists:' 'bootstrap reuses existing image'
assert_contains "$STATE_DIR/bootstrap.out" 'No upgrade needed' 'bootstrap checks for upgrades before starting'
assert_contains "$STATE_DIR/bootstrap.out" 'Starting existing stopped container:' 'bootstrap reuses stopped container'
assert_contains "$STATE_DIR/last_exec" 'opencode --help' 'bootstrap forwards args through to opencode-open'

if "$ROOT/scripts/shared/opencode-build" unexpected >/dev/null 2> "$STATE_DIR/build-args.err"; then
  printf 'assertion failed: build should reject unexpected arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/build-args.err" 'takes no arguments' 'build reports invalid argument usage clearly'

if "$ROOT/scripts/shared/opencode-upgrade" unexpected >/dev/null 2> "$STATE_DIR/upgrade-args.err"; then
  printf 'assertion failed: upgrade should reject unexpected arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/upgrade-args.err" 'takes no arguments' 'upgrade reports invalid argument usage clearly'

if "$ROOT/scripts/shared/opencode-start" >/dev/null 2> "$STATE_DIR/start-args.err"; then
  printf 'assertion failed: start should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/start-args.err" 'requires exactly 1 argument' 'start reports missing workspace clearly'

if "$ROOT/scripts/shared/opencode-start" one two >/dev/null 2> "$STATE_DIR/start-extra-args.err"; then
  printf 'assertion failed: start should reject extra arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/start-extra-args.err" 'requires exactly 1 argument' 'start reports extra arguments clearly'

if "$ROOT/scripts/shared/opencode-open" >/dev/null 2> "$STATE_DIR/open-args.err"; then
  printf 'assertion failed: open should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/open-args.err" 'requires at least 1 argument' 'open reports missing workspace clearly'

if "$ROOT/scripts/shared/opencode-shell" >/dev/null 2> "$STATE_DIR/shell-args.err"; then
  printf 'assertion failed: shell should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/shell-args.err" 'requires exactly 1 argument' 'shell reports missing workspace clearly'

if "$ROOT/scripts/shared/opencode-shell" one two >/dev/null 2> "$STATE_DIR/shell-extra-args.err"; then
  printf 'assertion failed: shell should reject extra arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/shell-extra-args.err" 'requires exactly 1 argument' 'shell reports extra arguments clearly'

if "$ROOT/scripts/shared/opencode-stop" >/dev/null 2> "$STATE_DIR/stop-args.err"; then
  printf 'assertion failed: stop should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/stop-args.err" 'requires exactly 1 argument' 'stop reports missing workspace clearly'

if "$ROOT/scripts/shared/opencode-stop" one two >/dev/null 2> "$STATE_DIR/stop-extra-args.err"; then
  printf 'assertion failed: stop should reject extra arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/stop-extra-args.err" 'requires exactly 1 argument' 'stop reports extra arguments clearly'

if "$ROOT/scripts/shared/opencode-remove" >/dev/null 2> "$STATE_DIR/remove-args.err"; then
  printf 'assertion failed: remove should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/remove-args.err" 'requires exactly 1 argument' 'remove reports missing workspace clearly'

if "$ROOT/scripts/shared/opencode-remove" one two >/dev/null 2> "$STATE_DIR/remove-extra-args.err"; then
  printf 'assertion failed: remove should reject extra arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/remove-extra-args.err" 'requires exactly 1 argument' 'remove reports extra arguments clearly'

if "$ROOT/scripts/shared/opencode-logs" >/dev/null 2> "$STATE_DIR/logs-args.err"; then
  printf 'assertion failed: logs should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/logs-args.err" 'requires exactly 1 argument' 'logs reports missing workspace clearly'

if "$ROOT/scripts/shared/opencode-logs" one two >/dev/null 2> "$STATE_DIR/logs-extra-args.err"; then
  printf 'assertion failed: logs should reject extra arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/logs-extra-args.err" 'requires exactly 1 argument' 'logs reports extra arguments clearly'

if "$ROOT/scripts/shared/bootstrap" >/dev/null 2> "$STATE_DIR/bootstrap-args.err"; then
  printf 'assertion failed: bootstrap should reject missing arguments\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/bootstrap-args.err" 'requires at least 1 argument' 'bootstrap reports missing workspace clearly'

reset_state
set_podman_failure build 'mock build failure'
if "$ROOT/scripts/shared/opencode-build" >/dev/null 2> "$STATE_DIR/build-fail.err"; then
  printf 'assertion failed: build should fail when podman build fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/build-fail.err" 'mock build failure' 'build surfaces podman build failure'
assert_not_contains "$STATE_DIR/build-fail.err" 'Build complete:' 'build does not print success after failure'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_labels" $'opencode.ubuntu_version=22.04\nopencode.version=1.2.26\n'
set_podman_failure image_rm 'mock image remove failure'
if "$ROOT/scripts/shared/opencode-upgrade" >/dev/null 2> "$STATE_DIR/upgrade-fail.err"; then
  printf 'assertion failed: upgrade should fail when image removal fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/upgrade-fail.err" 'mock image remove failure' 'upgrade surfaces image removal failure'
assert_not_contains "$STATE_DIR/podman.log" 'build ' 'upgrade does not rebuild after image removal failure'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" "image-d"
set_podman_failure run 'mock run failure'
if "$ROOT/scripts/shared/opencode-start" general >/dev/null 2> "$STATE_DIR/start-fail.err"; then
  printf 'assertion failed: start should fail when podman run fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/start-fail.err" 'mock run failure' 'start surfaces podman run failure'
assert_not_contains "$STATE_DIR/start-fail.err" 'Container started:' 'start does not print success after run failure'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_labels" $'opencode.ubuntu_version=22.04\nopencode.version=1.2.26\n'
set_podman_failure image_rm 'mock bootstrap upgrade failure'
if "$ROOT/scripts/shared/bootstrap" general --help >/dev/null 2> "$STATE_DIR/bootstrap-fail.err"; then
  printf 'assertion failed: bootstrap should fail when upgrade fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/bootstrap-fail.err" 'mock bootstrap upgrade failure' 'bootstrap surfaces upgrade failure'
assert_not_contains "$STATE_DIR/podman.log" 'run ' 'bootstrap does not start a container after upgrade failure'
assert_not_contains "$STATE_DIR/podman.log" 'exec ' 'bootstrap does not open opencode after upgrade failure'

reset_state
write_file "$STATE_DIR/container_exists" "1"
write_file "$STATE_DIR/container_running" "true"
set_podman_failure exec 'mock exec failure'
if "$ROOT/scripts/shared/opencode-open" general --help >/dev/null 2> "$STATE_DIR/open-fail.err"; then
  printf 'assertion failed: open should fail when podman exec fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/open-fail.err" 'mock exec failure' 'open surfaces podman exec failure'

echo "Runtime behaviour checks passed"
