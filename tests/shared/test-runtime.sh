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
	if sh -lc "$command" >"$output_file" 2>&1; then
		printf 'assertion failed: command should have failed\ncommand: %s\n' "$command" >&2
		exit 1
	fi
	assert_contains "$output_file" "$expected" "command reports the expected failure"
}

assert_command_fails() {
	local command="$1" output_file="$2"
	if sh -lc "$command" >"$output_file" 2>&1; then
		printf 'assertion failed: command should have failed\ncommand: %s\n' "$command" >&2
		exit 1
	fi
}

prepare_build_test_root() {
	local destination="$1"
	mkdir -p "$destination/config/shared" "$destination/config/containers" "$destination/lib/shell" "$destination/scripts/shared"
	cp "$ROOT/config/shared/opencode.conf" "$destination/config/shared/opencode.conf"
	cp "$ROOT/config/shared/tool-versions.conf" "$destination/config/shared/tool-versions.conf"
	cp "$ROOT/config/containers/Containerfile.wrapper" "$destination/config/containers/Containerfile.wrapper"
	cp "$ROOT/config/containers/Containerfile.source-base.template" "$destination/config/containers/Containerfile.source-base.template"
	cp "$ROOT/config/containers/entrypoint.sh" "$destination/config/containers/entrypoint.sh"
	cp "$ROOT/lib/shell/common.sh" "$destination/lib/shell/common.sh"
	cp "$ROOT/scripts/shared/opencode-build" "$destination/scripts/shared/opencode-build"
	chmod +x "$destination/scripts/shared/opencode-build"
}

reset_git_mock_state() {
	unset GIT_MOCK_DIFF_STATE GIT_MOCK_UNTRACKED GIT_MOCK_GIT_DIR GIT_MOCK_COMMON_DIR GIT_MOCK_BRANCH GIT_MOCK_HAS_UPSTREAM GIT_MOCK_AHEAD GIT_MOCK_BEHIND GIT_MOCK_TOPLEVEL
}

cat >"$MOCK_BIN/git" <<'EOF'
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

cat >"$MOCK_BIN/curl" <<'EOF'
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
    if [[ -n "${MOCK_LATEST_RELEASE_SEQUENCE:-}" ]]; then
      sequence_file="$STATE_DIR/mock-latest-release-sequence"
      if [[ ! -f "$sequence_file" ]]; then
        printf '%s\n' "$MOCK_LATEST_RELEASE_SEQUENCE" | tr ',' '\n' >"$sequence_file"
      fi
      tag_name="$(sed -n '1p' "$sequence_file")"
      sed -i '1d' "$sequence_file"
      printf '{"tag_name":"%s"}' "$tag_name"
    else
      printf '{"tag_name":"v1.4.3"}'
    fi
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

cat >"$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1-}" == "-c" ]] || {
  printf 'unexpected python3 invocation: %s\n' "$*" >&2
  exit 1
}

script="${2-}"

if [[ "$script" == *'item.get("tag_name")'* ]]; then
  perl -0ne '
    while (/\{[^{}]*"tag_name":"([^"]+)"[^{}]*"draft":(true|false)[^{}]*"prerelease":(true|false)[^{}]*\}/g) {
      my ($tag, $draft, $prerelease) = ($1, $2, $3);
      next if $draft eq q(true) || $prerelease eq q(true);
      $tag =~ s/^\s+|\s+$//g;
      print "$tag\n" if length $tag;
    }
  '
  exit 0
fi

if [[ "$script" == *'failed to resolve latest OpenCode release'* ]]; then
  perl -0ne '
    /"tag_name":"([^"]+)"/ or die "failed to resolve latest OpenCode release\n";
    my $tag = $1;
    $tag =~ s/^\s+|\s+$//g;
    die "failed to resolve latest OpenCode release\n" unless length $tag;
    print "$tag\n";
  '
  exit 0
fi

if [[ "$script" == *'failed to resolve latest Ubuntu LTS version'* ]]; then
  perl -e '
    my @versions;
    while (<STDIN>) {
      if (/^Version:\s*([0-9]+)\.([0-9]+)/) {
        push @versions, [$1 + 0, $2 + 0];
      }
    }
    die "failed to resolve latest Ubuntu LTS version\n" unless @versions;
    @versions = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @versions;
    printf "%d.%02d\n", $versions[-1][0], $versions[-1][1];
  '
  exit 0
fi

if [[ "$script" == *'failed to resolve package tarball url'* ]]; then
  perl -0ne '
    /"tarball":"([^"]+)"/ or die "failed to resolve package tarball url\n";
    my $url = $1;
    $url =~ s/^\s+|\s+$//g;
    die "failed to resolve package tarball url\n" unless length $url;
    print "$url\n";
  '
  exit 0
fi

if [[ "$script" == *'failed to resolve package sha512 integrity'* ]]; then
  integrity_line="$(sed -n 's/.*"integrity":"\(sha512-[^"]*\)".*/\1/p')"
  [[ "$integrity_line" == sha512-* ]] || {
    printf 'failed to resolve package sha512 integrity\n' >&2
    exit 1
  }
  printf '%s' "${integrity_line#sha512-}" | base64 -d | od -An -v -tx1 | tr -d ' \n'
  printf '\n'
  exit 0
fi

printf 'unexpected python3 script\n' >&2
exit 1
EOF
chmod +x "$MOCK_BIN/python3"

cat >"$MOCK_BIN/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == '-u' ]]; then
  printf '%s\n' "${ID_MOCK_UID:-$(/usr/bin/id -u)}"
  exit 0
fi
if [[ "${1-}" == '-g' ]]; then
  printf '%s\n' "${ID_MOCK_GID:-$(/usr/bin/id -g)}"
  exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod +x "$MOCK_BIN/id"

cat >"$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${STATE_DIR:?}"
RUNTIME_HOME="${OPENCODE_EXPECTED_RUNTIME_HOME:?}"
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
LABEL_HOST_UID="opencode.wrapper.host_uid"
LABEL_HOST_GID="opencode.wrapper.host_gid"
LABEL_UBUNTU_VERSION="opencode.wrapper.ubuntu_version"

image_runtime_user() {
  local ref="$1"
  local record
  record="$(image_record "$ref")"
  IFS=$'\t' read -r _ _ _ _ _ _ runtime_user runtime_home <<< "$record"
  if [[ -n "$runtime_user" ]]; then
    printf '%s\n' "$runtime_user"
    return 0
  fi
  printf 'opencode\n'
}

image_runtime_home() {
  local ref="$1"
  local record
  record="$(image_record "$ref")"
  IFS=$'\t' read -r _ _ _ _ _ _ runtime_user runtime_home _ _ workdir <<< "$record"
  if [[ -n "$runtime_home" ]]; then
    printf '%s\n' "$runtime_home"
    return 0
  fi
  printf '%s\n' "$RUNTIME_HOME"
}

image_workdir() {
  local ref="$1"
  local record
  record="$(image_record "$ref")"
  IFS=$'\t' read -r _ _ _ _ _ _ runtime_user runtime_home host_uid host_gid workdir ubuntu_version <<< "$record"
  if [[ -n "$workdir" ]]; then
    printf '%s\n' "$workdir"
    return 0
  fi
  printf '/workspace/opencode-workspace\n'
}

image_ubuntu_version() {
  local ref="$1"
  local record
  record="$(image_record "$ref")"
  IFS=$'\t' read -r _ _ _ _ _ _ runtime_user runtime_home host_uid host_gid workdir ubuntu_version <<< "$record"
  if [[ -n "$ubuntu_version" ]]; then
    printf '%s\n' "$ubuntu_version"
    return 0
  fi
  printf '24.04\n'
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
  rm -f "$STATE_DIR/port_4096_$name" "$STATE_DIR/server_active_$name" "$STATE_DIR/mount_home_$name" "$STATE_DIR/mount_workspace_$name" "$STATE_DIR/mount_development_$name" "$STATE_DIR/mount_project_$name"
}

set_container_running_state() {
  local name="$1"
  local desired_status="$2"
  local record
  record="$(container_record "$name")"
  [[ -n "$record" ]] || return 1
  IFS=$'\t' read -r cname workspace lane upstream wrapper commitstamp _status image_ref <<< "$record"
  grep -Fv "${name}"$'\t' "$CONTAINERS_FILE" > "$CONTAINERS_FILE.tmp" || true
  mv "$CONTAINERS_FILE.tmp" "$CONTAINERS_FILE"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$cname" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp" "$desired_status" "$image_ref" >> "$CONTAINERS_FILE"
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
    host_uid=""
    host_gid=""
    workdir="/workspace/opencode-workspace"
    ubuntu_version="24.04"
    runtime_user="opencode"
    runtime_home="$RUNTIME_HOME"
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
            $LABEL_HOST_UID=*) host_uid="${2#*=}" ;;
            $LABEL_HOST_GID=*) host_gid="${2#*=}" ;;
            $LABEL_UBUNTU_VERSION=*) ubuntu_version="${2#*=}" ;;
          esac
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    runtime_user="opencode"
    runtime_home="$RUNTIME_HOME"
    remove_image_record "$target"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$lane" "$upstream" "$upstream_ref" "$wrapper" "$commitstamp" "$runtime_user" "$runtime_home" "$host_uid" "$host_gid" "$workdir" "$ubuntu_version" >> "$IMAGES_FILE"
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
          IFS=$'\t' read -r ref lane upstream upstream_ref wrapper commitstamp runtime_user runtime_home host_uid host_gid workdir ubuntu_version <<< "$record"
          case "$format" in
            *"$LABEL_LANE"*) printf '%s\n' "$lane" ;;
            *"$LABEL_UPSTREAM_REF"*) printf '%s\n' "$upstream_ref" ;;
            *"$LABEL_UPSTREAM"*) printf '%s\n' "$upstream" ;;
            *"$LABEL_WRAPPER"*) printf '%s\n' "$wrapper" ;;
            *"$LABEL_COMMITSTAMP"*) printf '%s\n' "$commitstamp" ;;
            *"$LABEL_HOST_UID"*) printf '%s\n' "$host_uid" ;;
            *"$LABEL_HOST_GID"*) printf '%s\n' "$host_gid" ;;
            *"$LABEL_UBUNTU_VERSION"*) printf '%s\n' "$ubuntu_version" ;;
            '{{.Config.User}}') printf '%s\n' "${runtime_user:-opencode}" ;;
            '{{.Config.WorkingDir}}') printf '%s\n' "${workdir:-/workspace/opencode-workspace}" ;;
            '{{range .Config.Env}}{{println .}}{{end}}') printf 'HOME=%s\n' "${runtime_home:-$RUNTIME_HOME}" ;;
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
        [[ -f "$STATE_DIR/mount_home_$name" ]] && printf '%s\t%s\n' "$RUNTIME_HOME" "$(cat "$STATE_DIR/mount_home_$name")"
        [[ -f "$STATE_DIR/mount_workspace_$name" ]] && printf '/workspace/opencode-workspace\t%s\n' "$(cat "$STATE_DIR/mount_workspace_$name")"
        [[ -f "$STATE_DIR/mount_development_$name" ]] && printf '/workspace/opencode-development\t%s\n' "$(cat "$STATE_DIR/mount_development_$name")"
        if [[ -f "$STATE_DIR/mount_project_$name" && ! -f "$STATE_DIR/hide_project_mount_$name" ]]; then
          printf '/workspace/opencode-project\t%s\n' "$(cat "$STATE_DIR/mount_project_$name")"
        fi
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
    home_env=""
    runtime_home_env=""
    home_mount=""
    workspace_mount=""
    development_mount=""
    project_mount=""
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
            HOME=*) home_env="${2#HOME=}" ;;
            OPENCODE_CONTAINER_RUNTIME_HOME=*) runtime_home_env="${2#OPENCODE_CONTAINER_RUNTIME_HOME=}" ;;
            127.0.0.1::4096) server_port="64096" ;;
            127.0.0.1:*:4096) server_port="${2#127.0.0.1:}"; server_port="${server_port%:4096}" ;;
          esac
          shift 2
          ;;
        -v)
          case "$2" in
            *:"$RUNTIME_HOME") home_mount="${2%:"$RUNTIME_HOME"}" ;;
            *:/workspace/opencode-workspace) workspace_mount="${2%:/workspace/opencode-workspace}" ;;
            *:/workspace/opencode-development) development_mount="${2%:/workspace/opencode-development}" ;;
            *:/workspace/opencode-development:ro) development_mount="${2%:/workspace/opencode-development:ro}" ;;
            *:/workspace/opencode-project) project_mount="${2%:/workspace/opencode-project}" ;;
            *:/workspace/opencode-project:U) project_mount="${2%:/workspace/opencode-project:U}" ;;
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
    [[ -n "$home_env" ]] && printf '%s\n' "$home_env" > "$STATE_DIR/env_home_$name"
    [[ -n "$runtime_home_env" ]] && printf '%s\n' "$runtime_home_env" > "$STATE_DIR/env_runtime_home_$name"
    [[ -n "$home_mount" ]] && printf '%s\n' "$home_mount" > "$STATE_DIR/mount_home_$name"
    [[ -n "$workspace_mount" ]] && printf '%s\n' "$workspace_mount" > "$STATE_DIR/mount_workspace_$name"
    [[ -n "$development_mount" ]] && printf '%s\n' "$development_mount" > "$STATE_DIR/mount_development_$name"
    [[ -n "$project_mount" ]] && printf '%s\n' "$project_mount" > "$STATE_DIR/mount_project_$name"
    ;;
  start)
    log_call "start $*"
    set_container_running_state "$1" true
    ;;
  stop)
    log_call "stop $*"
    set_container_running_state "$1" false
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
assert_not_contains "$MOCK_BIN/podman" '/home/opencode' 'podman test double derives the runtime home from shared config instead of hard-coding it'

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
export ID_MOCK_UID=1001
export ID_MOCK_GID=1001
unset OPENCODE_CONTAINER_RUNTIME_HOME

