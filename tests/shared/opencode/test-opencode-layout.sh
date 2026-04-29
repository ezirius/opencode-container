#!/usr/bin/env bash

set -euo pipefail

# This test checks that the repo keeps the derived-image wrapper layout and command surface.

# This finds the repo root so every path check runs from the same place.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# These checks prove the old legacy paths are gone.
test ! -f "$ROOT/config/shared/opencode.conf"
test ! -f "$ROOT/config/shared/tool-versions.conf"
test ! -f "$ROOT/config/containers/Containerfile.wrapper"
test ! -f "$ROOT/config/containers/Containerfile.source-base.template"
test ! -f "$ROOT/config/containers/entrypoint.sh"
test ! -f "$ROOT/docs/shared/usage.md"
test ! -f "$ROOT/docs/shared/implementation-plan.md"
test ! -f "$ROOT/lib/shell/common.sh"
test ! -f "$ROOT/scripts/shared/opencode-bootstrap"
test ! -f "$ROOT/scripts/shared/opencode-build"
test ! -f "$ROOT/scripts/shared/opencode-logs"
test ! -f "$ROOT/scripts/shared/opencode-open"
test ! -f "$ROOT/scripts/shared/opencode-remove"
test ! -f "$ROOT/scripts/shared/opencode-shell"
test ! -f "$ROOT/scripts/shared/opencode-start"
test ! -f "$ROOT/scripts/shared/opencode-status"
test ! -f "$ROOT/scripts/shared/opencode-stop"
test ! -d "$ROOT/config"
test ! -d "$ROOT/lib"
test ! -d "$ROOT/docs/usage"
test ! -d "$ROOT/docs/superpowers"
test ! -d "$ROOT/scripts/agent"
test ! -d "$ROOT/tests/agent"

# These checks prove the normalized wrapper paths are present.
test -f "$ROOT/README.md"
test -f "$ROOT/AGENTS.md"
test -f "$ROOT/.dockerignore"
test -f "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
test -f "$ROOT/configs/shared/opencode/Containerfile"
test -f "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
test -f "$ROOT/docs/shared/opencode/usage.md"
test -f "$ROOT/docs/shared/opencode/architecture.md"
test -f "$ROOT/libs/shared/opencode/common.sh"
test -f "$ROOT/scripts/shared/opencode/opencode-build"
test -f "$ROOT/scripts/shared/opencode/opencode-run"
test -f "$ROOT/scripts/shared/opencode/opencode-shell"
test -f "$ROOT/tests/shared/shared/test-asserts.sh"
test -f "$ROOT/tests/shared/opencode/test-all.sh"
test -f "$ROOT/tests/shared/opencode/test-opencode-build.sh"
test -f "$ROOT/tests/shared/opencode/test-opencode-layout.sh"
test -f "$ROOT/tests/shared/opencode/test-opencode-run.sh"
test -f "$ROOT/tests/shared/opencode/test-opencode-shell.sh"

# These checks make sure the config keeps the concrete OpenCode path contract.
grep -q '^OPENCODE_VERSION="1.14.25"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_SERVER_PORT="4096"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_BASE_PATH="\$HOME/Documents/Ezirius/.applications-data/.containers-artificial-intelligence"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_DEVELOPMENT_ROOT="\$HOME/Documents/Ezirius/Development/OpenCode"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_WORKSPACES="ezirius:10000 nala:20000"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_HOME="/root"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_WORKSPACE="/workspace/general"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_PROJECTS="/workspace/projects"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_PROJECT="/workspace/project"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_SHARED_CONTAINER_SCOPE="infrastructure"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-general"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_DEFAULT_COMMAND="opencode"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_SHELL_COMMAND="nu"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_RELEASE_API_URL="https://api.github.com/repos/anomalyco/opencode/releases/latest"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS="2"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS="5"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_SERVER_HOSTNAME="0.0.0.0"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_ATTACH_HOST="127.0.0.1"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_RUNNING_WAIT_ATTEMPTS="10"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_RUNNING_WAIT_SECONDS="1"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_STABLE_WAIT_ATTEMPTS="2"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_STABLE_WAIT_SECONDS="1"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS="5"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="1"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="1"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"
grep -q '^OPENCODE_PUBLISHED_URL_WAIT_SECONDS="1"$' "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"

# These checks make sure the containerfile stays a thin wrapper around the official image.
grep -q '^FROM ghcr.io/anomalyco/opencode:1.14.25$' "$ROOT/configs/shared/opencode/Containerfile"
grep -q 'apk add --no-cache .*git' "$ROOT/configs/shared/opencode/Containerfile"
grep -q 'apk add --no-cache .*bash' "$ROOT/configs/shared/opencode/Containerfile"
grep -q 'apk add --no-cache .*nushell' "$ROOT/configs/shared/opencode/Containerfile"
grep -q '^WORKDIR /workspace/project$' "$ROOT/configs/shared/opencode/Containerfile"
grep -q '^ENTRYPOINT \["opencode"\]$' "$ROOT/configs/shared/opencode/Containerfile"

