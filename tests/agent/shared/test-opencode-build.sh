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

perl -0pi -e 's/OPENCODE_RELEASE_LINUX_X64_ASSET="[^"]+"/OPENCODE_RELEASE_LINUX_X64_ASSET="custom-linux-x64-musl.tar.gz"/; s/OPENCODE_RELEASE_LINUX_ARM64_ASSET="[^"]+"/OPENCODE_RELEASE_LINUX_ARM64_ASSET="custom-linux-arm64-musl.tar.gz"/' "$CONFIG_PATH"

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

# This fake git lets the test choose between clean and dirty states.
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
  'rev-parse --abbrev-ref --symbolic-full-name')
    case "$mode" in
      local-only|clean|dirty|no-commit)
        exit 1
        ;;
      default-upstream-synced|default-upstream-ahead|default-upstream-behind|default-upstream-diverged)
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
    printf 'refs/remotes/origin/main\n'
    ;;
  'rev-list --left-right --count')
    case "$mode" in
      default-upstream-synced)
        printf '0\t0\n'
        ;;
      default-upstream-ahead)
        printf '1\t0\n'
        ;;
      default-upstream-behind)
        printf '0\t1\n'
        ;;
      default-upstream-diverged)
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
    printf '{"assets":[{"name":"custom-linux-arm64-musl.tar.gz","uploader":{"login":"bot"},"digest":"sha256:%s","browser_download_url":"https://example.invalid/custom-linux-arm64-musl.tar.gz"},{"name":"custom-linux-x64-musl.tar.gz","uploader":{"login":"bot"},"digest":"sha256:%s","browser_download_url":"https://example.invalid/custom-linux-x64-musl.tar.gz"}]}' "$ARM64_ARCHIVE_SHA" "$X64_ARCHIVE_SHA"
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
assert_file_contains 'OPENCODE_RELEASE_LINUX_X64_ASSET="custom-linux-x64-musl.tar.gz"' "$ROOT/config/agent/shared/opencode-settings-shared.conf" 'build reads the pinned x64 musl asset name from shared config'
assert_file_contains 'OPENCODE_RELEASE_LINUX_ARM64_ASSET="custom-linux-arm64-musl.tar.gz"' "$ROOT/config/agent/shared/opencode-settings-shared.conf" 'build reads the pinned arm64 musl asset name from shared config'
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
    printf '{"assets":[{"name":"custom-linux-arm64-musl.tar.gz","uploader":{"login":"bot"},"digest":"sha256:%s","browser_download_url":"https://example.invalid/custom-linux-arm64-musl.tar.gz"},{"name":"custom-linux-x64-musl.tar.gz","uploader":{"login":"bot"},"digest":"sha256:%s","browser_download_url":"https://example.invalid/custom-linux-x64-musl.tar.gz"}]}' "$ARM64_ARCHIVE_SHA" "$X64_ARCHIVE_SHA"
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
assert_file_not_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build does not query the remote default branch for a local-only worktree branch'
assert_file_not_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build does not require upstream sync checks for a local-only worktree branch'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='default-upstream-synced' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null
assert_file_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build checks the remote default branch when the current branch has an upstream'
assert_file_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build checks ahead and behind counts when tracking the remote default branch'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='default-upstream-ahead' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/ahead.stderr"; then
  fail 'build should fail when the current branch is ahead of the remote default-branch upstream'
fi

assert_file_contains 'Build requires the current branch to be pushed and in sync with its upstream when tracking the remote default branch.' "$TMP_DIR/ahead.stderr" 'build explains ahead-of-default-branch failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='default-upstream-behind' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/behind.stderr"; then
  fail 'build should fail when the current branch is behind the remote default-branch upstream'
fi

assert_file_contains 'Build requires the current branch to be pushed and in sync with its upstream when tracking the remote default branch.' "$TMP_DIR/behind.stderr" 'build explains behind-default-branch failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='default-upstream-diverged' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/diverged.stderr"; then
  fail 'build should fail when the current branch has diverged from the remote default-branch upstream'
fi

assert_file_contains 'Build requires the current branch to be pushed and in sync with its upstream when tracking the remote default branch.' "$TMP_DIR/diverged.stderr" 'build explains diverged-default-branch failures clearly'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='feature-upstream' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null
assert_file_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build still resolves the remote default branch when an upstream exists'
assert_file_not_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build skips sync enforcement when the upstream is not the remote default branch'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='dirty' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/dirty.stderr"; then
  fail 'build should fail when the checkout is dirty'
fi

assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/dirty.stderr" 'build explains dirty checkout failures'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='no-commit' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null 2>"$TMP_DIR/no-commit.stderr"; then
  fail 'build should fail when the checkout has no commits'
fi

assert_file_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/no-commit.stderr" 'build explains missing-commit failures clearly'

printf 'opencode-build behavior checks passed\n'