source "$ROOT/lib/shell/common.sh"
export OPENCODE_EXPECTED_RUNTIME_HOME="$OPENCODE_CONTAINER_RUNTIME_HOME"
export OPENCODE_EXPECTED_HOST_UID="$(host_user_uid)"
export OPENCODE_EXPECTED_HOST_GID="$(host_user_gid)"
assert_eq '/home/opencode' "$OPENCODE_EXPECTED_RUNTIME_HOME" 'runtime home is fixed to the concrete opencode home path'
assert_eq '/home/opencode' "$(bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' OPENCODE_CONTAINER_RUNTIME_HOME='/tmp/not-opencode'; source '$ROOT/lib/shell/common.sh'; runtime_home_dir")" 'shell runtime home ignores conflicting environment overrides'
assert_eq '/workspace/opencode-project' "$(bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' OPENCODE_CONTAINER_PROJECT_DIR='/tmp/not-project'; source '$ROOT/lib/shell/common.sh'; container_project_dir")" 'shell project dir ignores conflicting environment overrides'
mkdir -p "$DEVELOPMENT_ROOT/beta" "$DEVELOPMENT_ROOT/alpha" "$DEVELOPMENT_ROOT/gamma+delta" "$DEVELOPMENT_ROOT/production" "$DEVELOPMENT_ROOT/z-last/deep"
mkdir -p "$DEVELOPMENT_ROOT/repo:old"
mkdir -p "$TMPDIR/external-project"
ln -s "$TMPDIR/external-project" "$DEVELOPMENT_ROOT/outside-link"
touch "$DEVELOPMENT_ROOT/not-a-project.txt"
assert_eq $'alpha\nbeta\ngamma+delta\nproduction\nz-last' "$(project_names_from_development_root)" 'project discovery lists only immediate child directories in alphabetical order'
assert_eq 'beta' "$(resolve_selected_project_name beta)" 'explicit project selection resolves an immediate child project'
assert_eq 'gamma+delta' "$(resolve_selected_project_name 'gamma+delta')" 'explicit project selection allows direct child names beyond workspace-style identifiers'
assert_eq 'production' "$(resolve_selected_project_name production)" 'explicit project selection accepts names that also match wrapper lane values'
assert_eq 'alpha' "$(resolve_selected_project_name --)" 'omitted project selection uses the alphabetical project picker'
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; resolve_selected_project_name 'z-last/deep'" >"$STATE_DIR/project-nested-reject.out" 2>&1; then
	printf 'assertion failed: nested project path should have been rejected\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-nested-reject.out" 'project name must not contain path separators' 'nested project path is rejected before selection'
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; resolve_selected_project_name 'outside-link'" >"$STATE_DIR/project-symlink-reject.out" 2>&1; then
	printf 'assertion failed: symlinked project path should have been rejected\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-symlink-reject.out" "project 'outside-link' was not found under $DEVELOPMENT_ROOT" 'symlinked project path is rejected'
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; resolve_selected_project_name 'repo:old'" >"$STATE_DIR/project-colon-reject.out" 2>&1; then
	printf 'assertion failed: colon-delimited project path should have been rejected\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-colon-reject.out" "project name must not contain ':'" 'project selection rejects names that would break Podman volume syntax'
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; project_mount_spec 'outside-link'" >"$STATE_DIR/project-mount-symlink-reject.out" 2>&1; then
	printf 'assertion failed: project mount spec should reject symlinked project paths\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-mount-symlink-reject.out" "project 'outside-link' was not found under $DEVELOPMENT_ROOT" 'project mount creation rejects symlinked project paths'
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$TMPDIR/missing-development-root' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; container_project_mount_matches_workspace_config opencode-project-runtime-create-test beta" >"$STATE_DIR/project-missing-root-reject.out" 2>&1; then
	printf 'assertion failed: missing development root should have rejected project mount validation\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-missing-root-reject.out" "project 'beta' was not found under $TMPDIR/missing-development-root" 'project mount validation fails clearly when the development root is missing'
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$TMPDIR/missing-development-root' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; create_or_replace_container missing-root-create-test opencode-local:test-1.4.3-main-20260410-163440-ab12cd3 projectmount test 1.4.3 main 20260410-163440-ab12cd3 beta" >"$STATE_DIR/project-missing-root-create.out" 2>&1; then
	printf 'assertion failed: missing development root should have rejected container creation\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-missing-root-create.out" "project 'beta' was not found under $TMPDIR/missing-development-root" 'container creation fails clearly when the development root is missing'
