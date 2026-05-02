#!/usr/bin/env bash

set -euo pipefail

# This test checks that the minimal build script keeps the old git safety checks and builds a thin derived image.

# This finds the repo root so the test can reach the script and shared config.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/shared/shared/test-asserts.sh"

TMP_DIR="$(mktemp -d)"
CONFIG_PATH="$ROOT/configs/shared/opencode/opencode-settings.conf"
trap 'rm -rf "$TMP_DIR"' EXIT

# This loads the saved config values so test expectations track the real naming inputs.
# shellcheck disable=SC1090
source "$CONFIG_PATH"

# This escapes config values before using them inside shell regex assertions.
escape_regex() {
  printf '%s\n' "$1" | sed 's/[][(){}.^$*+?|\\]/\\&/g'
}

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman records build and inspect commands without using a real image store.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >>"$OPENCODE_TEST_PODMAN_LOG"
printf '\n' >>"$OPENCODE_TEST_PODMAN_LOG"

case "${1-} ${2-} ${3-}" in
  'image inspect --format')
    printf 'sha256:%064d\n' 7
    ;;
esac

if [[ "${1-}" == 'tag' && "${OPENCODE_TEST_PODMAN_TAG_FAIL:-0}" == '1' ]]; then
  exit 1
fi
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
      detached-head)
        exit 1
        ;;
      clean|dirty|untracked|no-commit|main-origin-synced|main-origin-ahead|main-origin-behind|main-origin-diverged|main-no-upstream|main-wrong-head)
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
      clean|dirty|untracked|main-origin-synced|main-origin-ahead|main-origin-behind|main-origin-diverged|main-wrong-head)
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
      clean|untracked|main-origin-synced|main-wrong-head)
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
      printf '1\t0\tscripts/shared/opencode/opencode-build\n'
    fi
    ;;
  'ls-files --others --exclude-standard')
    if [[ "$mode" == 'untracked' ]]; then
      printf 'scratch.txt\n'
    fi
    ;;
  *)
    printf 'unexpected git invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

# This fake curl lets the test choose upstream release lookup results without network access.
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${OPENCODE_TEST_CURL_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$OPENCODE_TEST_CURL_LOG"
fi

case "$*" in
  *'--connect-timeout 2 --max-time 5'*) ;;
  *)
    printf 'curl missing bounded timeout arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac

case "${OPENCODE_TEST_LATEST_OPENCODE_VERSION:-same}" in
  same)
    printf '{"tag_name":"v1.14.25"}\n'
    ;;
  newer)
    printf '{"tag_name":"v1.14.26"}\n'
    ;;
  older)
    printf '{"tag_name":"v1.14.20"}\n'
    ;;
  empty)
    printf '{}\n'
    ;;
  fail)
    exit 7
    ;;
  *)
    printf '{"tag_name":"v%s"}\n' "$OPENCODE_TEST_LATEST_OPENCODE_VERSION"
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/git" "$FAKE_BIN/curl"

# These checks prove version freshness uses numeric semver triplets, not strings.
version_equal="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 1.14.25 1.14.25; then printf yes; else printf no; fi')"
assert_equals 'no' "$version_equal" 'build helper does not treat equal semver values as newer'

version_patch_newer="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 1.14.26 1.14.25; then printf yes; else printf no; fi')"
assert_equals 'yes' "$version_patch_newer" 'build helper treats a higher patch version as newer'

version_patch_older="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 1.14.24 1.14.25; then printf yes; else printf no; fi')"
assert_equals 'no' "$version_patch_older" 'build helper rejects a lower patch version as newer'

version_minor_newer="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 1.15.0 1.14.25; then printf yes; else printf no; fi')"
assert_equals 'yes' "$version_minor_newer" 'build helper treats a higher minor version as newer'

version_minor_older="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 1.13.99 1.14.25; then printf yes; else printf no; fi')"
assert_equals 'no' "$version_minor_older" 'build helper rejects a lower minor version as newer'

version_major_newer="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 2.0.0 1.99.99; then printf yes; else printf no; fi')"
assert_equals 'yes' "$version_major_newer" 'build helper treats a higher major version as newer'

version_major_older="$(ROOT="$ROOT" bash -c 'source "$ROOT/libs/shared/opencode/common.sh"; if opencode_version_is_newer_than 0.99.99 1.0.0; then printf yes; else printf no; fi')"
assert_equals 'no' "$version_major_older" 'build helper rejects a lower major version as newer'

PODMAN_LOG="$TMP_DIR/podman.log"
CURL_LOG="$TMP_DIR/curl.log"

: >"$PODMAN_LOG"
if ! PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-build" --help >"$TMP_DIR/help.out" 2>"$TMP_DIR/help.err"; then
  fail 'build --help should succeed'
