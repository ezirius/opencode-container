#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
SOURCE_DIR="$TMPDIR/source"
DEVELOPMENT_ROOT="$TMPDIR/opencode-development"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$SOURCE_DIR/packages/opencode" "$DEVELOPMENT_ROOT"

assert_contains() {
  local file="$1" needle="$2" message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nmissing: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1" needle="$2" message="$3"
  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\nfile: %s\n' "$message" "$needle" "$file" >&2
    exit 1
  fi
}

assert_line_order() {
  local file="$1" first="$2" second="$3" message="$4"
  local first_line second_line
  first_line="$(grep -Fn -- "$first" "$file" | cut -d: -f1 | head -n 1)"
  second_line="$(grep -Fn -- "$second" "$file" | cut -d: -f1 | head -n 1)"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    printf 'assertion failed: %s\nfirst: %s\nsecond: %s\nfile: %s\n' "$message" "$first" "$second" "$file" >&2
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

assert_rejects() {
  local command="$1" expected="$2" output_file="$3"
  if sh -lc "$command" > "$output_file" 2>&1; then
    printf 'assertion failed: command should have failed\ncommand: %s\n' "$command" >&2
    exit 1
  fi
  assert_contains "$output_file" "$expected" "command reports the expected failure"
}

assert_command_fails() {
  local command="$1" output_file="$2"
  if sh -lc "$command" > "$output_file" 2>&1; then
    printf 'assertion failed: command should have failed\ncommand: %s\n' "$command" >&2
    exit 1
  fi
}

reset_git_mock_state() {
  unset GIT_MOCK_DIFF_STATE GIT_MOCK_UNTRACKED GIT_MOCK_GIT_DIR GIT_MOCK_COMMON_DIR GIT_MOCK_BRANCH GIT_MOCK_HAS_UPSTREAM GIT_MOCK_AHEAD GIT_MOCK_BEHIND GIT_MOCK_TOPLEVEL
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
    case "${GIT_MOCK_DIFF_STATE:-clean}" in
      unstaged)
        if [[ "${2-}" != "--cached" ]]; then
          exit 1
        fi
        exit 0
        ;;
      staged)
        if [[ "${2-}" == "--cached" ]]; then
          exit 1
        fi
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  ls-files)
    if [[ "${GIT_MOCK_UNTRACKED:-0}" == "1" ]]; then
      printf 'untracked.txt\n'
    fi
    exit 0
    ;;
  log)
    printf '20260410-163440-ab12cd3\n'
    ;;
  rev-parse)
    case "$2" in
      --git-dir)
        printf '%s\n' "${GIT_MOCK_GIT_DIR:-.git}"
        ;;
      --git-common-dir)
        printf '%s\n' "${GIT_MOCK_COMMON_DIR:-.git}"
        ;;
      --abbrev-ref)
        if [[ "$*" == *"@{upstream}"* || "$*" == *"@{u}"* ]]; then
          if [[ "${GIT_MOCK_HAS_UPSTREAM:-1}" == "1" ]]; then
            printf 'origin/main\n'
          else
            exit 1
          fi
        else
          printf '%s\n' "${GIT_MOCK_BRANCH:-main}"
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
  rev-list)
    if [[ "$*" == *"--left-right --count @{upstream}...HEAD"* ]]; then
      printf '%s\t%s\n' "${GIT_MOCK_BEHIND:-0}" "${GIT_MOCK_AHEAD:-0}"
    elif [[ "$*" == *"--count @{u}..HEAD"* ]]; then
      printf '%s\n' "${GIT_MOCK_AHEAD:-0}"
    elif [[ "$*" == *"--count HEAD..@{u}"* ]]; then
      printf '%s\n' "${GIT_MOCK_BEHIND:-0}"
    else
      printf '0\t0\n'
    fi
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
STATE_DIR="${STATE_DIR:?}"
url="${@: -1}"
case "$url" in
  http://127.0.0.1:*/global/health)
    port_part="${url#http://127.0.0.1:}"
    port="${port_part%%/*}"
    for mapping_file in "$STATE_DIR"/port_4096_*; do
      [[ -e "$mapping_file" ]] || continue
      if [[ "$(cat "$mapping_file")" == "127.0.0.1:$port" ]]; then
        container_name="${mapping_file##*/port_4096_}"
        if [[ -f "$STATE_DIR/server_active_$container_name" ]]; then
          printf '{"healthy":true}'
          exit 0
        fi
      fi
    done
    exit 1
    ;;
  */releases/latest)
    printf '{"tag_name":"v1.4.3"}'
    ;;
  */releases)
    printf '[{"tag_name":"v1.4.3","draft":false,"prerelease":false},{"tag_name":"v1.4.2","draft":false,"prerelease":false},{"tag_name":"v1.5.0-beta.1","draft":false,"prerelease":true}]'
    ;;
  https://changelogs.ubuntu.com/meta-release-lts)
    printf 'Dist: noble\nVersion: 24.04\n\nDist: questing\nVersion: 26.04\n'
    ;;
  https://registry.npmjs.org/opencode-linux-x64/1.4.3)
    printf '{"dist":{"tarball":"https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-1.4.3.tgz","integrity":"sha512-RS6TsDqTUrW5sefxD1KD9Xy9mSYGXAlr2DlGrdi8vNm9e/Bt4r4u557VB7f/Uj2CxTt2Gf7OWl08ZoPlxMJ5Gg=="}}'
    ;;
  https://registry.npmjs.org/opencode-linux-x64/1.4.2)
    printf '{"dist":{"tarball":"https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-1.4.2.tgz","integrity":"sha512-RS6TsDqTUrW5sefxD1KD9Xy9mSYGXAlr2DlGrdi8vNm9e/Bt4r4u557VB7f/Uj2CxTt2Gf7OWl08ZoPlxMJ5Gg=="}}'
    ;;
  https://registry.npmjs.org/opencode-linux-arm64/1.4.3)
    printf '{"dist":{"tarball":"https://registry.npmjs.org/opencode-linux-arm64/-/opencode-linux-arm64-1.4.3.tgz","integrity":"sha512-9jpVSOEF7TX3gPPAHVAsBT9XEO3LgYafI+IUmOzbBB9CDiVVNJw6JmEffmSpSxY4nkAh322xnMbNjVGEyXQBRA=="}}'
    ;;
  https://registry.npmjs.org/opencode-linux-arm64/1.4.2)
    printf '{"dist":{"tarball":"https://registry.npmjs.org/opencode-linux-arm64/-/opencode-linux-arm64-1.4.2.tgz","integrity":"sha512-9jpVSOEF7TX3gPPAHVAsBT9XEO3LgYafI+IUmOzbBB9CDiVVNJw6JmEffmSpSxY4nkAh322xnMbNjVGEyXQBRA=="}}'
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
  rm -f "$STATE_DIR/port_4096_$name" "$STATE_DIR/server_active_$name" "$STATE_DIR/mount_home_$name" "$STATE_DIR/mount_workspace_$name" "$STATE_DIR/mount_development_$name"
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
    ubuntu_version=""
    release_url=""
    release_sha512=""
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
            UBUNTU_VERSION=*) ubuntu_version="${2#*=}" ;;
            OPENCODE_RELEASE_ARCHIVE_URL=*) release_url="${2#*=}" ;;
            OPENCODE_RELEASE_ARCHIVE_SHA512=*) release_sha512="${2#*=}" ;;
            OPENCODE_WRAPPER_LANE=*) lane="${2#*=}" ;;
            OPENCODE_WRAPPER_UPSTREAM=*) upstream="${2#*=}" ;;
            OPENCODE_WRAPPER_UPSTREAM_REF=*) upstream_ref="${2#*=}" ;;
            OPENCODE_WRAPPER_CONTEXT=*) wrapper="${2#*=}" ;;
            OPENCODE_WRAPPER_COMMITSTAMP=*) commitstamp="${2#*=}" ;;
          esac
          shift 2
          ;;
        --label)
          case "$2" in
            $LABEL_LANE=*) lane="${2#*=}" ;;
            $LABEL_UPSTREAM=*) upstream="${2#*=}" ;;
            $LABEL_UPSTREAM_REF=*) upstream_ref="${2#*=}" ;;
            $LABEL_WRAPPER=*) wrapper="${2#*=}" ;;
            $LABEL_COMMITSTAMP=*) commitstamp="${2#*=}" ;;
          esac
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    runtime_user="root"
    runtime_home="/root"
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
      '{{range .Mounts}}{{printf "%s\t%s\n" .Destination .Source}}{{end}}')
        [[ -f "$STATE_DIR/mount_home_$name" ]] && printf '/root\t%s\n' "$(cat "$STATE_DIR/mount_home_$name")"
        [[ -f "$STATE_DIR/mount_workspace_$name" ]] && printf '/workspace/opencode-workspace\t%s\n' "$(cat "$STATE_DIR/mount_workspace_$name")"
        [[ -f "$STATE_DIR/mount_development_$name" ]] && printf '/workspace/opencode-development\t%s\n' "$(cat "$STATE_DIR/mount_development_$name")"
        ;;
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
    server_port=""
    home_mount=""
    workspace_mount=""
    development_mount=""
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
        -e|-p)
          case "$2" in
            127.0.0.1::4096) server_port="64096" ;;
            127.0.0.1:*:4096) server_port="${2#127.0.0.1:}"; server_port="${server_port%:4096}" ;;
          esac
          shift 2
          ;;
        -v)
          case "$2" in
            *:/root) home_mount="${2%:/root}" ;;
            *:/workspace/opencode-workspace) workspace_mount="${2%:/workspace/opencode-workspace}" ;;
            *:/workspace/opencode-development) development_mount="${2%:/workspace/opencode-development}" ;;
          esac
          shift 2
          ;;
        --restart|-d)
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
    if [[ -n "$server_port" ]]; then
      printf '%s\n' "127.0.0.1:$server_port" > "$STATE_DIR/port_4096_$name"
    fi
    [[ -n "$home_mount" ]] && printf '%s\n' "$home_mount" > "$STATE_DIR/mount_home_$name"
    [[ -n "$workspace_mount" ]] && printf '%s\n' "$workspace_mount" > "$STATE_DIR/mount_workspace_$name"
    [[ -n "$development_mount" ]] && printf '%s\n' "$development_mount" > "$STATE_DIR/mount_development_$name"
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
    container_name="$1"
    shift || true
    if [[ "$*" == *'opencode serve --hostname 0.0.0.0 --port 4096'* ]]; then
      : > "$STATE_DIR/server_active_$container_name"
    fi
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
export OPENCODE_DEVELOPMENT_ROOT="$DEVELOPMENT_ROOT"
export OPENCODE_IMAGE_NAME="opencode-local"
export OPENCODE_HOST_SERVER_PORT="6553"
export OPENCODE_SELECT_INDEX=1
export OPENCODE_COMMITSTAMP_OVERRIDE="20260410-163440-ab12cd3"
export OPENCODE_SOURCE_OVERRIDE_DIR="$SOURCE_DIR"
export OPENCODE_SKIP_BUILD_CONTEXT_CHECK=1