assert_eq "$DEVELOPMENT_ROOT/beta" "$(project_root_dir beta)" 'project root resolves within the configured development root'
assert_eq '/workspace/opencode-project' "$(container_project_dir)" 'container project dir uses the fixed wrapper-owned mount point'
assert_eq "$DEVELOPMENT_ROOT/beta:/workspace/opencode-project" "$(ID_MOCK_UID=1001 ID_MOCK_GID=1001 project_mount_spec beta)" 'project mount spec keeps the writable default mapping for non-root hosts'
assert_eq "$DEVELOPMENT_ROOT/beta:/workspace/opencode-project:U" "$(ID_MOCK_UID=0 ID_MOCK_GID=0 project_mount_spec beta)" 'project mount spec switches to ownership-shifted mapping for root-host fallback'
assert_eq 'opencode-projectmount-test-1.4.3-main-global' "$(container_name projectmount test 1.4.3 main)" 'container identity defaults to a global project scope when no project is selected'
assert_eq 'opencode-projectmount-test-1.4.3-main-beta' "$(container_name projectmount test 1.4.3 main beta)" 'container identity includes the selected project'
create_or_replace_container opencode-project-runtime-create-test opencode-local:test-1.4.3-main-20260410-163440-ab12cd3 projectmount test 1.4.3 main 20260410-163440-ab12cd3 beta
assert_contains "$STATE_DIR/podman.log" 'OPENCODE_CONTAINER_PROJECT_DIR=/workspace/opencode-project' 'container creation exports the fixed project mount path'
assert_contains "$STATE_DIR/env_home_opencode-project-runtime-create-test" "$OPENCODE_EXPECTED_RUNTIME_HOME" 'container creation exports HOME using the canonical runtime home'
assert_contains "$STATE_DIR/env_runtime_home_opencode-project-runtime-create-test" "$OPENCODE_EXPECTED_RUNTIME_HOME" 'container creation exports OPENCODE_CONTAINER_RUNTIME_HOME using the canonical runtime home'
assert_eq "$DEVELOPMENT_ROOT/beta" "$(cat "$STATE_DIR/mount_project_opencode-project-runtime-create-test")" 'container creation mounts the selected direct-child project'
if ! container_matches_workspace_runtime_config opencode-project-runtime-create-test projectmount 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' beta; then
	printf 'assertion failed: created container satisfies the selected project runtime contract\n' >&2
	exit 1
fi
mkdir -p "$DEVELOPMENT_ROOT/temporary-delete"
create_or_replace_container opencode-project-runtime-delete-test opencode-local:test-1.4.3-main-20260410-163440-ab12cd3 projectmount test 1.4.3 main 20260410-163440-ab12cd3 temporary-delete
rm -rf "$DEVELOPMENT_ROOT/temporary-delete"
if bash -lc "cd '$ROOT'; export PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_HOST_SERVER_PORT='$OPENCODE_HOST_SERVER_PORT' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK'; source '$ROOT/lib/shell/common.sh'; container_matches_workspace_runtime_config opencode-project-runtime-delete-test projectmount 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' temporary-delete" >"$STATE_DIR/project-deleted-reject.out" 2>&1; then
	printf 'assertion failed: deleted selected project should have rejected runtime validation\n' >&2
	exit 1
fi
assert_contains "$STATE_DIR/project-deleted-reject.out" "project 'temporary-delete' was not found under $DEVELOPMENT_ROOT" 'runtime validation fails clearly when the selected project has been deleted'
assert_eq 'opencode-projectmount-test-1.4.3-main-beta' "$(start_or_reuse_target projectmount image 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 main 20260410-163440-ab12cd3 beta)" 'start-or-reuse propagates the selected project through image-backed target creation'
assert_eq "$DEVELOPMENT_ROOT/beta" "$(cat "$STATE_DIR/mount_project_opencode-projectmount-test-1.4.3-main-beta")" 'start-or-reuse mounts the selected project for image-backed targets'
create_or_replace_container opencode-projectmount-test-1.4.3-main-alpha opencode-local:test-1.4.3-main-20260410-163440-ab12cd3 projectmount test 1.4.3 main 20260410-163440-ab12cd3 alpha
create_or_replace_container opencode-projectmount-test-1.4.3-main-beta opencode-local:test-1.4.3-main-20260410-163440-ab12cd3 projectmount test 1.4.3 main 20260410-163440-ab12cd3 beta
assert_eq "$DEVELOPMENT_ROOT/alpha" "$(cat "$STATE_DIR/mount_project_opencode-projectmount-test-1.4.3-main-alpha")" 'alpha project container keeps its own selected project mount'
assert_eq "$DEVELOPMENT_ROOT/beta" "$(cat "$STATE_DIR/mount_project_opencode-projectmount-test-1.4.3-main-beta")" 'beta project container keeps its own selected project mount'
assert_eq "$TMPDIR/workspaces/projectmount/opencode-home" "$(cat "$STATE_DIR/mount_home_opencode-projectmount-test-1.4.3-main-alpha")" 'alpha project container still uses the shared workspace home'
assert_eq "$TMPDIR/workspaces/projectmount/opencode-home" "$(cat "$STATE_DIR/mount_home_opencode-projectmount-test-1.4.3-main-beta")" 'beta project container still uses the shared workspace home'
ROOT_LAYOUT_WORKSPACE='rootlayout'
mkdir -p "$TMPDIR/workspaces/$ROOT_LAYOUT_WORKSPACE"
ID_MOCK_UID=0 ID_MOCK_GID=0 ensure_workspace_layout "$ROOT_LAYOUT_WORKSPACE"
assert_eq '1000:1000 775' "$(stat -c '%u:%g %a' "$TMPDIR/workspaces/$ROOT_LAYOUT_WORKSPACE/opencode-home")" 'root-host layout makes the workspace home writable for the non-root fallback user'
assert_eq '1000:1000 775' "$(stat -c '%u:%g %a' "$TMPDIR/workspaces/$ROOT_LAYOUT_WORKSPACE/opencode-workspace")" 'root-host layout makes the workspace workspace dir writable for the non-root fallback user'
assert_eq '1000:1000 775' "$(stat -c '%u:%g %a' "$TMPDIR/workspaces/$ROOT_LAYOUT_WORKSPACE/opencode-workspace/.config/opencode")" 'root-host layout makes the wrapper-owned config dir writable for the non-root fallback user'
assert_eq '0:0' "$(stat -c '%u:%g' "$DEVELOPMENT_ROOT")" 'root-host layout does not chown the development root'
: >"$STATE_DIR/podman.log"
ID_MOCK_UID=0 ID_MOCK_GID=0 create_or_replace_container opencode-project-runtime-root-host-test opencode-local:test-1.4.3-main-20260410-163440-ab12cd3 projectmount test 1.4.3 main 20260410-163440-ab12cd3 beta
assert_contains "$STATE_DIR/podman.log" "$DEVELOPMENT_ROOT:/workspace/opencode-development:ro" 'root-host container creation keeps the development mount read-only for the non-root runtime user'
assert_contains "$STATE_DIR/podman.log" "$DEVELOPMENT_ROOT/beta:/workspace/opencode-project:U" 'root-host container creation gives the selected project mount a writable ownership-shifted mapping'
rm -rf "$TMPDIR/workspaces/$ROOT_LAYOUT_WORKSPACE"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-project-mount-test-1.4.3-main' projectmount test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\n' "$TMPDIR/workspaces/projectmount/opencode-home" >"$STATE_DIR/mount_home_opencode-project-mount-test-1.4.3-main"
printf '%s\n' "$TMPDIR/workspaces/projectmount/opencode-workspace" >"$STATE_DIR/mount_workspace_opencode-project-mount-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT" >"$STATE_DIR/mount_development_opencode-project-mount-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-project-mount-test-1.4.3-main"
mkdir -p "$TMPDIR/workspaces/projectmount/opencode-home" "$TMPDIR/workspaces/projectmount/opencode-workspace"
if ! container_project_mount_matches_workspace_config opencode-project-mount-test-1.4.3-main beta; then
	printf 'assertion failed: project mount compatibility matches the selected project\n' >&2
	exit 1
fi
if ! container_mounts_match_workspace_config opencode-project-mount-test-1.4.3-main projectmount 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' beta; then
	printf 'assertion failed: full runtime mount compatibility includes the selected project mount\n' >&2
	exit 1
fi
if ! container_matches_workspace_runtime_config opencode-project-mount-test-1.4.3-main projectmount 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' beta; then
	printf 'assertion failed: runtime compatibility threads the selected project mount through the live helper\n' >&2
	exit 1
fi
printf '%s\n' "$DEVELOPMENT_ROOT/alpha" >"$STATE_DIR/mount_project_opencode-project-mount-test-1.4.3-main"
if container_mounts_match_workspace_config opencode-project-mount-test-1.4.3-main projectmount 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' beta; then
	printf 'assertion failed: full runtime mount compatibility rejects stale project mounts\n' >&2
	exit 1
fi
if container_matches_workspace_runtime_config opencode-project-mount-test-1.4.3-main projectmount 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' beta; then
	printf 'assertion failed: live runtime compatibility rejects stale project mounts\n' >&2
	exit 1
fi
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

