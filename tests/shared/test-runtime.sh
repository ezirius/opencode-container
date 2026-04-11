#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
SOURCE_DIR="$TMPDIR/source"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$SOURCE_DIR/packages/opencode"

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "-C" ]]; then
  cd "$2"
  shift 2
fi

case "$1" in
  diff)
    exit 0
    ;;
  ls-files)
    exit 0
    ;;
  log)
    printf '20260410-163440-ab12cd3\n'
    ;;
  rev-parse)
    case "$2" in
      --git-dir)
        printf '.git\n'
        ;;
      --git-common-dir)
        printf '.git\n'
        ;;
      --abbrev-ref)
        printf 'origin/main\n'
        ;;
      --show-toplevel)
        pwd
        printf '\n'
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  rev-list)
    printf '0\t0\n'
    ;;
  *)
    printf 'unexpected git command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/git"

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${@: -1}"
case "$url" in
  */releases/latest)
    printf '{"tag_name":"v1.4.3"}'
    ;;
  */releases)
    printf '[{"tag_name":"v1.4.3"},{"tag_name":"v1.4.2"}]'
    ;;
  *)
    printf 'unexpected curl url: %s\n' "$url" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/curl"

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${STATE_DIR:?}"
LOG_FILE="$STATE_DIR/podman.log"
IMAGES_FILE="$STATE_DIR/images.tsv"
CONTAINERS_FILE="$STATE_DIR/containers.tsv"
touch "$LOG_FILE" "$IMAGES_FILE" "$CONTAINERS_FILE"

LABEL_WORKSPACE="opencode.wrapper.workspace"
LABEL_LANE="opencode.wrapper.lane"
LABEL_UPSTREAM="opencode.wrapper.upstream"
LABEL_UPSTREAM_REF="opencode.wrapper.upstream_ref"
LABEL_WRAPPER="opencode.wrapper.context"
LABEL_COMMITSTAMP="opencode.wrapper.commitstamp"

image_runtime_user() {
  local ref="$1"
  local record
  record="$(image_record "$ref")"
  IFS=$'\t' read -r _ _ _ _ _ _ runtime_user runtime_home <<< "$record"
  if [[ -n "$runtime_user" ]]; then
    printf '%s\n' "$runtime_user"
    return 0
  fi
  printf 'root\n'
}

image_runtime_home() {
  local ref="$1"
  local record
  record="$(image_record "$ref")"
  IFS=$'\t' read -r _ _ _ _ _ _ runtime_user runtime_home <<< "$record"
  if [[ -n "$runtime_home" ]]; then
    printf '%s\n' "$runtime_home"
    return 0
  fi
  printf '/root\n'
}

log_call() {
  printf '%s\n' "$*" >> "$LOG_FILE"
}

image_record() {
  local ref="$1"
  grep -F "${ref}"$'\t' "$IMAGES_FILE" || true
}

container_record() {
  local name="$1"
  grep -F "${name}"$'\t' "$CONTAINERS_FILE" || true
}

remove_image_record() {
  local ref="$1"
  grep -Fv "${ref}"$'\t' "$IMAGES_FILE" > "$IMAGES_FILE.tmp" || true
  mv "$IMAGES_FILE.tmp" "$IMAGES_FILE"
}

remove_container_record() {
  local name="$1"
  grep -Fv "${name}"$'\t' "$CONTAINERS_FILE" > "$CONTAINERS_FILE.tmp" || true
  mv "$CONTAINERS_FILE.tmp" "$CONTAINERS_FILE"
}

subcommand="${1:?}"
shift || true

