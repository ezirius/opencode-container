#!/usr/bin/env bash

set -euo pipefail

# This test checks that the build script uses the reduced Hermes-style build contract.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

TMP_DIR="$(mktemp -d)"
CONFIG_PATH="$(cd "$(dirname "$0")/../../.." && pwd)/config/agent/shared/opencode-settings-shared.conf"
CONFIG_BACKUP="$TMP_DIR/opencode-settings-shared.conf.bak"
cp "$CONFIG_PATH" "$CONFIG_BACKUP"
trap 'cp "$CONFIG_BACKUP" "$CONFIG_PATH"; rm -rf "$TMP_DIR"' EXIT

# These fake archives stand in for the official upstream Linux release assets.
X64_STAGE_DIR="$TMP_DIR/opencode-linux-x64-baseline-musl"
ARM64_STAGE_DIR="$TMP_DIR/opencode-linux-arm64-musl"
mkdir -p "$X64_STAGE_DIR" "$ARM64_STAGE_DIR"
printf 'linux-x64-binary\n' >"$X64_STAGE_DIR/opencode"
printf 'linux-arm64-binary\n' >"$ARM64_STAGE_DIR/opencode"
tar -czf "$TMP_DIR/custom-linux-x64-musl.tar.gz" -C "$X64_STAGE_DIR" opencode
tar -czf "$TMP_DIR/custom-linux-arm64-musl.tar.gz" -C "$ARM64_STAGE_DIR" opencode
X64_ARCHIVE_SHA="$(sha256sum "$TMP_DIR/custom-linux-x64-musl.tar.gz" | awk '{print $1}')"
ARM64_ARCHIVE_SHA="$(sha256sum "$TMP_DIR/custom-linux-arm64-musl.tar.gz" | awk '{print $1}')"

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman records the build command instead of building a real image.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$OPENCODE_TEST_PODMAN_LOG"
EOF

# This fake git lets the test choose between branch policy states.
cat >"$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${OPENCODE_TEST_GIT_MODE:-clean}"
printf 'git %s\n' "$*" >>"$OPENCODE_TEST_PODMAN_LOG"

if [[ "${1-}" == '-C' ]]; then
  shift 2
fi

case "$1 $2 ${3:-}" in
  'rev-parse --verify HEAD')
    if [[ "$mode" == 'no-commit' ]]; then
      exit 1
    fi
    printf 'deadbeef\n'
    ;;
  'symbolic-ref --quiet --short')
    case "$mode" in
      clean|dirty|no-commit|main-origin-synced|main-origin-ahead|main-origin-behind|main-origin-diverged|main-no-upstream|main-wrong-head)
        printf 'main\n'
        ;;
      local-only|feature-upstream)
        printf 'feature-work\n'
        ;;
      *)
        printf 'unexpected branch mode: %s\n' "$mode" >&2
        exit 1
        ;;
    esac
    ;;
  'rev-parse --abbrev-ref --symbolic-full-name')
    case "$mode" in
      local-only|main-no-upstream|no-commit)
        exit 1
        ;;
      clean|dirty|main-origin-synced|main-origin-ahead|main-origin-behind|main-origin-diverged|main-wrong-head)
        printf 'origin/main\n'
        ;;
      feature-upstream)
        printf 'origin/feature-work\n'
        ;;
      *)
        printf 'unexpected upstream mode: %s\n' "$mode" >&2
        exit 1
        ;;
    esac
    ;;
  'symbolic-ref refs/remotes/origin/HEAD ')
    case "$mode" in
      main-wrong-head)
        printf 'refs/remotes/origin/feature-work\n'
        ;;
      *)
        printf 'refs/remotes/origin/main\n'
        ;;
    esac
    ;;
  'rev-list --left-right --count')
    case "$mode" in
      clean|main-origin-synced|main-wrong-head)
        printf '0\t0\n'
        ;;
      main-origin-ahead)
        printf '1\t0\n'
        ;;
      main-origin-behind)
        printf '0\t1\n'
        ;;
      main-origin-diverged)
        printf '2\t3\n'
        ;;
      *)
        printf 'unexpected rev-list mode: %s\n' "$mode" >&2
        exit 1
        ;;
    esac
    ;;
  'update-index -q --refresh')
    ;;
  'diff --numstat '|'diff --summary '|'diff --cached --numstat'|'diff --cached --summary')
    if [[ "$mode" == 'dirty' ]]; then
      printf '1\t0\tscripts/agent/shared/opencode-build\n'
    fi
    ;;
  'ls-files --others --exclude-standard')
    ;;
  *)
    printf 'unexpected git invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