KEEP_ROOT="$TMPDIR/build-keep-root"
prepare_build_test_root "$KEEP_ROOT"
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'ARG OPENCODE_HOST_UID' 'wrapper image declares the host uid build argument'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'ARG OPENCODE_HOST_GID' 'wrapper image declares the host gid build argument'
assert_not_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'ARG OPENCODE_CONTAINER_RUNTIME_HOME' 'wrapper image no longer treats the runtime home as a configurable build argument'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'useradd -o -m -u "$OPENCODE_HOST_UID" -g "$OPENCODE_HOST_GID" -d "/home/opencode" -s /bin/bash opencode' 'wrapper image creates the opencode user with the concrete runtime home'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'groupadd -o -g "$OPENCODE_HOST_GID" opencode' 'wrapper image creates the opencode group with the host gid'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'useradd -o -m -u "$OPENCODE_HOST_UID" -g "$OPENCODE_HOST_GID" -d "/home/opencode" -s /bin/bash opencode' 'wrapper image creates the opencode user with the host uid and gid'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'USER opencode' 'wrapper image sets the opencode runtime user in the container config'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.wrapper" 'ENV HOME=/home/opencode' 'wrapper image exports the concrete opencode home'
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$KEEP_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build.out" 2>&1
assert_contains "$STATE_DIR/build.out" '1. keep the current pin and continue' 'build offers a keep choice when the Ubuntu pin is behind'
assert_contains "$STATE_DIR/build.out" '2. update the config pin and continue' 'build offers an update choice when the Ubuntu pin is behind'
assert_contains "$STATE_DIR/build.out" '3. cancel' 'build offers a cancel choice when the Ubuntu pin is behind'
assert_contains "$STATE_DIR/build.out" 'Build source: official release v1.4.3' 'build uses the official stable release artefact for exact releases'
assert_contains "$STATE_DIR/build.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'build creates immutable image ref'
assert_contains "$STATE_DIR/podman.log" 'UBUNTU_VERSION=24.04' 'release build keeps using the pinned Ubuntu LTS version when keep is selected'
assert_contains "$STATE_DIR/podman.log" "OPENCODE_HOST_UID=$OPENCODE_EXPECTED_HOST_UID" 'release build passes the host uid into the wrapper image build'
assert_contains "$STATE_DIR/podman.log" "OPENCODE_HOST_GID=$OPENCODE_EXPECTED_HOST_GID" 'release build passes the host gid into the wrapper image build'
assert_contains "$STATE_DIR/podman.log" 'opencode.wrapper.ubuntu_version=24.04' 'release build labels the image with the pinned Ubuntu base version'
assert_not_contains "$STATE_DIR/podman.log" 'OPENCODE_CONTAINER_RUNTIME_HOME=' 'release build no longer passes a configurable runtime home into the image build'
assert_contains "$KEEP_ROOT/config/shared/opencode.conf" 'OPENCODE_UBUNTU_LTS_VERSION="24.04"' 'keep leaves the copied Ubuntu pin unchanged'

ROOT_HOST_IDS_ROOT="$TMPDIR/build-root-host-ids-root"
prepare_build_test_root "$ROOT_HOST_IDS_ROOT"
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE='20260410-163442-roothost' OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" ID_MOCK_UID=0 ID_MOCK_GID=0 "$ROOT_HOST_IDS_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build-root-host-ids.out" 2>&1
assert_contains "$STATE_DIR/build-root-host-ids.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163442-roothost' 'root-host build still completes with a non-root runtime identity'
assert_contains "$STATE_DIR/podman.log" 'OPENCODE_HOST_UID=1000' 'root-host build remaps uid 0 to a non-root runtime uid'
assert_contains "$STATE_DIR/podman.log" 'OPENCODE_HOST_GID=1000' 'root-host build remaps gid 0 to a non-root runtime gid'
assert_not_contains "$STATE_DIR/podman.log" 'OPENCODE_HOST_UID=0' 'root-host build does not pass uid 0 into the image build'
assert_not_contains "$STATE_DIR/podman.log" 'OPENCODE_HOST_GID=0' 'root-host build does not pass gid 0 into the image build'

assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'ARG OPENCODE_HOST_UID' 'source-base image declares the host uid build argument'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'ARG OPENCODE_HOST_GID' 'source-base image declares the host gid build argument'
assert_not_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'ARG OPENCODE_CONTAINER_RUNTIME_HOME' 'source-base image no longer treats the runtime home as a configurable build argument'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'useradd -o -m -u "$OPENCODE_HOST_UID" -g "$OPENCODE_HOST_GID" -d "/home/opencode" -s /bin/bash opencode' 'source-base image creates the opencode user with the concrete runtime home'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'groupadd -o -g "$OPENCODE_HOST_GID" opencode' 'source-base image creates the opencode group with the host gid'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'useradd -o -m -u "$OPENCODE_HOST_UID" -g "$OPENCODE_HOST_GID" -d "/home/opencode" -s /bin/bash opencode' 'source-base image creates the opencode user with the host uid, gid, and runtime home'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'USER opencode' 'source-base image sets the runtime user to opencode'
assert_contains "$KEEP_ROOT/config/containers/Containerfile.source-base.template" 'ENV HOME=/home/opencode' 'source-base image exports the concrete opencode home'

UPDATE_ROOT="$TMPDIR/build-update-root"
prepare_build_test_root "$UPDATE_ROOT"
UPDATE_MODE_BEFORE="$(stat -c '%a' "$UPDATE_ROOT/config/shared/opencode.conf")"
printf '2\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE='20260410-163441-updatelts' OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$UPDATE_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build-update.out" 2>&1
assert_contains "$STATE_DIR/build-update.out" 'Build source: official release v1.4.3' 'build continues after updating the Ubuntu pin'
assert_contains "$STATE_DIR/podman.log" 'UBUNTU_VERSION=26.04' 'release build uses the updated Ubuntu LTS version after the pin is changed'
assert_contains "$UPDATE_ROOT/config/shared/opencode.conf" 'OPENCODE_UBUNTU_LTS_VERSION="26.04"' 'update rewrites the copied Ubuntu pin in config/shared/opencode.conf'
assert_eq "$UPDATE_MODE_BEFORE" "$(stat -c '%a' "$UPDATE_ROOT/config/shared/opencode.conf")" 'update preserves the config file mode when rewriting the Ubuntu pin'

UPDATE_EXISTING_ROOT="$TMPDIR/build-update-existing-root"
prepare_build_test_root "$UPDATE_EXISTING_ROOT"
printf '2\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$UPDATE_EXISTING_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build-update-existing.out" 2>&1
assert_not_contains "$STATE_DIR/build-update-existing.out" 'Image already exists:' 'updating the Ubuntu pin rebuilds even when the previous image tag already exists'
assert_contains "$STATE_DIR/podman.log" 'UBUNTU_VERSION=26.04' 'pin updates rebuild the existing tag with the new Ubuntu LTS version'
assert_contains "$UPDATE_EXISTING_ROOT/config/shared/opencode.conf" 'OPENCODE_UBUNTU_LTS_VERSION="26.04"' 'pin update with an existing image still rewrites the copied Ubuntu pin'

STALE_UBUNTU_PIN_ROOT="$TMPDIR/build-stale-ubuntu-pin-root"
prepare_build_test_root "$STALE_UBUNTU_PIN_ROOT"
perl -0pi -e 's/OPENCODE_UBUNTU_LTS_VERSION="24\.04"/OPENCODE_UBUNTU_LTS_VERSION="26.04"/' "$STALE_UBUNTU_PIN_ROOT/config/shared/opencode.conf"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 opencode "$OPENCODE_EXPECTED_RUNTIME_HOME" "$OPENCODE_EXPECTED_HOST_UID" "$OPENCODE_EXPECTED_HOST_GID" /workspace/opencode-workspace 24.04 >"$STATE_DIR/images.tsv"
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$STALE_UBUNTU_PIN_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build-stale-ubuntu-pin.out" 2>&1
assert_not_contains "$STATE_DIR/build-stale-ubuntu-pin.out" 'Image already exists:' 'cached images built on an older Ubuntu pin are rebuilt when the configured base version changed'
assert_contains "$STATE_DIR/build-stale-ubuntu-pin.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'stale Ubuntu-pin image is replaced by a rebuilt image'
assert_contains "$STATE_DIR/podman.log" 'UBUNTU_VERSION=26.04' 'rebuild after an external Ubuntu pin change uses the configured newer Ubuntu base'

STALE_RUNTIME_IDS_ROOT="$TMPDIR/build-stale-runtime-ids-root"
prepare_build_test_root "$STALE_RUNTIME_IDS_ROOT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 opencode "$OPENCODE_EXPECTED_RUNTIME_HOME" 99998 99997 /workspace/opencode-workspace 24.04 >"$STATE_DIR/images.tsv"
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$STALE_RUNTIME_IDS_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build-stale-runtime-ids.out" 2>&1
assert_not_contains "$STATE_DIR/build-stale-runtime-ids.out" 'Image already exists:' 'stale images with mismatched runtime uid and gid are rebuilt instead of being reused'
assert_contains "$STATE_DIR/build-stale-runtime-ids.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'stale runtime-id image is replaced by a rebuilt image'
assert_contains "$STATE_DIR/podman.log" "OPENCODE_HOST_UID=$OPENCODE_EXPECTED_HOST_UID" 'rebuild after stale runtime ids uses the current host uid'
assert_contains "$STATE_DIR/podman.log" "OPENCODE_HOST_GID=$OPENCODE_EXPECTED_HOST_GID" 'rebuild after stale runtime ids uses the current host gid'