# These fail explicitly because negated grep does not trip errexit when it matches.
if grep -q '^ARG OPENCODE_ALPINE_VERSION' "$ROOT/configs/shared/opencode/Containerfile"; then
  printf 'Containerfile must not define OPENCODE_ALPINE_VERSION\n' >&2
  exit 1
fi

if grep -q '^COPY dist/' "$ROOT/configs/shared/opencode/Containerfile"; then
  printf 'Containerfile must not copy local dist output\n' >&2
  exit 1
fi

if grep -q '^USER ' "$ROOT/configs/shared/opencode/Containerfile"; then
  printf 'Containerfile must not override the upstream user\n' >&2
  exit 1
fi

# These checks make sure docs and script headers describe the current behaviour.
grep -q '\[repo base\]/category/os/app-or-shared/file' "$ROOT/README.md"
grep -q '`scripts/shared/opencode/opencode-build`' "$ROOT/README.md"
grep -q '`scripts/shared/opencode/opencode-run`' "$ROOT/README.md"
grep -q 'scripts/shared/opencode/opencode-shell <workspace> <project> \[command...\]`' "$ROOT/README.md"
grep -q 'tests/shared/shared/test-asserts.sh' "$ROOT/README.md"
grep -q 'tests/shared/opencode/test-all.sh' "$ROOT/README.md"
grep -q 'docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md' "$ROOT/README.md"
grep -q '1.14.25' "$ROOT/README.md"
grep -q 'OPENCODE_SERVER_PORT' "$ROOT/README.md"
grep -q 'opencode attach http://\$OPENCODE_ATTACH_HOST:\$OPENCODE_SERVER_PORT' "$ROOT/README.md"
grep -q 'clean committed checkout' "$ROOT/README.md"
grep -q 'attached branch HEAD' "$ROOT/README.md"
grep -q 'main` to track `origin/main' "$ROOT/README.md"
grep -q 'main` to be pushed and in sync with `origin/main' "$ROOT/README.md"
grep -q 'opencode-shell` prompts for workspace and project' "$ROOT/README.md"
grep -q 'opencode-shell <workspace>` prompts for project' "$ROOT/README.md"

if grep -q 'host\.containers\.internal:<published-port>' "$ROOT/README.md"; then
  printf 'README must not document host.containers.internal project attach flow\n' >&2
  exit 1
fi

grep -q '/workspace/general' "$ROOT/docs/shared/opencode/usage.md"
grep -q '/workspace/development' "$ROOT/docs/shared/opencode/usage.md"
grep -q '/workspace/projects' "$ROOT/docs/shared/opencode/usage.md"
grep -q '/workspace/project' "$ROOT/docs/shared/opencode/usage.md"
grep -q '/root' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'serve --hostname \$OPENCODE_SERVER_HOSTNAME --port \$OPENCODE_SERVER_PORT' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'http://\$OPENCODE_ATTACH_HOST:\$OPENCODE_SERVER_PORT' "$ROOT/docs/shared/opencode/usage.md"

if grep -q 'host\.containers\.internal:<published-port>' "$ROOT/docs/shared/opencode/usage.md"; then
  printf 'usage docs must not document host.containers.internal project attach flow\n' >&2
  exit 1
fi

grep -q 'OPENCODE_SERVER_PORT' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'OPENCODE_SERVER_HOSTNAME' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'OPENCODE_ATTACH_HOST' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'clean committed checkout' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'attached branch HEAD' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'main` to track `origin/main' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'main` to be pushed and in sync with `origin/main' "$ROOT/docs/shared/opencode/usage.md"
grep -q '`nu`' "$ROOT/docs/shared/opencode/usage.md"
grep -q '`scripts/shared/opencode/opencode-build`' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'scripts/shared/opencode/opencode-shell <workspace> <project> \[command...\]`' "$ROOT/docs/shared/opencode/usage.md"
grep -q 'opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>' "$ROOT/docs/shared/opencode/usage.md"
grep -q '<workspace>-infrastructure' "$ROOT/docs/shared/opencode/usage.md"
grep -q '<workspace>-<project>' "$ROOT/docs/shared/opencode/usage.md"
grep -q '`nu`' "$ROOT/docs/shared/opencode/architecture.md"
grep -q 'git' "$ROOT/docs/shared/opencode/architecture.md"
grep -q 'OPENCODE_SERVER_PORT' "$ROOT/docs/shared/opencode/architecture.md"

if grep -q 'host\.containers\.internal:<published-port>' "$ROOT/docs/shared/opencode/architecture.md"; then
  printf 'architecture docs must not document host.containers.internal project attach flow\n' >&2
  exit 1
fi