# This fake curl serves release metadata, version checks, and fake asset downloads.
cat >"$FAKE_BIN/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail

output_path=''
args=()

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o)
      output_path="\$2"
      shift 2
      ;;
    -fsSL|-f|-s|-S|-L)
      shift
      ;;
    *)
      args+=("\$1")
      shift
      ;;
  esac
done

url="\${args[\${#args[@]}-1]}"

case "\$url" in
  https://api.github.com/repos/anomalyco/opencode/releases/tags/v1.4.3)
    printf '{"assets":[{"name": "opencode-linux-arm64-musl.tar.gz", "uploader": {"login": "bot"}, "metadata": {"kind": "release"}, "digest": "sha256:%s", "browser_download_url": "https://example.invalid/custom-linux-arm64-musl.tar.gz"},{"name": "opencode-linux-x64-baseline-musl.tar.gz", "uploader": {"login": "bot"}, "metadata": {"kind": "release"}, "digest": "sha256:%s", "browser_download_url": "https://example.invalid/custom-linux-x64-musl.tar.gz"}]}' "$ARM64_ARCHIVE_SHA" "$X64_ARCHIVE_SHA"
    ;;
  https://api.github.com/repos/anomalyco/opencode/releases/latest)
    printf '{"tag_name":"v1.4.4"}'
    ;;
  https://hub.docker.com/v2/repositories/library/alpine/tags/3.23)
    printf '{"name":"3.23","digest":"sha256:newer-alpine-digest"}'
    ;;
  https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100)
    printf '{"results":[{"name":"latest"},{"name":"3.24"},{"name":"3.23"},{"name":"3.22"}]}'
    ;;
  https://example.invalid/custom-linux-x64-musl.tar.gz)
    cp "$TMP_DIR/custom-linux-x64-musl.tar.gz" "\$output_path"
    ;;
  https://example.invalid/custom-linux-arm64-musl.tar.gz)
    cp "$TMP_DIR/custom-linux-arm64-musl.tar.gz" "\$output_path"
    ;;
  *)
    printf 'unexpected curl url: %s\n' "\$url" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/git" "$FAKE_BIN/curl"

# This fake uname keeps the architecture-specific package resolution predictable.
cat >"$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'x86_64\n'
EOF

chmod +x "$FAKE_BIN/uname"

PODMAN_LOG="$TMP_DIR/podman.log"

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-build" >"$TMP_DIR/build.out" 2>"$TMP_DIR/build.err"