STALE_WORKDIR_ROOT="$TMPDIR/build-stale-workdir-root"
prepare_build_test_root "$STALE_WORKDIR_ROOT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 opencode "$OPENCODE_EXPECTED_RUNTIME_HOME" "$OPENCODE_EXPECTED_HOST_UID" "$OPENCODE_EXPECTED_HOST_GID" /workspace/legacy-workspace >"$STATE_DIR/images.tsv"
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$STALE_WORKDIR_ROOT/scripts/shared/opencode-build" test 1.4.3 >"$STATE_DIR/build-stale-workdir.out" 2>&1
assert_not_contains "$STATE_DIR/build-stale-workdir.out" 'Image already exists:' 'images with a stale workspace workdir are rebuilt instead of being reused'
assert_contains "$STATE_DIR/build-stale-workdir.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'stale workdir image is replaced by a rebuilt image'

STALE_SOURCE_RUNTIME_ROOT="$TMPDIR/build-stale-source-runtime-root"
prepare_build_test_root "$STALE_SOURCE_RUNTIME_ROOT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-main-main-20260410-163440-ab12cd3' test main main main 20260410-163440-ab12cd3 root /root "$OPENCODE_EXPECTED_HOST_UID" "$OPENCODE_EXPECTED_HOST_GID" /workspace/opencode-workspace >"$STATE_DIR/images.tsv"
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$STALE_SOURCE_RUNTIME_ROOT/scripts/shared/opencode-build" test main >"$STATE_DIR/build-stale-source-runtime.out" 2>&1
assert_not_contains "$STATE_DIR/build-stale-source-runtime.out" 'Image already exists:' 'source images with stale runtime user or home are rebuilt instead of being reused'
assert_contains "$STATE_DIR/build-stale-source-runtime.out" 'Build source: upstream source ref main' 'source-path rebuild still uses the source build flow'
assert_contains "$STATE_DIR/build-stale-source-runtime.out" 'Built image: opencode-local:test-main-main-20260410-163440-ab12cd3' 'stale source runtime image is replaced by a rebuilt image'
assert_contains "$STATE_DIR/podman.log" "OPENCODE_HOST_UID=$OPENCODE_EXPECTED_HOST_UID" 'source-path rebuild passes the current host uid into the image build'
assert_contains "$STATE_DIR/podman.log" "OPENCODE_HOST_GID=$OPENCODE_EXPECTED_HOST_GID" 'source-path rebuild passes the current host gid into the image build'
assert_not_contains "$STATE_DIR/podman.log" 'OPENCODE_CONTAINER_RUNTIME_HOME=' 'source-path rebuild no longer passes a configurable runtime home into the image build'

STALE_SOURCE_UPSTREAM_REF_ROOT="$TMPDIR/build-stale-source-upstream-ref-root"
prepare_build_test_root "$STALE_SOURCE_UPSTREAM_REF_ROOT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-main-main-20260410-163440-ab12cd3' test main stale-source-ref main 20260410-163440-ab12cd3 opencode "$OPENCODE_EXPECTED_RUNTIME_HOME" "$OPENCODE_EXPECTED_HOST_UID" "$OPENCODE_EXPECTED_HOST_GID" /workspace/opencode-workspace >"$STATE_DIR/images.tsv"
: >"$STATE_DIR/podman.log"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" "$STALE_SOURCE_UPSTREAM_REF_ROOT/scripts/shared/opencode-build" test main >"$STATE_DIR/build-stale-source-upstream-ref.out" 2>&1
assert_not_contains "$STATE_DIR/build-stale-source-upstream-ref.out" 'Image already exists:' 'source images with a stale upstream ref are rebuilt instead of being reused'
assert_contains "$STATE_DIR/build-stale-source-upstream-ref.out" 'Build source: upstream source ref main' 'stale source upstream-ref rebuild still uses the source build flow'
assert_contains "$STATE_DIR/build-stale-source-upstream-ref.out" 'Built image: opencode-local:test-main-main-20260410-163440-ab12cd3' 'stale source upstream-ref image is replaced by a rebuilt image'

LATEST_RACE_ROOT="$TMPDIR/build-latest-race-root"
prepare_build_test_root "$LATEST_RACE_ROOT"
: >"$STATE_DIR/podman.log"
rm -f "$STATE_DIR/mock-latest-release-sequence"
printf '1\n' | env -u OPENCODE_SELECT_INDEX PATH="$PATH" STATE_DIR="$STATE_DIR" OPENCODE_BASE_ROOT="$OPENCODE_BASE_ROOT" OPENCODE_DEVELOPMENT_ROOT="$OPENCODE_DEVELOPMENT_ROOT" OPENCODE_IMAGE_NAME="$OPENCODE_IMAGE_NAME" OPENCODE_COMMITSTAMP_OVERRIDE="$OPENCODE_COMMITSTAMP_OVERRIDE" OPENCODE_SOURCE_OVERRIDE_DIR="$OPENCODE_SOURCE_OVERRIDE_DIR" OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$OPENCODE_SKIP_BUILD_CONTEXT_CHECK" MOCK_LATEST_RELEASE_SEQUENCE='v1.4.3,v1.4.4' "$LATEST_RACE_ROOT/scripts/shared/opencode-build" test latest >"$STATE_DIR/build-latest-race.out" 2>&1
assert_contains "$STATE_DIR/build-latest-race.out" 'Build source: official release v1.4.3' 'latest-release builds derive the upstream ref from the already resolved release value'
assert_contains "$STATE_DIR/build-latest-race.out" 'Built image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'latest-release builds keep the resolved image identity when the latest tag changes mid-build'
assert_not_contains "$STATE_DIR/podman.log" 'opencode-linux-x64/1.4.4' 'latest-release builds do not re-resolve the selector after choosing the release version'