case "$subcommand" in
  manifest)
    log_call "manifest $*"
    [[ "$1" == "inspect" ]] || exit 1
    if [[ "$2" == *":1.4.3" || "$2" == *":v1.4.3" ]]; then
      printf '{}\n'
      exit 0
    fi
    exit 1
    ;;
  pull)
    log_call "pull $*"
    exit 0
    ;;
  build)
    log_call "build $*"
    target=""
    base_image=""
    lane=""
    upstream=""
    upstream_ref=""
    wrapper=""
    commitstamp=""
    runtime_user="root"
    runtime_home="/root"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        --build-arg)
          case "$2" in
            BASE_IMAGE=*) base_image="${2#*=}" ;;
            OPENCODE_WRAPPER_LANE=*) lane="${2#*=}" ;;
            OPENCODE_WRAPPER_UPSTREAM=*) upstream="${2#*=}" ;;
            OPENCODE_WRAPPER_UPSTREAM_REF=*) upstream_ref="${2#*=}" ;;
            OPENCODE_WRAPPER_CONTEXT=*) wrapper="${2#*=}" ;;
            OPENCODE_WRAPPER_COMMITSTAMP=*) commitstamp="${2#*=}" ;;
          esac
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    case "$base_image" in
      ghcr.io/anomalyco/opencode:*)
        runtime_user="root"
        runtime_home="/root"
        ;;
      *)
        runtime_user="opencode"
        runtime_home="/home/opencode"
        ;;
    esac
    remove_image_record "$target"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$lane" "$upstream" "$upstream_ref" "$wrapper" "$commitstamp" "$runtime_user" "$runtime_home" >> "$IMAGES_FILE"
    ;;
  image)
    action="$1"
    shift || true
    case "$action" in
      exists)
        log_call "image exists $*"
        [[ -n "$(image_record "$1")" ]]
        ;;
        inspect)
          log_call "image inspect $*"
          format="$2"
          record="$(image_record "$3")"
          IFS=$'\t' read -r ref lane upstream upstream_ref wrapper commitstamp runtime_user runtime_home <<< "$record"
          case "$format" in
            *"$LABEL_LANE"*) printf '%s\n' "$lane" ;;
            *"$LABEL_UPSTREAM_REF"*) printf '%s\n' "$upstream_ref" ;;
            *"$LABEL_UPSTREAM"*) printf '%s\n' "$upstream" ;;
            *"$LABEL_WRAPPER"*) printf '%s\n' "$wrapper" ;;
            *"$LABEL_COMMITSTAMP"*) printf '%s\n' "$commitstamp" ;;
            '{{.Config.User}}') printf '%s\n' "${runtime_user:-root}" ;;
            '{{range .Config.Env}}{{println .}}{{end}}') printf 'HOME=%s\n' "${runtime_home:-/root}" ;;
            *) exit 1 ;;
          esac
          ;;
      *) exit 1 ;;
    esac
    ;;
  images)
    log_call "images $*"
    cut -f1 "$IMAGES_FILE"
    ;;
  container)
    action="$1"
    shift || true
    case "$action" in
      exists)
        log_call "container exists $*"
        [[ -n "$(container_record "$1")" ]]
        ;;
      *) exit 1 ;;
    esac
    ;;
  ps)
    log_call "ps $*"
    cut -f1 "$CONTAINERS_FILE"
    ;;
  inspect)
    log_call "inspect $*"
    format="$2"
    record="$(container_record "$3")"
    IFS=$'\t' read -r name workspace lane upstream wrapper commitstamp status image_ref <<< "$record"
    case "$format" in
      '{{.State.Running}}') printf '%s\n' "$status" ;;
      '{{.ImageName}}') printf '%s\n' "$image_ref" ;;
      *"$LABEL_WORKSPACE"*) printf '%s\n' "$workspace" ;;
      *"$LABEL_LANE"*) printf '%s\n' "$lane" ;;
      *"$LABEL_UPSTREAM"*) printf '%s\n' "$upstream" ;;
      *"$LABEL_WRAPPER"*) printf '%s\n' "$wrapper" ;;
      *"$LABEL_COMMITSTAMP"*) printf '%s\n' "$commitstamp" ;;
      *) exit 1 ;;
    esac
    ;;
  run)
    log_call "run $*"
    name=""
    workspace=""
    lane=""
    upstream=""
    wrapper=""
    commitstamp=""
    image_ref=""
    server_port="64096"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name)
          name="$2"
          shift 2
          ;;
        --label)
          case "$2" in
            $LABEL_WORKSPACE=*) workspace="${2#*=}" ;;
            $LABEL_LANE=*) lane="${2#*=}" ;;
            $LABEL_UPSTREAM=*) upstream="${2#*=}" ;;
            $LABEL_WRAPPER=*) wrapper="${2#*=}" ;;
            $LABEL_COMMITSTAMP=*) commitstamp="${2#*=}" ;;
          esac
          shift 2
          ;;
        -p)
          case "$2" in
            127.0.0.1::4096) server_port="64096" ;;
            127.0.0.1:*:4096) server_port="${2#127.0.0.1:}"; server_port="${server_port%:4096}" ;;
          esac
          shift 2
          ;;
        -v|--restart|-d)
          if [[ "$1" == "-d" ]]; then shift; else shift 2; fi
          ;;
        *)
          image_ref="$1"
          shift
          ;;
      esac
    done
    remove_container_record "$name"
    printf '%s\t%s\t%s\t%s\t%s\t%s\ttrue\t%s\n' "$name" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp" "$image_ref" >> "$CONTAINERS_FILE"
    printf '%s\n' "127.0.0.1:$server_port" > "$STATE_DIR/port_4096_$name"
    ;;
  start)
    log_call "start $*"
    name="$1"
    record="$(container_record "$name")"
    IFS=$'\t' read -r cname workspace lane upstream wrapper commitstamp status image_ref <<< "$record"
    remove_container_record "$name"
    printf '%s\t%s\t%s\t%s\t%s\t%s\ttrue\t%s\n' "$cname" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp" "$image_ref" >> "$CONTAINERS_FILE"
    ;;
  stop)
    log_call "stop $*"
    name="$1"
    record="$(container_record "$name")"
    IFS=$'\t' read -r cname workspace lane upstream wrapper commitstamp status image_ref <<< "$record"
    remove_container_record "$name"
    printf '%s\t%s\t%s\t%s\t%s\t%s\tfalse\t%s\n' "$cname" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp" "$image_ref" >> "$CONTAINERS_FILE"
    ;;
  rm)
    log_call "rm $*"
    name="${@: -1}"
    remove_container_record "$name"
    ;;
  rmi)
    log_call "rmi $*"
    name="${@: -1}"
    remove_image_record "$name"
    ;;
  logs)
    log_call "logs $*"
    printf 'mock logs\n'
    ;;
  port)
    log_call "port $*"
    name="$1"
    port_proto="$2"
    port="${port_proto%%/*}"
    cat "$STATE_DIR/port_${port}_$name"
    ;;
  exec)
    log_call "exec $*"
    printf 'mock exec\n'
    ;;
  *)
    printf 'unexpected podman command: %s\n' "$subcommand" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"