assert_file_contains 'build --build-arg OPENCODE_ALPINE_VERSION=' "$PODMAN_LOG" 'build passes the pinned Alpine tag into the container image build'
assert_file_contains '--build-arg OPENCODE_ALPINE_DIGEST=' "$PODMAN_LOG" 'build passes the pinned Alpine digest into the container image build'
assert_file_contains '--build-arg OPENCODE_CONTAINER_HOME=/root' "$PODMAN_LOG" 'build passes the concrete container home path'
assert_file_contains 'config/containers/shared/Containerfile' "$PODMAN_LOG" 'build uses the Hermes-style containerfile path'
assert_file_contains 'OPENCODE_RELEASE_LINUX_X64_ASSET="opencode-linux-x64-baseline-musl.tar.gz"' "$ROOT/config/agent/shared/opencode-settings-shared.conf" 'build reads the pinned x64 musl asset name from shared config'
assert_file_contains 'OPENCODE_RELEASE_LINUX_ARM64_ASSET="opencode-linux-arm64-musl.tar.gz"' "$ROOT/config/agent/shared/opencode-settings-shared.conf" 'build reads the pinned arm64 musl asset name from shared config'
assert_file_not_contains '--build-arg OPENCODE_RELEASE_ARCHIVE_URL=' "$PODMAN_LOG" 'build no longer passes npm release tarball metadata into the container build'
assert_file_not_contains '--build-arg OPENCODE_RELEASE_ARCHIVE_SHA512=' "$PODMAN_LOG" 'build no longer passes npm release checksums into the container build'
assert_file_not_contains '--build-arg OPENCODE_HOST_UID=' "$PODMAN_LOG" 'build no longer passes host uid into the upstream-root image build'
assert_file_not_contains '--build-arg OPENCODE_HOST_GID=' "$PODMAN_LOG" 'build no longer passes host gid into the upstream-root image build'
assert_file_contains 'linux-x64-binary' "$ROOT/dist/opencode-linux-x64-baseline-musl/bin/opencode" 'build stages the official x64 musl binary into the upstream dist path'
assert_file_contains 'linux-arm64-binary' "$ROOT/dist/opencode-linux-arm64-musl/bin/opencode" 'build stages the official arm64 musl binary into the upstream dist path'
assert_file_contains 'Built image: opencode-1.4.3-' "$TMP_DIR/build.out" 'build still prints the built image name after staging binaries'
assert_file_contains 'newer OpenCode version available: 1.4.4' "$TMP_DIR/build.err" 'build warns when a newer OpenCode release exists'
assert_file_contains 'newer Alpine version available: 3.24' "$TMP_DIR/build.err" 'build warns when a newer Alpine tag line exists'
assert_file_contains 'newer Alpine digest available for 3.23' "$TMP_DIR/build.err" 'build warns when a newer Alpine digest exists for the pinned tag'
assert_file_contains 'warning:' "$TMP_DIR/build.err" 'build emits warning output for newer pinned values'
assert_file_not_contains "$(printf '\033[33m')" "$TMP_DIR/build.err" 'build avoids ANSI color escapes when stderr is not a terminal'

MAC_BASE64_BIN="$TMP_DIR/mac-base64-bin"
mkdir -p "$MAC_BASE64_BIN"
ln -sf "$FAKE_BIN/podman" "$MAC_BASE64_BIN/podman"
ln -sf "$FAKE_BIN/git" "$MAC_BASE64_BIN/git"
ln -sf "$FAKE_BIN/curl" "$MAC_BASE64_BIN/curl"
ln -sf "$FAKE_BIN/uname" "$MAC_BASE64_BIN/uname"

cat >"$MAC_BASE64_BIN/base64" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == '-D' ]]; then
  exec /usr/bin/base64 -d
fi

printf 'invalid option\n' >&2
exit 64
EOF

chmod +x "$MAC_BASE64_BIN/base64"

PATH="$MAC_BASE64_BIN:/usr/bin:/bin" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>/dev/null

cat >"$FAKE_BIN/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail

output_path=''
args=()

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o)
      output_path="\$2"
      shift 2
      ;;
    -fsSL|-f|-s|-S|-L)
      shift
      ;;
    *)
      args+=("\$1")
      shift
      ;;
  esac
done

url="\${args[\${#args[@]}-1]}"