CANCEL_ROOT="$TMPDIR/build-cancel-root"
prepare_build_test_root "$CANCEL_ROOT"
: >"$STATE_DIR/podman.log"
printf '%s	%s	%s	%s	%s	%s	%s	%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 false 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\n' "$TMPDIR/workspaces/general/opencode-home" >"$STATE_DIR/mount_home_opencode-general-test-1.4.3-main"
printf '%s\n' "$TMPDIR/workspaces/general/opencode-workspace" >"$STATE_DIR/mount_workspace_opencode-general-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT" >"$STATE_DIR/mount_development_opencode-general-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-general-test-1.4.3-main"
"$ROOT/scripts/shared/opencode-shell" general beta -- env >"$STATE_DIR/shell-stopped.out" 2>&1 && {
	printf 'assertion failed: shell should refuse stopped containers instead of starting them\n' >&2
	exit 1
}
assert_contains "$STATE_DIR/shell-stopped.out" 'container is not running:' 'shell rejects stopped containers instead of starting them'
assert_not_contains "$STATE_DIR/podman.log" 'start opencode-general-test-1.4.3-main-beta' 'shell does not start stopped containers implicitly'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-test-1.4.3-main' second test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\n' "$TMPDIR/workspaces/second/opencode-home" >"$STATE_DIR/mount_home_opencode-second-test-1.4.3-main"
printf '%s\n' "$TMPDIR/workspaces/second/opencode-workspace" >"$STATE_DIR/mount_workspace_opencode-second-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT" >"$STATE_DIR/mount_development_opencode-second-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-second-test-1.4.3-main"
: >"$STATE_DIR/podman.log"
"$ROOT/scripts/shared/opencode-shell" second beta >"$STATE_DIR/shell-explicit-project-no-payload.out"
assert_contains "$STATE_DIR/shell-explicit-project-no-payload.out" 'mock exec' 'shell accepts an explicit project even when no command args remain'
assert_contains "$STATE_DIR/podman.log" 'exec /bin/sh' 'shell opens an interactive shell when explicit project selection leaves no command args'
"$ROOT/scripts/shared/opencode-bootstrap" second beta -- --version >"$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/podman.log" '--workdir /workspace/opencode-project' 'bootstrap reuses the fixed project workdir for the selected project directory'
assert_contains "$STATE_DIR/podman.log" 'opencode-second-test-1.4.3-main-beta /bin/sh -lc' 'bootstrap reuses the resolved target container'
: >"$STATE_DIR/podman.log"
"$ROOT/scripts/shared/opencode-bootstrap" second beta >"$STATE_DIR/bootstrap-no-payload.out"
assert_contains "$STATE_DIR/bootstrap-no-payload.out" 'mock exec' 'bootstrap accepts an explicit project even when no OpenCode args remain'
assert_contains "$STATE_DIR/podman.log" 'exec opencode "$@"' 'bootstrap still execs OpenCode when explicit project selection leaves no trailing payload args'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
rm -f "$STATE_DIR/hide_project_mount_opencode-order-test-1.4.3-main-beta"
touch "$STATE_DIR/hide_project_mount_opencode-order-test-1.4.3-main-beta"
: >"$STATE_DIR/podman.log"
assert_command_fails "$ROOT/scripts/shared/opencode-start order test 1.4.3 beta -- --version" "$STATE_DIR/start-hidden-project-mount.out"
assert_contains "$STATE_DIR/start-hidden-project-mount.out" "selected project 'beta' does not match the existing container runtime" 'start refuses to launch into the fixed project path before the selected project mount is visible'
assert_not_contains "$STATE_DIR/podman.log" 'opencode-order-test-1.4.3-main-beta /bin/sh -lc' 'start does not launch before the selected project mount exists'
rm -f "$STATE_DIR/hide_project_mount_opencode-order-test-1.4.3-main-beta"

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-third-test-1.4.3-main' third test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\n' "$TMPDIR/workspaces/third/opencode-home" >"$STATE_DIR/mount_home_opencode-third-test-1.4.3-main"
printf '%s\n' "$TMPDIR/workspaces/third/opencode-workspace" >"$STATE_DIR/mount_workspace_opencode-third-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT" >"$STATE_DIR/mount_development_opencode-third-test-1.4.3-main"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-third-test-1.4.3-main"
touch "$STATE_DIR/hide_project_mount_opencode-third-test-1.4.3-main"
: >"$STATE_DIR/podman.log"
assert_command_fails "$ROOT/scripts/shared/opencode-open third beta -- --version" "$STATE_DIR/open-hidden-project-mount.out"
assert_contains "$STATE_DIR/open-hidden-project-mount.out" "selected project 'beta' does not match the existing container runtime" 'open rejects the fixed project path until the selected project mount is visible'
assert_not_contains "$STATE_DIR/podman.log" 'opencode-third-test-1.4.3-main /bin/sh -lc' 'open does not launch before the selected project mount exists'
: >"$STATE_DIR/podman.log"
assert_command_fails "$ROOT/scripts/shared/opencode-shell third beta -- env" "$STATE_DIR/shell-hidden-project-mount.out"
assert_contains "$STATE_DIR/shell-hidden-project-mount.out" "selected project 'beta' does not match the existing container runtime" 'shell rejects the fixed project path until the selected project mount is visible'
assert_not_contains "$STATE_DIR/podman.log" 'opencode-third-test-1.4.3-main /bin/sh -lc' 'shell does not launch before the selected project mount exists'
rm -f "$STATE_DIR/hide_project_mount_opencode-third-test-1.4.3-main"

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260409-120000-deadbee' test 1.4.3 v1.4.3 main 20260409-120000-deadbee >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-picker-test-1.4.3-main-alpha' picker test 1.4.3 main 20260409-120000-deadbee true 'opencode-local:test-1.4.3-main-20260409-120000-deadbee' >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-picker-test-1.4.3-main-beta' picker test 1.4.3 main 20260409-120000-deadbee true 'opencode-local:test-1.4.3-main-20260409-120000-deadbee' >>"$STATE_DIR/containers.tsv"
printf '%s\n' "$DEVELOPMENT_ROOT/alpha" >"$STATE_DIR/mount_project_opencode-picker-test-1.4.3-main-alpha"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-picker-test-1.4.3-main-beta"
assert_eq $'container\topencode-picker-test-1.4.3-main-beta\ttest\t1.4.3\tmain\t20260409-120000-deadbee\trunning\topencode-local:test-1.4.3-main-20260409-120000-deadbee\tbeta' "$(OPENCODE_SELECT_INDEX=2 resolve_target_details_for_workspace picker)" 'target resolution preserves the selected project in the returned tuple for existing containers'
assert_eq 'beta' "$(OPENCODE_SELECT_INDEX=2 resolve_target_details_for_workspace picker >/dev/null; resolve_selected_project_name '')" 'target resolution carries the selected beta project into the next implicit project lookup'
printf '3\n2\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-start" picker >"$STATE_DIR/start-picker.out" 2>&1
assert_contains "$STATE_DIR/start-picker.out" "Select a target for workspace 'picker'" 'start still shows the target picker for implicit target resolution'
assert_contains "$STATE_DIR/start-picker.out" 'project' 'start target picker shows the project metadata column'
assert_contains "$STATE_DIR/start-picker.out" 'lane' 'start target picker still shows the lane metadata column'
assert_contains "$STATE_DIR/start-picker.out" 'alpha' 'start target picker distinguishes the alpha container row'
assert_contains "$STATE_DIR/start-picker.out" 'beta' 'start target picker distinguishes the beta container row'
assert_contains "$STATE_DIR/start-picker.out" 'Select a project from' 'start requires project selection after resolving the workspace target'
assert_line_order "$STATE_DIR/start-picker.out" "Select a target for workspace 'picker'" 'Select a project from' 'start resolves the target before prompting for the project'
assert_contains "$STATE_DIR/start-picker.out" '  Name: opencode-picker-test-1.4.3-main-beta' 'start can select an image row and create the matching project-specific container'
assert_eq "$DEVELOPMENT_ROOT/beta" "$(cat "$STATE_DIR/mount_project_opencode-picker-test-1.4.3-main-beta")" 'target-selected start mounts the chosen project into the recreated container'
: >"$STATE_DIR/podman.log"
printf '2\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-start" picker -- --version >"$STATE_DIR/start-picker-existing-project.out" 2>&1
assert_contains "$STATE_DIR/start-picker-existing-project.out" "Select a target for workspace 'picker'" 'start still prompts for target selection when choosing an existing project-specific container'
assert_not_contains "$STATE_DIR/start-picker-existing-project.out" 'Select a project from' 'start reuses the selected project from the chosen container row without prompting again'
assert_contains "$STATE_DIR/start-picker-existing-project.out" 'mock exec' 'start launches after preserving the selected project from the chosen container row'
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-test-1.4.3-main' second test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >>"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >>"$STATE_DIR/containers.tsv"

"$ROOT/scripts/shared/opencode-logs" second --tail 5 >"$STATE_DIR/logs.out"
assert_contains "$STATE_DIR/podman.log" 'logs --tail 5 opencode-second-test-1.4.3-main' 'logs forwards podman log arguments to the resolved workspace container'

: >"$STATE_DIR/podman.log"
printf '3\n1\n' >"$STATE_DIR/logs-picked.input"
env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-logs" -- --tail 6 <"$STATE_DIR/logs-picked.input" >"$STATE_DIR/logs-picked.out" 2>&1
assert_contains "$STATE_DIR/podman.log" 'logs --tail 6 opencode-second-test-1.4.3-main' 'logs can pick a workspace when forwarded podman arguments begin with a dash'

"$ROOT/scripts/shared/opencode-status" second >"$STATE_DIR/status.out"
assert_contains "$STATE_DIR/status.out" 'Container' 'status prints a container section'
assert_contains "$STATE_DIR/status.out" 'Build' 'status prints a build section'
assert_contains "$STATE_DIR/status.out" 'Ports' 'status prints a ports section'
assert_contains "$STATE_DIR/status.out" 'Mounts' 'status prints a mounts section'
assert_contains "$STATE_DIR/status.out" 'Config' 'status prints a config section'
assert_contains "$STATE_DIR/status.out" '  Lane: test' 'status reports lane'
assert_contains "$STATE_DIR/status.out" '  Upstream: 1.4.3' 'status reports upstream'
assert_contains "$STATE_DIR/status.out" '  Container Port: 4096/tcp' 'status reports the container port even when no host port is configured'
assert_contains "$STATE_DIR/status.out" '  Host Mapping: (not published)' 'status reports when the container port is not published'
assert_contains "$STATE_DIR/status.out" '  Configured Host Port: (unset)' 'status reports an unset configured host port explicitly'
assert_contains "$STATE_DIR/status.out" "  Development Root Mount: $DEVELOPMENT_ROOT -> /workspace/opencode-development" 'status reports the live development-root mount'
assert_contains "$STATE_DIR/status.out" "  Selected Project Mount: $DEVELOPMENT_ROOT/beta -> /workspace/opencode-project" 'status reports the live selected project mount when present'
assert_contains "$STATE_DIR/status.out" "  config.env: present ($TMPDIR/workspaces/second/opencode-workspace/.config/opencode/config.env)" 'status reports config.env presence explicitly'
assert_contains "$STATE_DIR/status.out" "  secrets.env: missing ($TMPDIR/workspaces/second/opencode-workspace/.config/opencode/secrets.env)" 'status reports missing secrets.env explicitly'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-production-1.4.3-main' second production 1.4.3 main 20260410-163440-ab12cd3 false 'opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-logs" second --tail 7 >"$STATE_DIR/logs-second-picker.out"
assert_contains "$STATE_DIR/podman.log" 'logs --tail 7 opencode-second-production-1.4.3-main' 'logs can select among multiple matching containers'
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-status" second >"$STATE_DIR/status-second-picker.out"
assert_contains "$STATE_DIR/status-second-picker.out" '  Lane: production' 'status can select among multiple matching containers without tripping nounset array handling'
printf '2\n2\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-shell" second -- env >"$STATE_DIR/shell-second-picker.out" 2>&1
assert_contains "$STATE_DIR/shell-second-picker.out" "Select a container for workspace 'second'" 'shell can still select among multiple matching containers'
assert_contains "$STATE_DIR/shell-second-picker.out" 'Select a project from' 'shell requires project selection after choosing a matching container'
assert_line_order "$STATE_DIR/shell-second-picker.out" "Select a container for workspace 'second'" 'Select a project from' 'shell resolves the matching container before project selection'
assert_contains "$STATE_DIR/podman.log" '--workdir /workspace/opencode-project' 'shell can select among multiple matching containers and exec in the selected project directory'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-test-1.4.3-main-alpha' second test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-second-test-1.4.3-main-beta' second test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >>"$STATE_DIR/containers.tsv"
printf '%s\n' "$DEVELOPMENT_ROOT/alpha" >"$STATE_DIR/mount_project_opencode-second-test-1.4.3-main-alpha"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-second-test-1.4.3-main-beta"
rm -f "$(selected_target_project_state_file)"
OPENCODE_SELECT_INDEX=2 resolve_row_from_picker "Select a container for workspace 'second'" $'opencode-second-test-1.4.3-main-alpha\tsecond\talpha\ttest\t1.4.3\tmain\t20260410-163440-ab12cd3\trunning\topencode-local:test-1.4.3-main-20260410-163440-ab12cd3\nopencode-second-test-1.4.3-main-beta\tsecond\tbeta\ttest\t1.4.3\tmain\t20260410-163440-ab12cd3\trunning\topencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >/dev/null
assert_eq 'beta' "$(sed -n '1p' "$(selected_target_project_state_file)")" 'row picker records the selected beta project for explicit container reuse'
rm -f "$(selected_target_project_state_file)"
assert_eq 'opencode-second-test-1.4.3-main-beta' "$(OPENCODE_SELECT_INDEX=2 resolve_existing_explicit_container second test 1.4.3)" 'explicit container resolution keeps the selected beta row'
OPENCODE_SELECT_INDEX=2 resolve_existing_explicit_container second test 1.4.3 >/dev/null
assert_eq 'beta' "$(sed -n '1p' "$(selected_target_project_state_file)")" 'explicit container resolution records the selected beta project for reuse'
rm -f "$(selected_target_project_state_file)"
assert_eq 'beta' "$(OPENCODE_SELECT_INDEX=2 resolve_existing_explicit_container second test 1.4.3 >/dev/null; resolve_selected_project_name '')" 'explicit container resolution carries the selected beta project into the next implicit project lookup'
: >"$STATE_DIR/podman.log"
printf '2\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-shell" second test 1.4.3 -- env >"$STATE_DIR/shell-second-explicit-picker.out" 2>&1
assert_contains "$STATE_DIR/shell-second-explicit-picker.out" "Select a container for workspace 'second'" 'shell explicit selection prompts when multiple matching containers exist'
assert_contains "$STATE_DIR/shell-second-explicit-picker.out" 'project' 'shell explicit picker shows the project metadata column'
assert_contains "$STATE_DIR/shell-second-explicit-picker.out" 'lane' 'shell explicit picker keeps the metadata headers visible'
assert_contains "$STATE_DIR/shell-second-explicit-picker.out" 'alpha' 'shell explicit picker distinguishes the alpha container row'
assert_contains "$STATE_DIR/shell-second-explicit-picker.out" 'beta' 'shell explicit picker distinguishes the beta container row'
assert_not_contains "$STATE_DIR/shell-second-explicit-picker.out" 'Select a project from' 'shell explicit picker reuses the chosen row project instead of prompting again'
assert_contains "$STATE_DIR/podman.log" 'exec --workdir /workspace/opencode-project opencode-second-test-1.4.3-main-beta /bin/sh -lc' 'shell explicit picker execs in the selected beta container'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-single-test-1.4.3-main-beta' single test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\n' "$DEVELOPMENT_ROOT/beta" >"$STATE_DIR/mount_project_opencode-single-test-1.4.3-main-beta"
rm -f "$(selected_target_project_state_file)"
assert_eq 'opencode-single-test-1.4.3-main-beta' "$(resolve_existing_explicit_container single test 1.4.3)" 'single-match explicit container resolution still resolves the beta container'
rm -f "$(selected_target_project_state_file)"
resolve_existing_explicit_container single test 1.4.3 >/dev/null
assert_eq 'beta' "$(sed -n '1p' "$(selected_target_project_state_file)")" 'single-match explicit container resolution records the selected beta project for reuse'
rm -f "$(selected_target_project_state_file)"
resolve_existing_explicit_container single test 1.4.3 >/dev/null
assert_eq 'beta' "$(resolve_selected_project_name '')" 'single-match explicit container resolution carries the selected beta project into the next implicit lookup'