export PATH="$MOCK_BIN:$PATH"
export STATE_DIR
export OPENCODE_BASE_ROOT="$TMPDIR/workspaces"
export OPENCODE_IMAGE_NAME="opencode-local"
export OPENCODE_SELECT_INDEX=1
export OPENCODE_COMMITSTAMP_OVERRIDE="20260410-163440-ab12cd3"
export OPENCODE_SOURCE_OVERRIDE_DIR="$SOURCE_DIR"
export OPENCODE_SKIP_BUILD_CONTEXT_CHECK=1

source "$ROOT/lib/shell/common.sh"
assert_eq $'1.4.3\n1.4.2' "$(list_release_tags)" 'release list resolves from GitHub API output'
assert_eq '1.4.3' "$(latest_release_tag)" 'latest release resolves from GitHub API output'

"$ROOT/scripts/shared/opencode-build" test 1.4.3 > "$STATE_DIR/build.out"
assert_contains "$STATE_DIR/build.out" 'Build source: official image ghcr.io/anomalyco/opencode:1.4.3' 'build prefers official image for exact tag'
assert_contains "$STATE_DIR/build.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'build creates immutable image ref'

"$ROOT/scripts/shared/opencode-build" test main > "$STATE_DIR/build-main.out"
assert_contains "$STATE_DIR/build-main.out" 'Build source: upstream source ref dev' 'main build uses upstream source ref'
assert_contains "$STATE_DIR/build-main.out" 'Built image: opencode-local:test-main-main-20260410-163440-ab12cd3' 'main build creates immutable image ref'
assert_contains "$STATE_DIR/podman.log" 'Containerfile.source-base' 'main build uses source-base containerfile'
assert_contains "$STATE_DIR/podman.log" 'config/containers/Containerfile.wrapper' 'main build wraps the source base image'

"$ROOT/scripts/shared/opencode-build" test 1.4.2 > "$STATE_DIR/build-fallback.out"
assert_contains "$STATE_DIR/build-fallback.out" 'Build source: upstream source ref v1.4.2' 'release fallback uses source when no official image is available'
assert_contains "$STATE_DIR/podman.log" 'Containerfile.source-base' 'release fallback uses source-base containerfile'

"$ROOT/scripts/shared/opencode-start" general test 1.4.3 > "$STATE_DIR/start.out"
assert_contains "$STATE_DIR/start.out" 'Container: opencode-general-test-1.4.3-main' 'start prints deterministic container name'
assert_contains "$STATE_DIR/start.out" 'Server: http://127.0.0.1:64096' 'start reports random mapped server port when unset'
assert_contains "$STATE_DIR/start.out" 'Workspace Dir: /workspace/opencode-workspace' 'start prints container workspace dir'
assert_contains "$STATE_DIR/podman.log" '--name opencode-general-test-1.4.3-main' 'run uses deterministic container name'
assert_contains "$STATE_DIR/podman.log" '-p 127.0.0.1::4096' 'start uses random host server port when unset'
assert_contains "$STATE_DIR/podman.log" "$TMPDIR/workspaces/general/opencode-home:/root" 'official image run mounts workspace home at the upstream root home'
assert_contains "$STATE_DIR/podman.log" "$TMPDIR/workspaces/general/opencode-workspace:/workspace/opencode-workspace" 'run mounts workspace dir'