source "$ROOT/lib/shell/common.sh"
assert_eq $'1.4.3\n1.4.2' "$(list_release_tags)" 'release list resolves from GitHub API output and excludes prereleases'
assert_eq '1.4.3' "$(latest_release_tag)" 'latest release resolves from GitHub API output'
assert_eq '26.04' "$(latest_ubuntu_lts_version)" 'latest Ubuntu LTS resolves from Ubuntu metadata'
NO_PYTHON_BIN="$TMPDIR/no-python-bin"
mkdir -p "$NO_PYTHON_BIN"
ln -sf "$(command -v bash)" "$NO_PYTHON_BIN/bash"
ln -sf "$(command -v dirname)" "$NO_PYTHON_BIN/dirname"
ln -sf "$MOCK_BIN/podman" "$NO_PYTHON_BIN/podman"
assert_command_fails "env PATH='$NO_PYTHON_BIN' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' '$ROOT/scripts/shared/opencode-build' test 1.4.3" "$STATE_DIR/build-no-python.out"
assert_contains "$STATE_DIR/build-no-python.out" 'python3 is required' 'build fails early with a clear prerequisite error when python3 is missing'

"$ROOT/scripts/shared/opencode-build" test 1.4.3 > "$STATE_DIR/build.out"
assert_contains "$STATE_DIR/build.out" 'Notice: newer Ubuntu LTS available (26.04); build continues with pinned Ubuntu LTS 24.04' 'build notifies when the Ubuntu LTS pin is behind'
assert_contains "$STATE_DIR/build.out" 'Build source: official release v1.4.3' 'build uses the official stable release artefact for exact releases'
assert_contains "$STATE_DIR/build.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'build creates immutable image ref'
assert_contains "$STATE_DIR/podman.log" 'UBUNTU_VERSION=24.04' 'release build uses the pinned Ubuntu LTS version'