grep -q '/workspace/projects' "$ROOT/docs/shared/opencode/architecture.md"
grep -q '`tests/shared/shared/test-asserts.sh`' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q '`tests/shared/opencode/test-opencode-build.sh`' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q '`tests/shared/opencode/test-opencode-layout.sh`' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q '`tests/shared/opencode/test-opencode-run.sh`' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q '`tests/shared/opencode/test-opencode-shell.sh`' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q 'private project containers' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q 'http://\$OPENCODE_ATTACH_HOST:\$OPENCODE_SERVER_PORT' "$ROOT/docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md"
grep -q '^IMAGE_ID=.1234567890ab.$' "$ROOT/tests/shared/opencode/test-opencode-shell.sh"
grep -q '^OLD_IMAGE_ID=.fedcba098765.$' "$ROOT/tests/shared/opencode/test-opencode-shell.sh"
grep -q '`scripts/shared/opencode/opencode-shell`' "$ROOT/AGENTS.md"
grep -q '\[command...\]' "$ROOT/AGENTS.md"
grep -q '`configs/shared/opencode/opencode-settings-shared.conf`' "$ROOT/AGENTS.md"
grep -q '\[repo base\]/category/os/app-or-shared/file' "$ROOT/AGENTS.md"
grep -q '\[repo base\]/scripts/shared/opencode/opencode-run' "$ROOT/AGENTS.md"
grep -q '^- `configs`$' "$ROOT/AGENTS.md"
grep -q '^- `libs`$' "$ROOT/AGENTS.md"
grep -q '^- `docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md`$' "$ROOT/AGENTS.md"
grep -q '`configs/shared/opencode/Containerfile`' "$ROOT/AGENTS.md"
grep -q '`tests/shared/opencode/test-all.sh`' "$ROOT/AGENTS.md"
grep -q '`.dockerignore`' "$ROOT/AGENTS.md"
grep -q 'Keep `.gitignore` at the repository root.' "$ROOT/AGENTS.md"

if grep -q 'Use the cleanup worktree at `.worktrees/cleanup`' "$ROOT/AGENTS.md"; then
  printf 'AGENTS must not include local cleanup-worktree instructions\n' >&2
  exit 1
fi

if grep -q 'moving in-progress cleanup changes into a worktree' "$ROOT/AGENTS.md"; then
  printf 'AGENTS must not include cleanup-migration workflow instructions\n' >&2
  exit 1
fi

grep -q '^\.git$' "$ROOT/.dockerignore"
grep -q '^\.git/$' "$ROOT/.dockerignore"
grep -q '^\.worktrees/$' "$ROOT/.dockerignore"
grep -q '^build/$' "$ROOT/.dockerignore"
grep -q '^dist/$' "$ROOT/.dockerignore"
grep -q '^coverage/$' "$ROOT/.dockerignore"
grep -q '^tmp/$' "$ROOT/.dockerignore"
grep -q '^\.tmp/$' "$ROOT/.dockerignore"
grep -q '^temp/$' "$ROOT/.dockerignore"
grep -q '^cache/$' "$ROOT/.dockerignore"
grep -q '^__pycache__/$' "$ROOT/.dockerignore"
grep -q '^\*.pyc$' "$ROOT/.dockerignore"
grep -q '^\.DS_Store$' "$ROOT/.dockerignore"

# These keep repo-owned source and container build inputs inside the build context.
for ignored_repo_path in \
  'configs/' \
  'scripts/' \
  'docs/' \
  'tests/' \
  'libs/' \
  'configs/shared/' \
  'configs/shared/opencode/' \
  'configs/shared/opencode/Containerfile'
do
  if grep -qxF "$ignored_repo_path" "$ROOT/.dockerignore"; then
    printf '.dockerignore must not exclude repo-owned path: %s\n' "$ignored_repo_path" >&2
    exit 1
  fi
done

# These checks enforce the required shell-file documentation contract.
for shell_path in \
  "$ROOT/libs/shared/opencode/common.sh" \
  "$ROOT/scripts/shared/opencode/opencode-build" \
  "$ROOT/scripts/shared/opencode/opencode-run" \
  "$ROOT/scripts/shared/opencode/opencode-shell" \
  "$ROOT/tests/shared/shared/test-asserts.sh" \
  "$ROOT/tests/shared/opencode/test-all.sh" \
  "$ROOT/tests/shared/opencode/test-opencode-build.sh" \
  "$ROOT/tests/shared/opencode/test-opencode-layout.sh" \
  "$ROOT/tests/shared/opencode/test-opencode-run.sh" \
  "$ROOT/tests/shared/opencode/test-opencode-shell.sh"
do
  if ! awk '
    NR <= 12 && /^# / { header_found=1 }
    /^[A-Za-z0-9_]+\(\) \{/ {
      if (previous_nonblank !~ /^# /) {
        printf "%s:%d\n", FILENAME, NR
        missing=1
      }
    }
    /^[[:space:]]*(if|while|for|case)\b/ {
      if (NR > 12 && previous_nonblank !~ /^# / && previous_nonblank !~ /^(do|then|else|elif|in|\{|\}|;;)/) {
        printf "%s:%d\n", FILENAME, NR
        missing=1
      }
    }
    /^[[:space:]]*$/ { next }
    { previous_nonblank=$0 }
    END {
      if (!header_found) {
        printf "%s:header\n", FILENAME
        missing=1
      }
      exit missing
    }
  ' "$shell_path"; then
    printf 'Shell comment contract failed for %s\n' "$shell_path" >&2
    exit 1
  fi
done

echo "OpenCode layout checks passed"