fi
assert_file_contains 'Usage: scripts/shared/opencode/opencode-build' "$TMP_DIR/help.out" 'build prints usage text for --help'
test ! -s "$TMP_DIR/help.err" || fail 'build --help should not print stderr output'
test ! -s "$PODMAN_LOG" || fail 'build --help should not invoke podman'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/shared/opencode/opencode-build" unexpected >/dev/null 2>"$TMP_DIR/args.err"; then
  fail 'build should reject unexpected arguments'
fi
assert_file_contains 'This script takes no arguments. See --help.' "$TMP_DIR/args.err" 'build rejects unexpected arguments clearly'

PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/opencode/opencode-build" >"$TMP_DIR/build.out" 2>"$TMP_DIR/build.err"
assert_file_contains 'Built image:' "$TMP_DIR/build.out" 'build prints the built image name after a successful thin-image build'
assert_file_contains 'api.github.com/repos/anomalyco/opencode/releases/latest' "$CURL_LOG" 'build checks the latest upstream OpenCode release before build work'
assert_file_not_contains 'newer OpenCode version available' "$TMP_DIR/build.err" 'build does not warn when the upstream release matches the pinned version'
built_image_line="$(grep '^Built image:' "$TMP_DIR/build.out")"
built_image_name="${built_image_line#Built image: }"

assert_file_contains 'build -f' "$PODMAN_LOG" 'build invokes podman build with the canonical containerfile path'
assert_file_contains 'configs/shared/opencode/Containerfile' "$PODMAN_LOG" 'build uses the canonical containerfile path'
assert_file_contains "-t ${OPENCODE_IMAGE_BASENAME}-${OPENCODE_VERSION}-" "$PODMAN_LOG" 'build tags the temporary local image with the version-prefixed naming contract'
assert_file_contains 'image inspect --format' "$PODMAN_LOG" 'build resolves the full image id after building the local image'
assert_file_contains "tag ${OPENCODE_IMAGE_BASENAME}-${OPENCODE_VERSION}-" "$PODMAN_LOG" 'build retags the temporary image into the final image name'
assert_file_contains "rmi ${OPENCODE_IMAGE_BASENAME}-${OPENCODE_VERSION}-" "$PODMAN_LOG" 'build removes the temporary image tag after retagging'
assert_file_not_contains 'OPENCODE_ALPINE_VERSION' "$PODMAN_LOG" 'build does not pass old Alpine pin build arguments'
assert_file_not_contains 'OPENCODE_RELEASE_LINUX_' "$PODMAN_LOG" 'build does not pass old release asset metadata'

# This checks the new image naming contract with a full timestamp and 12-character image id suffix.
expected_image_regex="^$(escape_regex "$OPENCODE_IMAGE_BASENAME")-$(escape_regex "$OPENCODE_VERSION")-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}$"
if [[ ! "$built_image_name" =~ $expected_image_regex ]]; then
  fail 'build should print the version, timestamp, and 12-character image id in the built image name'
fi

: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_LATEST_OPENCODE_VERSION='newer' bash "$ROOT/scripts/shared/opencode/opencode-build" >"$TMP_DIR/build-newer.out" 2>"$TMP_DIR/build-newer.err"
assert_file_contains 'warning: newer OpenCode version available (1.14.26); continuing with pinned version 1.14.25' "$TMP_DIR/build-newer.err" 'build warns when the upstream release differs from the pinned version'
assert_file_not_contains $'\033[' "$TMP_DIR/build-newer.err" 'build keeps warning text plain when stderr is not a terminal'
assert_file_not_contains 'Press any key to continue...' "$TMP_DIR/build-newer.err" 'build does not pause for a newer version in non-interactive runs'
assert_file_contains 'build -f' "$PODMAN_LOG" 'build continues after a newer-version warning'

: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_LATEST_OPENCODE_VERSION='older' bash "$ROOT/scripts/shared/opencode/opencode-build" >"$TMP_DIR/build-older.out" 2>"$TMP_DIR/build-older.err"
assert_file_not_contains 'newer OpenCode version available' "$TMP_DIR/build-older.err" 'build does not warn when the pinned version is ahead of the latest upstream release'
assert_file_contains 'build -f' "$PODMAN_LOG" 'build continues when the pinned version is ahead of latest upstream'

: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_LATEST_OPENCODE_VERSION='empty' bash "$ROOT/scripts/shared/opencode/opencode-build" >"$TMP_DIR/build-empty.out" 2>"$TMP_DIR/build-empty.err"
assert_file_not_contains 'newer OpenCode version available' "$TMP_DIR/build-empty.err" 'build does not warn when the latest release cannot be parsed'
assert_file_contains 'build -f' "$PODMAN_LOG" 'build continues when the latest release cannot be parsed'

: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_LATEST_OPENCODE_VERSION='fail' bash "$ROOT/scripts/shared/opencode/opencode-build" >"$TMP_DIR/build-curl-fail.out" 2>"$TMP_DIR/build-curl-fail.err"
assert_file_not_contains 'newer OpenCode version available' "$TMP_DIR/build-curl-fail.err" 'build does not warn when the latest release lookup fails'
assert_file_contains 'build -f' "$PODMAN_LOG" 'build continues when the latest release lookup fails'