(cd "$TMPDIR" && "$ROOT/scripts/shared/opencode-build" test 1.4.3 > "$STATE_DIR/build-outside-repo.out")
assert_contains "$STATE_DIR/build-outside-repo.out" 'Image already exists: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'build uses repository workdir even when launched from outside the repo'

env OPENCODE_COMMITSTAMP_OVERRIDE='20260410-170000-deffeed' "$ROOT/scripts/shared/opencode-build" test > "$STATE_DIR/build-default.out"
assert_contains "$STATE_DIR/build-default.out" 'Build source: official release v1.4.3' 'build defaults to the latest stable official release when no upstream is given'
assert_contains "$STATE_DIR/build-default.out" 'Built image: opencode-local:test-1.4.3-main-20260410-170000-deffeed' 'default build resolves to the latest stable release identity'

"$ROOT/scripts/shared/opencode-build" test main > "$STATE_DIR/build-main.out"
assert_contains "$STATE_DIR/build-main.out" 'Build source: upstream source ref main' 'main build uses upstream source ref'
assert_contains "$STATE_DIR/build-main.out" 'Built image: opencode-local:test-main-main-20260410-163440-ab12cd3' 'main build creates immutable image ref'
assert_contains "$STATE_DIR/podman.log" 'Containerfile.source-base' 'main build uses source-base containerfile'