"$ROOT/scripts/shared/opencode-start" sourcey test 1.4.2 > "$STATE_DIR/start-source.out"
assert_contains "$STATE_DIR/podman.log" "$TMPDIR/workspaces/sourcey/opencode-home:/home/opencode" 'source-built run mounts workspace home at the upstream opencode home'
podman rm -f opencode-sourcey-test-1.4.2-main >/dev/null

mkdir -p "$TMPDIR/workspaces/fixed/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/fixed/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5096
EOF
"$ROOT/scripts/shared/opencode-start" fixed test 1.4.3 > "$STATE_DIR/start-fixed-port.out"
assert_contains "$STATE_DIR/start-fixed-port.out" 'Server: http://127.0.0.1:5096' 'start reports fixed mapped server port when configured'
assert_contains "$STATE_DIR/podman.log" '-p 127.0.0.1:5096:4096' 'start uses configured fixed host server port'
podman rm -f opencode-fixed-test-1.4.3-main >/dev/null

"$ROOT/scripts/shared/opencode-open" general test 1.4.3 --help > "$STATE_DIR/open.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-general-test-1.4.3-main /bin/sh -lc' 'open execs through wrapper shell'
assert_contains "$STATE_DIR/podman.log" 'exec opencode "$@"' 'open forwards OpenCode arguments'

"$ROOT/scripts/shared/opencode-status" general > "$STATE_DIR/status.out"
assert_contains "$STATE_DIR/status.out" 'Lane: test' 'status reports lane'
assert_contains "$STATE_DIR/status.out" 'Upstream: 1.4.3' 'status reports upstream'

"$ROOT/scripts/shared/opencode-stop" general > "$STATE_DIR/stop.out"
assert_contains "$STATE_DIR/stop.out" 'Stopped container: opencode-general-test-1.4.3-main' 'stop stops running container'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-feature-xyz-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 feature-xyz 20260410-163440-ab12cd3 >> "$STATE_DIR/images.tsv"
OPENCODE_WRAPPER_CONTEXT_OVERRIDE=feature-xyz "$ROOT/scripts/shared/opencode-start" branchy test 1.4.3 --version > "$STATE_DIR/start-with-args.out"
assert_contains "$STATE_DIR/podman.log" '--name opencode-branchy-test-1.4.3-feature-xyz' 'start with args creates the selected wrapper-context container'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-branchy-test-1.4.3-feature-xyz /bin/sh -lc' 'start with args preserves selected wrapper context when delegating to open'
podman rm -f opencode-branchy-test-1.4.3-feature-xyz >/dev/null

OPENCODE_SELECT_INDEX=3 "$ROOT/scripts/shared/opencode-remove" container > "$STATE_DIR/remove-container.out"
assert_contains "$STATE_DIR/remove-container.out" 'Removed container: opencode-general-test-1.4.3-main' 'remove container removes selected container'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 > "$STATE_DIR/images.tsv"
OPENCODE_SELECT_INDEX=3 "$ROOT/scripts/shared/opencode-remove" image > "$STATE_DIR/remove-image.out"
assert_contains "$STATE_DIR/remove-image.out" 'Removed image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'remove image removes selected image'

IMG_EZ_NEW='opencode-local:production-1.4.3-main-20260410-163440-ab12cd3'
IMG_EZ_OLD='opencode-local:production-1.4.2-main-20260409-120000-deadbee'
IMG_NA='opencode-local:test-1.4.3-main-20260408-090000-cafebabe'
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_OLD" production 1.4.2 v1.4.2 main 20260409-120000-deadbee >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" image > "$STATE_DIR/remove-image-all-but-newest.out"
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Keeping image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'remove image all-but-newest keeps newest associated ezirius image'
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Keeping image: opencode-local:test-1.4.3-main-20260408-090000-cafebabe' 'remove image all-but-newest keeps newest associated nala image'
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Removed image: opencode-local:production-1.4.2-main-20260409-120000-deadbee' 'remove image all-but-newest removes older associated image'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.2-main' general test 1.4.2 main 20260409-120000-deadbee false "$IMG_EZ_OLD" >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" container > "$STATE_DIR/remove-container-all-but-newest.out"
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Keeping container: opencode-general-production-1.4.3-main' 'remove container all-but-newest keeps newest container for general'
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Removed container: opencode-general-test-1.4.2-main' 'remove container all-but-newest removes older general container'
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Keeping container: opencode-nala-test-1.4.3-main' 'remove container all-but-newest keeps newest container for nala'

echo "Runtime checks passed"
