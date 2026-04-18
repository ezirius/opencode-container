#!/usr/bin/env bash

set -euo pipefail

# This test checks that the build script uses the reduced Hermes-style build contract.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

# This fake curl serves the release metadata that the build script resolves.
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url="${@: -1}"
case "$url" in
  https://registry.npmjs.org/opencode-linux-x64/1.4.3)
    printf '{"dist":{"tarball":"https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-1.4.3.tgz","integrity":"sha512-RS6TsDqTUrW5sefxD1KD9Xy9mSYGXAlr2DlGrdi8vNm9e/Bt4r4u557VB7f/Uj2CxTt2Gf7OWl08ZoPlxMJ5Gg=="}}'
    ;;
  *)
    printf 'unexpected curl url: %s\n' "$url" >&2
    exit 1
    ;;
esac
EOF

# This fake id keeps host uid and gid resolution controllable.
cat >"$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1-}" in
  -u) printf '%s\n' "${OPENCODE_TEST_HOST_UID:-1001}" ;;
  -g) printf '%s\n' "${OPENCODE_TEST_HOST_GID:-1001}" ;;
  *) printf 'unexpected id invocation\n' >&2; exit 1 ;;
esac
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/git" "$FAKE_BIN/curl" "$FAKE_BIN/id"

# This fake uname keeps the architecture-specific package resolution predictable.
cat >"$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'x86_64\n'
EOF

chmod +x "$FAKE_BIN/uname"

PODMAN_LOG="$TMP_DIR/podman.log"

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-build"

assert_file_contains 'build --build-arg OPENCODE_HOST_UID=' "$PODMAN_LOG" 'build passes the host uid into the container image build'
assert_file_contains '--build-arg OPENCODE_HOST_GID=' "$PODMAN_LOG" 'build passes the host gid into the container image build'
assert_file_contains '--build-arg OPENCODE_CONTAINER_HOME=/home/opencode' "$PODMAN_LOG" 'build passes the concrete container home path'
assert_file_contains '--build-arg OPENCODE_CONTAINER_WORKSPACE=/workspace/general' "$PODMAN_LOG" 'build passes the concrete workspace path'
assert_file_contains '--build-arg OPENCODE_CONTAINER_DEVELOPMENT=/workspace/development' "$PODMAN_LOG" 'build passes the concrete development path'
assert_file_contains '--build-arg OPENCODE_CONTAINER_PROJECT=/workspace/project' "$PODMAN_LOG" 'build passes the concrete project path'
assert_file_contains '--build-arg OPENCODE_RELEASE_ARCHIVE_URL=https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-1.4.3.tgz' "$PODMAN_LOG" 'build resolves the OpenCode release tarball url from npm metadata'
assert_file_contains '--build-arg OPENCODE_RELEASE_ARCHIVE_SHA512=' "$PODMAN_LOG" 'build resolves the release sha512 from npm metadata'
assert_file_contains 'config/containers/shared/Containerfile' "$PODMAN_LOG" 'build uses the Hermes-style containerfile path'
assert_file_contains '--build-arg OPENCODE_HOST_UID=1001' "$PODMAN_LOG" 'build uses the detected non-root host uid by default'
assert_file_contains '--build-arg OPENCODE_HOST_GID=1001' "$PODMAN_LOG" 'build uses the detected non-root host gid by default'

MAC_BASE64_BIN="$TMP_DIR/mac-base64-bin"
mkdir -p "$MAC_BASE64_BIN"
ln -sf "$FAKE_BIN/podman" "$MAC_BASE64_BIN/podman"
ln -sf "$FAKE_BIN/git" "$MAC_BASE64_BIN/git"
ln -sf "$FAKE_BIN/curl" "$MAC_BASE64_BIN/curl"
ln -sf "$FAKE_BIN/id" "$MAC_BASE64_BIN/id"
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

PATH="$MAC_BASE64_BIN:/usr/bin:/bin" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_HOST_UID='0' OPENCODE_TEST_HOST_GID='0' SUDO_UID='4242' SUDO_GID='4343' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null
assert_file_contains '--build-arg OPENCODE_HOST_UID=4242' "$PODMAN_LOG" 'build prefers sudo caller uid when the build itself runs as root'
assert_file_contains '--build-arg OPENCODE_HOST_GID=4343' "$PODMAN_LOG" 'build prefers sudo caller gid when the build itself runs as root'

: >"$PODMAN_LOG"
env -u SUDO_UID -u SUDO_GID PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_HOST_UID='0' OPENCODE_TEST_HOST_GID='0' bash "$ROOT/scripts/agent/shared/opencode-build" >/dev/null
assert_file_contains '--build-arg OPENCODE_HOST_UID=0' "$PODMAN_LOG" 'build preserves true root uid when invoked directly as root without sudo metadata'
assert_file_contains '--build-arg OPENCODE_HOST_GID=0' "$PODMAN_LOG" 'build preserves true root gid when invoked directly as root without sudo metadata'

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