"$ROOT/scripts/shared/opencode-build" test 1.4.2 > "$STATE_DIR/build-fallback.out"
assert_contains "$STATE_DIR/build-fallback.out" 'Build source: official release v1.4.2' 'exact stable releases use the official release artefact path'

reset_git_mock_state
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_DIFF_STATE=unstaged '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'working tree has unstaged changes' "$STATE_DIR/build-production-unstaged.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_DIFF_STATE=staged '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'working tree has staged changes' "$STATE_DIR/build-production-staged.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_UNTRACKED=1 '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'working tree has untracked files' "$STATE_DIR/build-production-untracked.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_BRANCH=feature '$ROOT/scripts/shared/opencode-build' production 1.4.3" "production builds must run from branch 'main'" "$STATE_DIR/build-production-branch.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_HAS_UPSTREAM=0 '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'production builds require a tracking branch' "$STATE_DIR/build-production-upstream.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_AHEAD=1 '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'production builds require the canonical main checkout to be in sync with its upstream' "$STATE_DIR/build-production-ahead.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_BEHIND=1 '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'production builds require the canonical main checkout to be in sync with its upstream' "$STATE_DIR/build-production-behind.out"
assert_rejects "env PATH='$PATH' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK= GIT_MOCK_GIT_DIR='.git/worktrees/feat' GIT_MOCK_COMMON_DIR='.git' '$ROOT/scripts/shared/opencode-build' production 1.4.3" 'production builds must run from the canonical main checkout' "$STATE_DIR/build-production-worktree.out"
env PATH="$PATH" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK= "$ROOT/scripts/shared/opencode-build" production 1.4.3 > "$STATE_DIR/build-production-clean.out"
assert_contains "$STATE_DIR/build-production-clean.out" 'Built image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'production build succeeds only when the checkout is clean and in sync'
reset_git_mock_state

"$ROOT/scripts/shared/opencode-start" general test 1.4.3 > "$STATE_DIR/start.out"
assert_contains "$STATE_DIR/start.out" 'Container: opencode-general-test-1.4.3-main' 'start prints deterministic container name'
assert_not_contains "$STATE_DIR/start.out" 'Server: http://127.0.0.1:' 'start does not report a server URL when host server port is unset'
assert_contains "$STATE_DIR/start.out" 'Workspace Dir: /workspace/opencode-workspace' 'start prints container workspace dir'
assert_contains "$STATE_DIR/podman.log" '--name opencode-general-test-1.4.3-main' 'run uses deterministic container name'
assert_not_contains "$STATE_DIR/podman.log" '-p 127.0.0.1::4096' 'start does not publish a random host server port when unset'
assert_contains "$STATE_DIR/podman.log" "$TMPDIR/workspaces/general/opencode-home:/root" 'owned Ubuntu runtime mounts workspace home at the fixed runtime home'
assert_contains "$STATE_DIR/podman.log" "$TMPDIR/workspaces/general/opencode-workspace:/workspace/opencode-workspace" 'run mounts workspace dir'
assert_contains "$STATE_DIR/podman.log" "$DEVELOPMENT_ROOT:/workspace/opencode-development" 'run mounts configured development root'
assert_not_contains "$STATE_DIR/podman.log" '-p 127.0.0.1:6553:4096' 'global OPENCODE_HOST_SERVER_PORT environment does not override per-workspace server config'

rm -rf "$DEVELOPMENT_ROOT"
: > "$STATE_DIR/podman.log"
"$ROOT/scripts/shared/opencode-start" general test 1.4.3 > "$STATE_DIR/start-nodevroot.out"
assert_not_contains "$STATE_DIR/podman.log" '/workspace/opencode-development' 'release containers can start without a configured development mount root'
mkdir -p "$DEVELOPMENT_ROOT"

"$ROOT/scripts/shared/opencode-start" sourcey test 1.4.2 > "$STATE_DIR/start-source.out"
assert_contains "$STATE_DIR/podman.log" "$TMPDIR/workspaces/sourcey/opencode-home:/root" 'release-built and source-built runtimes share the same fixed runtime home'
podman rm -f opencode-sourcey-test-1.4.2-main >/dev/null