: >"$PODMAN_LOG"
: >"$CURL_LOG"
run_with_tty "$TMP_DIR/build-newer-tty.out" env PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_CURL_LOG="$CURL_LOG" OPENCODE_TEST_LATEST_OPENCODE_VERSION='newer' bash "$ROOT/scripts/shared/opencode/opencode-build"
assert_file_contains $'\033[33mwarning:\033[0m newer OpenCode version available (1.14.26); continuing with pinned version 1.14.25' "$TMP_DIR/build-newer-tty.out" 'build shows an amber newer-version warning when stderr is a terminal'
assert_file_contains 'Press any key to continue...' "$TMP_DIR/build-newer-tty.out" 'build pauses for acknowledgement when stdin and stderr are terminals'
assert_file_contains 'build -f' "$PODMAN_LOG" 'build continues after the interactive newer-version warning path'

: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_PODMAN_TAG_FAIL='1' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/tag-fail.err"; then
  fail 'build should fail when retagging the temporary image fails'
fi
assert_file_contains "rmi ${OPENCODE_IMAGE_BASENAME}-${OPENCODE_VERSION}-" "$PODMAN_LOG" 'build cleans up the temporary image tag when retagging fails'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='local-only' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null
assert_file_contains 'symbolic-ref --quiet --short HEAD' "$PODMAN_LOG" 'build resolves the current branch before applying the build policy'
assert_file_not_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build does not consult cached origin HEAD for a local-only worktree branch'
assert_file_not_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build does not require upstream sync checks for a local-only worktree branch'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-synced' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null
assert_file_contains 'rev-parse --abbrev-ref --symbolic-full-name @{upstream}' "$PODMAN_LOG" 'build resolves the configured upstream when on main'
assert_file_contains 'rev-list --left-right --count HEAD...@{upstream}' "$PODMAN_LOG" 'build checks ahead and behind counts when main tracks origin/main'
assert_file_contains 'symbolic-ref refs/remotes/origin/HEAD' "$PODMAN_LOG" 'build warns from cached origin HEAD only after the main policy passes'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-ahead' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/ahead.stderr"; then
  fail 'build should fail when main is ahead of origin/main'
fi
assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/ahead.stderr" 'build explains ahead-of-origin-main failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-behind' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/behind.stderr"; then
  fail 'build should fail when main is behind origin/main'
fi
assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/behind.stderr" 'build explains behind-origin-main failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-origin-diverged' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/diverged.stderr"; then
  fail 'build should fail when main has diverged from origin/main'
fi
assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/diverged.stderr" 'build explains diverged-origin-main failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-no-upstream' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/main-no-upstream.stderr"; then
  fail 'build should fail when main does not track origin/main'
fi
assert_file_contains 'Build requires main to track origin/main.' "$TMP_DIR/main-no-upstream.stderr" 'build requires main to track origin/main before building'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='feature-upstream' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/feature-upstream.stderr"; then
  fail 'build should fail when a non-main branch tracks a remote upstream'
fi
assert_file_contains 'Build only allows remote-tracking builds from main. Use a clean committed local worktree branch or main tracking origin/main.' "$TMP_DIR/feature-upstream.stderr" 'build rejects remote-tracking non-main branches clearly'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='main-wrong-head' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/wrong-head.stderr"
assert_file_contains 'warning: local origin/HEAD points to refs/remotes/origin/feature-work, expected refs/remotes/origin/main; ignoring cached remote HEAD for build policy.' "$TMP_DIR/wrong-head.stderr" 'build only warns when cached origin HEAD is wrong locally'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='dirty' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/dirty.stderr"; then
  fail 'build should fail when the checkout is dirty'
fi
assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/dirty.stderr" 'build explains dirty checkout failures'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='untracked' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/untracked.stderr"; then
  fail 'build should fail when the checkout has untracked files'
fi
assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/untracked.stderr" 'build explains untracked checkout failures'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='no-commit' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/no-commit.stderr"; then
  fail 'build should fail when the checkout has no commits'
fi
assert_file_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/no-commit.stderr" 'build explains missing-commit failures clearly'

if PATH="$FAKE_BIN:$PATH" OPENCODE_TEST_PODMAN_LOG="$PODMAN_LOG" OPENCODE_TEST_GIT_MODE='detached-head' bash "$ROOT/scripts/shared/opencode/opencode-build" >/dev/null 2>"$TMP_DIR/detached-head.stderr"; then
  fail 'build should fail clearly when HEAD is detached'
fi
assert_file_contains 'Build requires an attached branch HEAD.' "$TMP_DIR/detached-head.stderr" 'build explains detached HEAD failures clearly'

printf 'opencode-build behaviour checks passed\n'