remember_selected_target_project global
if [[ -f "$(selected_target_project_state_file)" ]]; then
	printf 'assertion failed: global scope should not be remembered as a selected project\n' >&2
	exit 1
fi
remember_selected_target_project -
if [[ -f "$(selected_target_project_state_file)" ]]; then
	printf 'assertion failed: placeholder scope should not be remembered as a selected project\n' >&2
	exit 1
fi

printf '%s	%s	%s	%s	%s	%s	%s	%s
printf '%s
printf '%s
printf '%s
printf '%s
printf '%s
: >"$STATE_DIR/server_active_opencode-general-test-1.4.3-main"
mkdir -p "$TMPDIR/workspaces/general/opencode-workspace/.config/opencode"
cat >"$TMPDIR/workspaces/general/opencode-workspace/.config/opencode/config.env" <<'EOF'
OPENCODE_HOST_SERVER_PORT=5098
EOF
"$ROOT/scripts/shared/opencode-status" general >"$STATE_DIR/status-general.out"
assert_contains "$STATE_DIR/status-general.out" '  Configured Host Port: 5098' 'status reports the configured host port when present'
assert_contains "$STATE_DIR/status-general.out" '  Host Mapping: (not published)' 'status reports when no live published mapping is present for the selected container'
assert_contains "$STATE_DIR/status-general.out" "  Selected Project Mount: $DEVELOPMENT_ROOT/beta -> /workspace/opencode-project" 'status reports the live selected project mount'
assert_contains "$STATE_DIR/status-general.out" "  config.env: present ($TMPDIR/workspaces/general/opencode-workspace/.config/opencode/config.env)" 'status reports config.env presence'
assert_contains "$STATE_DIR/status-general.out" "  secrets.env: missing ($TMPDIR/workspaces/general/opencode-workspace/.config/opencode/secrets.env)" 'status reports missing secrets.env without printing secret values'

: >"$STATE_DIR/podman.log"
rm -f "$STATE_DIR/server_active_opencode-general-test-1.4.3-main"
"$ROOT/scripts/shared/opencode-status" general >"$STATE_DIR/status-general-recovered.out"
assert_contains "$STATE_DIR/status-general-recovered.out" '  Host Mapping: (not published)' 'status remains diagnostic when no live published mapping is present'
assert_not_contains "$STATE_DIR/podman.log" 'exec opencode-general-test-1.4.3-main /bin/sh -lc' 'status does not trigger managed server repair during diagnostics'

"$ROOT/scripts/shared/opencode-stop" general >"$STATE_DIR/stop.out"
assert_contains "$STATE_DIR/stop.out" 'Stopped container: opencode-general-test-1.4.3-main' 'stop stops running container'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-feature-xyz-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 feature-xyz 20260410-163440-ab12cd3 >>"$STATE_DIR/images.tsv"
OPENCODE_WRAPPER_CONTEXT_OVERRIDE=feature-xyz "$ROOT/scripts/shared/opencode-start" branchy test 1.4.3 beta -- --version >"$STATE_DIR/start-with-args.out"
assert_contains "$STATE_DIR/podman.log" '--name opencode-branchy-test-1.4.3-feature-xyz-beta' 'start with args creates the selected wrapper-context container'
assert_contains "$STATE_DIR/podman.log" '--workdir /workspace/opencode-project' 'start with args uses the fixed project workdir'
assert_contains "$STATE_DIR/podman.log" 'opencode-branchy-test-1.4.3-feature-xyz-beta /bin/sh -lc' 'start with args forwards directly into the selected container'
podman rm -f opencode-branchy-test-1.4.3-feature-xyz-beta >/dev/null

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >>"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false 'opencode-local:test-1.4.3-main-20260408-090000-cafebabe' >>"$STATE_DIR/containers.tsv"
printf '4\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-remove" containers >"$STATE_DIR/remove-container-ui.out" 2>&1
assert_contains "$STATE_DIR/remove-container-ui.out" 'workspace  project  lane        upstream  wrapper  commit                   status' 'remove containers shows aligned headers with workspace and project identity'
assert_contains "$STATE_DIR/remove-container-ui.out" '4. general    global   test        1.4.3     main     20260410-163440-ab12cd3   running' 'remove containers keeps workspace and project identity in each row'
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.3-main' general test 1.4.3 main 20260410-163440-ab12cd3 true 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' >>"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false 'opencode-local:test-1.4.3-main-20260408-090000-cafebabe' >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=4 "$ROOT/scripts/shared/opencode-remove" containers >"$STATE_DIR/remove-container.out"
assert_contains "$STATE_DIR/remove-container.out" 'Removed container: opencode-general-test-1.4.3-main' 'remove container removes selected container'
assert_not_contains "$STATE_DIR/containers.tsv" $'opencode-general-test-1.4.3-main\t' 'remove container deletes the selected container record'
test ! -e "$STATE_DIR/mount_home_opencode-general-test-1.4.3-main"
test ! -e "$STATE_DIR/mount_workspace_opencode-general-test-1.4.3-main"

printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '3\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-remove" images >"$STATE_DIR/remove-image-ui.out" 2>&1
assert_contains "$STATE_DIR/remove-image-ui.out" 'workspace  project  lane  upstream  wrapper  commit                   status' 'remove images shows workspace and project headers'
assert_contains "$STATE_DIR/remove-image-ui.out" '3. -          -        test  1.4.3     main     20260410-163440-ab12cd3  image only' 'remove images keeps placeholder workspace and project rows aligned under the metadata columns'
printf '%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
OPENCODE_SELECT_INDEX=3 "$ROOT/scripts/shared/opencode-remove" images >"$STATE_DIR/remove-image.out"
assert_contains "$STATE_DIR/remove-image.out" 'Removed image: opencode-local:test-1.4.3-main-20260410-163440-ab12cd3' 'remove image removes selected image'
assert_not_contains "$STATE_DIR/images.tsv" $'opencode-local:test-1.4.3-main-20260410-163440-ab12cd3\t' 'remove image deletes the selected image record'