mkdir -p "$TMPDIR/workspaces/fixed/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/fixed/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5096
EOF
"$ROOT/scripts/shared/opencode-start" fixed test 1.4.3 > "$STATE_DIR/start-fixed-port.out"
assert_contains "$STATE_DIR/start-fixed-port.out" 'Server: http://127.0.0.1:5096' 'start reports fixed mapped server port when configured'
assert_contains "$STATE_DIR/podman.log" '-p 127.0.0.1:5096:4096' 'start uses configured fixed host server port'
assert_contains "$STATE_DIR/podman.log" 'exec opencode-fixed-test-1.4.3-main /bin/sh -lc' 'start launches managed server inside the configured-port container'

mkdir -p "$TMPDIR/workspaces/safe/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/safe/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5097
MALICIOUS=$(touch /tmp/should-not-run)
EOF
"$ROOT/scripts/shared/opencode-start" safe test 1.4.3 > "$STATE_DIR/start-safe-port.out"
assert_contains "$STATE_DIR/start-safe-port.out" 'Server: http://127.0.0.1:5097' 'start reads configured server port from assignment-only env parsing'
test ! -e /tmp/should-not-run

mkdir -p "$TMPDIR/workspaces/lastwins/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/lastwins/opencode-workspace/.config/opencode/config.env" <<'EOF'
export   OPENCODE_HOST_SERVER_PORT=5088
OPENCODE_HOST_SERVER_PORT=5089
EOF
"$ROOT/scripts/shared/opencode-start" lastwins test 1.4.3 > "$STATE_DIR/start-lastwins.out"
assert_contains "$STATE_DIR/start-lastwins.out" 'Server: http://127.0.0.1:5089' 'start uses the last matching assignment and accepts spaced export syntax in config env'

mkdir -p "$TMPDIR/workspaces/quoted/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/quoted/opencode-workspace/.config/opencode/config.env" <<'EOF'
export OPENCODE_HOST_SERVER_PORT="5087" # comment
EOF
"$ROOT/scripts/shared/opencode-start" quoted test 1.4.3 > "$STATE_DIR/start-quoted.out"
assert_contains "$STATE_DIR/start-quoted.out" 'Server: http://127.0.0.1:5087' 'start accepts quoted host server ports with inline comments'

mkdir -p "$TMPDIR/workspaces/badport/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/badport/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=abc
EOF
assert_command_fails "env PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' '$ROOT/scripts/shared/opencode-start' badport test 1.4.3" "$STATE_DIR/start-badport.out"
assert_not_contains "$STATE_DIR/podman.log" '--name opencode-badport-test-1.4.3-main' 'invalid port values fail before podman run'

mkdir -p "$TMPDIR/workspaces/portzero/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/portzero/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=0
EOF
assert_command_fails "env PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' '$ROOT/scripts/shared/opencode-start' portzero test 1.4.3" "$STATE_DIR/start-portzero.out"

mkdir -p "$TMPDIR/workspaces/portbig/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/portbig/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=65536
EOF
assert_command_fails "env PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' '$ROOT/scripts/shared/opencode-start' portbig test 1.4.3" "$STATE_DIR/start-portbig.out"

mkdir -p "$TMPDIR/workspaces/secretive/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/secretive/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5091
EOF
cat > "$TMPDIR/workspaces/secretive/opencode-workspace/.config/opencode/secrets.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5099
EOF
"$ROOT/scripts/shared/opencode-start" secretive test 1.4.3 > "$STATE_DIR/start-secretive.out"
assert_contains "$STATE_DIR/start-secretive.out" 'Server: http://127.0.0.1:5099' 'secrets env overrides config env for the managed server port'
assert_contains "$STATE_DIR/podman.log" '-p 127.0.0.1:5099:4096' 'secrets env override is used for published server port'

mkdir -p "$TMPDIR/workspaces/disabled/opencode-workspace/.config/opencode"
cat > "$TMPDIR/workspaces/disabled/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5094
EOF
cat > "$TMPDIR/workspaces/disabled/opencode-workspace/.config/opencode/secrets.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=
EOF
"$ROOT/scripts/shared/opencode-start" disabled test 1.4.3 > "$STATE_DIR/start-disabled.out"
assert_not_contains "$STATE_DIR/start-disabled.out" 'Server: http://127.0.0.1:' 'empty secrets env assignment disables a configured server port'

mkdir -p "$TMPDIR/workspaces/second/opencode-workspace/.config/opencode"
"$ROOT/scripts/shared/opencode-start" second test 1.4.3 > "$STATE_DIR/start-second.out"
assert_not_contains "$STATE_DIR/start-second.out" 'Server: http://127.0.0.1:' 'server port does not leak from one workspace to the next'