case "\$url" in
  https://api.github.com/repos/anomalyco/opencode/releases/tags/v1.4.3)
    printf '{"assets":[{"name": "opencode-linux-arm64-musl.tar.gz", "uploader": {"login": "bot"}, "metadata": {"kind": "release"}, "digest": "sha256:%s", "browser_download_url": "https://example.invalid/custom-linux-arm64-musl.tar.gz"},{"name": "opencode-linux-x64-baseline-musl.tar.gz", "uploader": {"login": "bot"}, "metadata": {"kind": "release"}, "digest": "sha256:%s", "browser_download_url": "https://example.invalid/custom-linux-x64-musl.tar.gz"}]}' "$ARM64_ARCHIVE_SHA" "$X64_ARCHIVE_SHA"
    ;;
  https://example.invalid/custom-linux-x64-musl.tar.gz)
    cp "$TMP_DIR/custom-linux-x64-musl.tar.gz" "\$output_path"
    ;;
  https://example.invalid/custom-linux-arm64-musl.tar.gz)
    cp "$TMP_DIR/custom-linux-arm64-musl.tar.gz" "\$output_path"
    ;;
  *)
    printf 'transient lookup failure\n' >&2
    exit 22
    ;;
esac
EOF

chmod +x "$FAKE_BIN/curl"

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-build" >"$TMP_DIR/fallback.out" 2>"$TMP_DIR/fallback.err"
assert_file_contains 'Built image: opencode-1.4.3-' "$TMP_DIR/fallback.out" 'build still succeeds when latest-version checks fail'
assert_file_not_contains 'newer OpenCode version available:' "$TMP_DIR/fallback.err" 'build skips OpenCode update warnings when the lookup fails'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='local-only' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null
assert_file_contains 'symbolic-ref --quiet --short HEAD' "$PODMAN_LOG" 'build resolves the current branch before applying the build policy'
assert_file_not_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build does not consult cached origin HEAD for a local-only worktree branch'
assert_file_not_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build does not require upstream sync checks for a local-only worktree branch'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-synced' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null
assert_file_contains 'rev-parse --abbrev-ref --symbolic-full-name @{upstream}' "$PODMAN_LOG" 'build resolves the configured upstream when on main'
assert_file_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build checks ahead and behind counts when main tracks origin/main'
assert_file_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build warns from cached origin HEAD only after the main policy passes'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-ahead' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/ahead.stderr"; then
  fail 'build should fail when main is ahead of origin/main'
fi

assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/ahead.stderr" 'build explains ahead-of-origin-main failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-behind' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/behind.stderr"; then
  fail 'build should fail when main is behind origin/main'
fi

assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/behind.stderr" 'build explains behind-origin-main failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-diverged' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/diverged.stderr"; then
  fail 'build should fail when main has diverged from origin/main'
fi

assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/diverged.stderr" 'build explains diverged-origin-main failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-no-upstream' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/main-no-upstream.stderr"; then
  fail 'build should fail when main does not track origin/main'
fi

assert_file_contains 'Build requires main to track origin/main.' "$TMP_DIR/main-no-upstream.stderr" 'build requires main to track origin/main before building'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='feature-upstream' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/feature-upstream.stderr"; then
  fail 'build should fail when a non-main branch tracks a remote upstream'
fi

assert_file_contains 'Build only allows remote-tracking builds from main. Use a clean committed local worktree branch or main tracking origin/main.' "$TMP_DIR/feature-upstream.stderr" 'build rejects remote-tracking non-main branches clearly'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-wrong-head' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/wrong-head.stderr"
assert_file_contains 'warning: local origin/HEAD points to refs/remotes/origin/feature-work, expected refs/remotes/origin/main; ignoring cached remote HEAD for build policy.' "$TMP_DIR/wrong-head.stderr" 'build only warns when cached origin HEAD is wrong locally'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='dirty' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/dirty.stderr"; then
  fail 'build should fail when the checkout is dirty'
fi

assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/dirty.stderr" 'build explains dirty checkout failures'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='no-commit' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/no-commit.stderr"; then
  fail 'build should fail when the checkout has no commits'
fi

assert_file_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/no-commit.stderr" 'build explains missing-commit failures clearly'

printf 'opencode-build behavior checks passed\n'