assert_rejects "env PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' '$ROOT/scripts/shared/opencode-start' missing test 9.9.9" 'no local image found for lane=test upstream=9.9.9 wrapper=main' "$STATE_DIR/start-missing-image.out"
assert_rejects "env PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' '$ROOT/scripts/shared/opencode-open' missing test 1.4.3" 'no matching container exists for workspace=missing lane=test upstream=1.4.3' "$STATE_DIR/open-missing-container.out"
assert_rejects "env PATH='$PATH' STATE_DIR='$STATE_DIR' OPENCODE_BASE_ROOT='$OPENCODE_BASE_ROOT' OPENCODE_DEVELOPMENT_ROOT='$OPENCODE_DEVELOPMENT_ROOT' OPENCODE_IMAGE_NAME='$OPENCODE_IMAGE_NAME' OPENCODE_COMMITSTAMP_OVERRIDE='$OPENCODE_COMMITSTAMP_OVERRIDE' OPENCODE_SOURCE_OVERRIDE_DIR='$OPENCODE_SOURCE_OVERRIDE_DIR' OPENCODE_SKIP_BUILD_CONTEXT_CHECK='$OPENCODE_SKIP_BUILD_CONTEXT_CHECK' '$ROOT/scripts/shared/opencode-shell' missing test 1.4.3" 'no matching container exists for workspace=missing lane=test upstream=1.4.3' "$STATE_DIR/shell-missing-container.out"

IMG_EZ_NEW='opencode-local:production-1.4.3-main-20260410-163440-ab12cd3'
IMG_EZ_OLD='opencode-local:production-1.4.2-main-20260409-120000-deadbee'
IMG_NA='opencode-local:test-1.4.3-main-20260408-090000-cafebabe'
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_OLD" production 1.4.2 v1.4.2 main 20260409-120000-deadbee >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" >>"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" images >"$STATE_DIR/remove-image-all-but-newest.out"
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Keeping image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'remove image all-but-newest keeps newest associated ezirius image'
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Keeping image: opencode-local:test-1.4.3-main-20260408-090000-cafebabe' 'remove image all-but-newest keeps newest associated nala image'
assert_contains "$STATE_DIR/remove-image-all-but-newest.out" 'Removed image: opencode-local:production-1.4.2-main-20260409-120000-deadbee' 'remove image all-but-newest removes older associated image'

IMG_TIE_ALPHA='opencode-local:test-1.4.3-main-20260410-163440-ab12cd3-alpha'
IMG_TIE_BETA='opencode-local:test-1.4.3-main-20260410-163440-ab12cd3-beta'
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_TIE_ALPHA" test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_TIE_BETA" test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-tied-test-1.4.3-main-beta' tied test 1.4.3 main 20260410-163440-ab12cd3 false "$IMG_TIE_BETA" >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-tied-test-1.4.3-main-alpha' tied test 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_TIE_ALPHA" >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" containers >"$STATE_DIR/remove-container-all-but-newest-tie.out"
assert_contains "$STATE_DIR/remove-container-all-but-newest-tie.out" 'Keeping container: opencode-tied-test-1.4.3-main-alpha' 'remove container all-but-newest keeps the lexical-first container when lane and commitstamp tie'
assert_contains "$STATE_DIR/remove-container-all-but-newest-tie.out" 'Removed container: opencode-tied-test-1.4.3-main-beta' 'remove container all-but-newest removes the lexical-later tie'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_TIE_ALPHA" test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_TIE_BETA" test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-tied-test-1.4.3-main-beta' tied test 1.4.3 main 20260410-163440-ab12cd3 false "$IMG_TIE_BETA" >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-tied-test-1.4.3-main-alpha' tied test 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_TIE_ALPHA" >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" images >"$STATE_DIR/remove-image-all-but-newest-tie.out"
assert_contains "$STATE_DIR/remove-image-all-but-newest-tie.out" "Keeping image: $IMG_TIE_ALPHA" 'remove image all-but-newest keeps the image for the lexical-first kept container when lane and commitstamp tie'
assert_contains "$STATE_DIR/remove-image-all-but-newest-tie.out" "Removed image: $IMG_TIE_BETA" 'remove image all-but-newest removes the image for the lexical-later tie'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_TIE_ALPHA" test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_TIE_BETA" test 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-tied-test-1.4.3-main-beta' tied test 1.4.3 main 20260410-163440-ab12cd3 false "$IMG_TIE_BETA" >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-tied-test-1.4.3-main-alpha' tied test 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_TIE_ALPHA" >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" >"$STATE_DIR/remove-mixed-all-but-newest-tie.out"
assert_contains "$STATE_DIR/remove-mixed-all-but-newest-tie.out" 'Keeping container: opencode-tied-test-1.4.3-main-alpha' 'mixed remove keeps the lexical-first container when lane and commitstamp tie'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest-tie.out" "Keeping image: $IMG_TIE_ALPHA" 'mixed remove keeps the image serving the lexical-first kept container when lane and commitstamp tie'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest-tie.out" "Removed image: $IMG_TIE_BETA" 'mixed remove removes the image for the lexical-later tie'

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.2-main' general test 1.4.2 main 20260409-120000-deadbee false "$IMG_EZ_OLD" >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" containers >"$STATE_DIR/remove-container-all-but-newest.out"
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Keeping container: opencode-general-production-1.4.3-main' 'remove container all-but-newest keeps newest container for general'
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Removed container: opencode-general-test-1.4.2-main' 'remove container all-but-newest removes older general container'
assert_contains "$STATE_DIR/remove-container-all-but-newest.out" 'Keeping container: opencode-nala-test-1.4.3-main' 'remove container all-but-newest keeps newest container for nala'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_OLD" production 1.4.2 v1.4.2 main 20260409-120000-deadbee >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-test-1.4.2-main' general test 1.4.2 main 20260409-120000-deadbee false "$IMG_EZ_OLD" >>"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >>"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=1 "$ROOT/scripts/shared/opencode-remove" >"$STATE_DIR/remove-mixed-all-but-newest.out"
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping container: opencode-general-production-1.4.3-main' 'mixed remove keeps newest general container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping container: opencode-nala-test-1.4.3-main' 'mixed remove keeps newest nala container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'mixed remove keeps image serving kept general container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Keeping image: opencode-local:test-1.4.3-main-20260408-090000-cafebabe' 'mixed remove keeps image serving kept nala container'
assert_contains "$STATE_DIR/remove-mixed-all-but-newest.out" 'Removed image: opencode-local:production-1.4.2-main-20260409-120000-deadbee' 'mixed remove removes image not serving kept containers'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_NA" test 1.4.3 v1.4.3 main 20260408-090000-cafebabe >>"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" >"$STATE_DIR/containers.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-nala-test-1.4.3-main' nala test 1.4.3 main 20260408-090000-cafebabe false "$IMG_NA" >>"$STATE_DIR/containers.tsv"
printf '4\n' | env -u OPENCODE_SELECT_INDEX "$ROOT/scripts/shared/opencode-remove" >"$STATE_DIR/remove-mixed-ui.out" 2>&1
assert_contains "$STATE_DIR/remove-mixed-ui.out" 'workspace  project  lane        upstream  wrapper  commit                    status' 'mixed remove shows aligned headers with workspace and project identity'
assert_contains "$STATE_DIR/remove-mixed-ui.out" '3. general    global   production  1.4.3     main     20260410-163440-ab12cd3' 'mixed remove shows workspace and project identity for container rows'
assert_contains "$STATE_DIR/remove-mixed-ui.out" '4. nala       global   test        1.4.3     main     20260408-090000-cafebabe' 'mixed remove keeps container rows unambiguous across workspaces'
assert_contains "$STATE_DIR/remove-mixed-ui.out" '6. -          -        test        1.4.3     main     20260408-090000-cafebabe  image only' 'mixed remove shows placeholder workspace and project identity for image rows'
OPENCODE_SELECT_INDEX=2 "$ROOT/scripts/shared/opencode-remove" >"$STATE_DIR/remove-mixed-all.out"
assert_contains "$STATE_DIR/remove-mixed-all.out" 'Removed container: opencode-general-production-1.4.3-main' 'mixed remove all removes containers first'
assert_contains "$STATE_DIR/remove-mixed-all.out" 'Removed container: opencode-nala-test-1.4.3-main' 'mixed remove all removes all containers'
assert_contains "$STATE_DIR/remove-mixed-all.out" 'Removed image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'mixed remove all removes images after containers'
assert_line_order "$STATE_DIR/remove-mixed-all.out" 'Removed container: opencode-general-production-1.4.3-main' 'Removed image: opencode-local:production-1.4.3-main-20260410-163440-ab12cd3' 'mixed remove all removes containers before images'

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$IMG_EZ_NEW" production 1.4.3 v1.4.3 main 20260410-163440-ab12cd3 >"$STATE_DIR/images.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'opencode-general-production-1.4.3-main' general production 1.4.3 main 20260410-163440-ab12cd3 true "$IMG_EZ_NEW" >"$STATE_DIR/containers.tsv"
OPENCODE_SELECT_INDEX=4 "$ROOT/scripts/shared/opencode-remove" >"$STATE_DIR/remove-mixed-image-row.out"
assert_contains "$STATE_DIR/remove-mixed-image-row.out" "Removed image: $IMG_EZ_NEW" 'mixed remove can remove an image row even when a container row references the same image'

echo "Runtime checks passed"