cat > "$TMPDIR/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5098
EOF
"$ROOT/scripts/shared/opencode-start" general test 1.4.3 > "$STATE_DIR/start-general-fixed.out"
assert_contains "$STATE_DIR/start-general-fixed.out" 'Server: http://127.0.0.1:5098' 'restarting after adding a configured host server port recreates the container and starts the managed server'
assert_contains "$STATE_DIR/podman.log" '-p 127.0.0.1:5098:4096' 'reconfigured workspace recreates container with the configured host server port'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-normalize-test-1.4.3-main' normalize test 1.4.3 main 20260410-163440-ab12cd3 true 'localhost/opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' > "$STATE_DIR/containers.tsv"
assert_eq 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' "$(container_image_ref opencode-normalize-test-1.4.3-main)" 'container image refs are normalised before runtime comparisons'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-remount-test-1.4.3-main' remount test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' > "$STATE_DIR/containers.tsv"
printf '%s\n' "$TMPDIR/workspaces/remount/opencode-home" > "$STATE_DIR/mount_home_opencode-remount-test-1.4.3-main"
printf '%s\n' "$TMPDIR/workspaces/remount/opencode-workspace" > "$STATE_DIR/mount_workspace_opencode-remount-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT-old" > "$STATE_DIR/mount_development_opencode-remount-test-1.4.3-main"
: > "$STATE_DIR/podman.log"
"$ROOT/scripts/shared/opencode-start" remount test 1.4.3 > "$STATE_DIR/start-remount.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f opencode-remount-test-1.4.3-main' 'start recreates the container when the configured development mount changes'
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' > "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-test-1.4.3-main' second test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-stray-test-1.4.3-main' '' '' '' '' '' true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
assert_not_contains <(project_container_rows) 'opencode-stray-test-1.4.3-main' 'unlabelled prefix-matching containers are ignored by project container discovery'

podman rm -f opencode-fixed-test-1.4.3-main >/dev/null

"$ROOT/scripts/shared/opencode-open" general test 1.4.3 --help > "$STATE_DIR/open.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-general-test-1.4.3-main /bin/sh -lc' 'open execs through wrapper shell'
assert_contains "$STATE_DIR/podman.log" 'exec opencode "$@"' 'open forwards OpenCode arguments'

OPENCODE_WRAPPER_CONTEXT_OVERRIDE=feature-xyz "$ROOT/scripts/shared/opencode-open" general test 1.4.3 -- --help > "$STATE_DIR/open-explicit-context.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-general-test-1.4.3-main /bin/sh -lc' 'explicit open resolves existing containers independently of the caller wrapper context'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-solo-test-1.4.3-main' solo test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
printf '1\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-logs" solo --tail 3 > "$STATE_DIR/logs-solo-picker.out" 2>&1
assert_contains "$STATE_DIR/logs-solo-picker.out" "Select a container for workspace 'solo'" 'logs shows picker UI even with a single matching container'
assert_contains "$STATE_DIR/logs-solo-picker.out" 'lane  upstream  wrapper  commit                   status' 'logs single-container picker shows aligned headers'
printf '1\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-status" solo > "$STATE_DIR/status-solo-picker.out" 2>&1
assert_contains "$STATE_DIR/status-solo-picker.out" "Select a container for workspace 'solo'" 'status shows picker UI even with a single matching container'
assert_contains "$STATE_DIR/status-solo-picker.out" 'Status: running' 'status still resolves the selected single container'
printf '1\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-shell" solo -- env > "$STATE_DIR/shell-solo-picker.out" 2>&1
assert_contains "$STATE_DIR/shell-solo-picker.out" "Select a container for workspace 'solo'" 'shell shows picker UI even with a single matching container'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-solo-test-1.4.3-main /bin/sh -lc' 'shell runs against the selected single container'
printf '1\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-open" solo -- --help > "$STATE_DIR/open-solo-picker.out" 2>&1
assert_contains "$STATE_DIR/open-solo-picker.out" "Select a container for workspace 'solo'" 'open shows picker UI even with a single matching container'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-solo-test-1.4.3-main /bin/sh -lc' 'open runs against the selected single container'
printf '1\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-stop" solo > "$STATE_DIR/stop-solo-picker.out" 2>&1
assert_contains "$STATE_DIR/stop-solo-picker.out" "Select a container for workspace 'solo'" 'stop shows picker UI even with a single matching container'
assert_contains "$STATE_DIR/stop-solo-picker.out" 'Stopped container: opencode-solo-test-1.4.3-main' 'stop still stops the selected single container'

"$ROOT/scripts/shared/opencode-shell" second -- test arg > "$STATE_DIR/shell-delimiter.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-second-test-1.4.3-main /bin/sh -lc' 'shell accepts -- to separate wrapper arguments from command arguments'

"$ROOT/scripts/shared/opencode-bootstrap" second --version > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-second-test-1.4.3-main /bin/sh -lc' 'bootstrap reuses the resolved target and opens OpenCode in the same container'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260409-120000-deadbee' test 1.4.3 v1.4.3 main 20260409-120000-deadbee > "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-picker-test-1.4.3-main' picker test 1.4.3 main 20260409-120000-deadbee true 'opencode-local:test-1.4.3-main-20260409-120000-deadbee' > "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=2 "$ROOT/scripts/shared/opencode-start" picker > "$STATE_DIR/start-picker.out"
assert_contains "$STATE_DIR/start-picker.out" 'Container: opencode-picker-test-1.4.3-main' 'start can select an image row and create the matching workspace container'
assert_contains "$STATE_DIR/podman.log" 'rm -f opencode-picker-test-1.4.3-main' 'selecting a newer image row replaces the stale workspace container'
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-test-1.4.3-main' second test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"

"$ROOT/scripts/shared/opencode-logs" second --tail 5 > "$STATE_DIR/logs.out"
assert_contains "$STATE_DIR/podman.log" 'logs --tail 5 opencode-second-test-1.4.3-main' 'logs forwards podman log arguments to the resolved workspace container'

"$ROOT/scripts/shared/opencode-status" second > "$STATE_DIR/status.out"
assert_contains "$STATE_DIR/status.out" 'Lane: test' 'status reports lane'
assert_contains "$STATE_DIR/status.out" 'Upstream: 1.4.3' 'status reports upstream'
assert_not_contains "$STATE_DIR/status.out" 'Server: http://127.0.0.1:' 'status does not report a server URL for workspaces without configured host server ports'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-production-1.4.3-main' second production 1.4.3 main 20260410-163440-ab12cd3 false 'opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=2 "$ROOT/scripts/shared/opencode-logs" second --tail 7 > "$STATE_DIR/logs-second-picker.out"
assert_contains "$STATE_DIR/podman.log" 'logs --tail 7 opencode-second-production-1.4.3-main' 'logs can select among multiple matching containers'
OPENCODE_SELECT_INDEX=2 "$ROOT/scripts/shared/opencode-status" second > "$STATE_DIR/status-second-picker.out"
assert_contains "$STATE_DIR/status-second-picker.out" 'Lane: production' 'status can select among multiple matching containers without tripping nounset array handling'
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-shell" second -- env > "$STATE_DIR/shell-second-picker.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-second-test-1.4.3-main /bin/sh -lc' 'shell can select among multiple matching containers'

"$ROOT/scripts/shared/opencode-status" general > "$STATE_DIR/status-general.out"
assert_contains "$STATE_DIR/status-general.out" 'Server: http://127.0.0.1:5098' 'status reports the verified server URL for workspaces with configured host server ports'

rm -f "$STATE_DIR/server_active_opencode-general-test-1.4.3-main"
"$ROOT/scripts/shared/opencode-status" general > "$STATE_DIR/status-general-recovered.out"
assert_contains "$STATE_DIR/status-general-recovered.out" 'Server: http://127.0.0.1:5098' 'status restarts the managed server when the configured-port container is still running but the server is down'
assert_contains "$STATE_DIR/podman.log" 'exec opencode-general-test-1.4.3-main /bin/sh -lc' 'status triggers managed server recovery inside the configured-port container'

"$ROOT/scripts/shared/opencode-stop" general > "$STATE_DIR/stop.out"
assert_contains "$STATE_DIR/stop.out" 'Stopped container: opencode-general-test-1.4.3-main' 'stop stops running container'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-feature-xyz-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 feature-xyz 20260410-163440-ab12cd3 >> "$STATE_DIR/images.tsv"
OPENCODE_WRAPPER_CONTEXT_OVERRIDE=feature-xyz "$ROOT/scripts/shared/opencode-start" branchy test 1.4.3 --version > "$STATE_DIR/start-with-args.out"
assert_contains "$STATE_DIR/podman.log" '--name opencode-branchy-test-1.4.3-feature-xyz' 'start with args creates the selected wrapper-context container'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/opencode-workspace opencode-branchy-test-1.4.3-feature-xyz /bin/sh -lc' 'start with args forwards directly into the selected container'
assert_not_contains "$STATE_DIR/podman.log" 'opencode-open' 'start with args does not re-resolve the target through opencode-open'
podman rm -f opencode-branchy-test-1.4.3-feature-xyz >/dev/null

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' > "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false 'opencode-local:test-1.4.3-main-20260408-090000-cafebabe' >> "$STATE_DIR/containers.tsv"
printf '4\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-remove" containers > "$STATE_DIR/remove-container-ui.out" 2>&1
assert_contains "$STATE_DIR/remove-container-ui.out" 'selection                         workspace  lane        upstream  wrapper  commit                   status' 'remove containers shows aligned headers'
assert_contains "$STATE_DIR/remove-container-ui.out" 'opencode-general-test-1.4.3-main  general    test        1.4.3     main     20260410-163440-ab12cd3  true' 'remove containers uses aligned container rows'
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' > "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false 'opencode-local:test-1.4.3-main-20260408-090000-cafebabe' >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=4 "$ROOT/scripts/shared/opencode-remove" containers > "$STATE_DIR/remove-container.out"
assert_contains "$STATE_DIR/remove-container.out" 'Removed container: opencode-general-test-1.4.3-main' 'remove container removes selected container'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 > "$STATE_DIR/images.tsv"
printf '3\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-remove" images > "$STATE_DIR/remove-image-ui.out" 2>&1
assert_contains "$STATE_DIR/remove-image-ui.out" '-          test        1.4.3     main     20260410-163440-ab12cd3  image only' 'remove images keeps image rows aligned under the metadata columns'
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 > "$STATE_DIR/images.tsv"
OPENCODE_SELECT_INDEX=3 "$ROOT/scripts/shared/opencode-remove" images > "$STATE_DIR/remove-image.out"
assert_contains "$STATE_DIR/remove-image.out" 'Removed image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'remove image removes selected image'

IMG_EZ_NEW='opencode-local:production-1.4.3-main-20260410-163440-ab12cd3'
IMG_EZ_OLD='opencode-local:production-1.4.2-main-20260409-120000-deadbee'
IMG_NA='opencode-local:test-1.4.3-main-20260408-090000-cafebabe'
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_OLD" production 1.4.2 v1.4.2 main 20260409-120000-deadbee >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" images > "$STATE_DIR/remove-image-all-but-newest.out"
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Keeping image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'remove image all-but-newest keeps newest associated ezirius image'
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Keeping image: opencode-local:test-1.4.3-main-20260408-090000-cafebabe' 'remove image all-but-newest keeps newest associated nala image'
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Removed image: opencode-local:production-1.4.2-main-20260409-120000-deadbee' 'remove image all-but-newest removes older associated image'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.2-main' general test 1.4.2 main 20260409-120000-deadbee false "$IMG_EZ_OLD" >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" containers > "$STATE_DIR/remove-container-all-but-newest.out"
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Keeping container: opencode-general-production-1.4.3-main' 'remove container all-but-newest keeps newest container for general'
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Removed container: opencode-general-test-1.4.2-main' 'remove container all-but-newest removes older general container'
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Keeping container: opencode-nala-test-1.4.3-main' 'remove container all-but-newest keeps newest container for nala'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 > "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_OLD" production 1.4.2 v1.4.2 main 20260409-120000-deadbee >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" > "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.2-main' general test 1.4.2 main 20260409-120000-deadbee false "$IMG_EZ_OLD" >> "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" > "$STATE_DIR/remove-mixed-all-but-newest.out"
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping container: opencode-general-production-1.4.3-main' 'mixed remove keeps newest general container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping container: opencode-nala-test-1.4.3-main' 'mixed remove keeps newest nala container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'mixed remove keeps image serving kept general container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping image: opencode-local:test-1.4.3-main-20260408-090000-cafebabe' 'mixed remove keeps image serving kept nala container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Removed image: opencode-local:production-1.4.2-main-20260409-120000-deadbee' 'mixed remove removes image not serving kept containers'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 > "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >> "$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" > "$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >> "$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=2 "$ROOT/scripts/shared/opencode-remove" > "$STATE_DIR/remove-mixed-all.out"
assert_contains "$STATE_DIR/remove-mixed-all.out" 'Removed container: opencode-general-production-1.4.3-main' 'mixed remove all removes containers first'
assert_contains "$STATE_DIR/remove-mixed-all.out" 'Removed container: opencode-nala-test-1.4.3-main' 'mixed remove all removes all containers'
assert_contains "$STATE_DIR/remove-mixed-all.out" 'Removed image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'mixed remove all removes images after containers'
assert_line_order "$STATE_DIR/remove-mixed-all.out" 'Removed container: opencode-general-production-1.4.3-main' 'Removed image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'mixed remove all removes containers before images'

echo "Runtime checks passed"
