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
test ! -d "$ROOT/tests/shared"

# These checks prove the normalized wrapper paths are present.
test -f "$ROOT/README.md"
test -f "$ROOT/AGENTS.md"
test -f "$ROOT/.dockerignore"
test -f "$ROOT/config/agent/shared/opencode-settings-shared.conf"
test -f "$ROOT/config/containers/shared/Containerfile"
test -f "$ROOT/docs/usage/shared/usage.md"
test -f "$ROOT/docs/usage/shared/architecture.md"
test -f "$ROOT/lib/shell/shared/common.sh"
test -f "$ROOT/scripts/agent/shared/opencode-build"
test -f "$ROOT/scripts/agent/shared/opencode-run"
test -f "$ROOT/scripts/agent/shared/opencode-shell"
test -f "$ROOT/tests/agent/shared/test-asserts.sh"
test -f "$ROOT/tests/agent/shared/test-all.sh"
test -f "$ROOT/tests/agent/shared/test-opencode-build.sh"
test -f "$ROOT/tests/agent/shared/test-opencode-layout.sh"
test -f "$ROOT/tests/agent/shared/test-opencode-run.sh"
test -f "$ROOT/tests/agent/shared/test-opencode-shell.sh"

# These checks make sure the config keeps the concrete OpenCode path contract.
grep -q '^OPENCODE_IMAGE_REPOSITORY="ghcr.io/anomalyco/opencode"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_VERSION="1.14.25"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_TARGET_ARCH="arm64"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_HOME="/root"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_WORKSPACE="/workspace/general"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_PROJECTS="/workspace/projects"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_PROJECT="/workspace/project"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-general"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_SHELL_COMMAND="nu"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"

# These checks make sure the containerfile stays a thin wrapper around the official image.
grep -q '^FROM ghcr.io/anomalyco/opencode:1.14.25$' "$ROOT/config/containers/shared/Containerfile"
grep -q 'apk add --no-cache .*git' "$ROOT/config/containers/shared/Containerfile"
grep -q 'apk add --no-cache .*bash' "$ROOT/config/containers/shared/Containerfile"
grep -q 'apk add --no-cache .*nushell' "$ROOT/config/containers/shared/Containerfile"
grep -q '^WORKDIR /workspace/project$' "$ROOT/config/containers/shared/Containerfile"
grep -q '^ENTRYPOINT \["opencode"\]$' "$ROOT/config/containers/shared/Containerfile"
# These fail explicitly because negated grep does not trip errexit when it matches.
if grep -q '^ARG OPENCODE_ALPINE_VERSION' "$ROOT/config/containers/shared/Containerfile"; then
  printf 'Containerfile must not define OPENCODE_ALPINE_VERSION\n' >&2
  exit 1
fi

if grep -q '^COPY dist/' "$ROOT/config/containers/shared/Containerfile"; then
  printf 'Containerfile must not copy local dist output\n' >&2
  exit 1
fi

if grep -q '^USER ' "$ROOT/config/containers/shared/Containerfile"; then
  printf 'Containerfile must not override the upstream user\n' >&2
  exit 1
fi

# These checks make sure docs and script headers describe the current behavior.
grep -q '`scripts/agent/shared/opencode-build`' "$ROOT/README.md"
grep -q '`scripts/agent/shared/opencode-run`' "$ROOT/README.md"
grep -q 'scripts/agent/shared/opencode-shell <workspace> <project> \[command...\]`' "$ROOT/README.md"
grep -q 'tests/agent/shared/test-asserts.sh' "$ROOT/README.md"
grep -q 'tests/agent/shared/test-all.sh' "$ROOT/README.md"
grep -q 'docs/superpowers/plans/2026-04-16-opencode-project-runtime-and-status.md' "$ROOT/README.md"
grep -q '1.14.25' "$ROOT/README.md"
grep -q 'arm64' "$ROOT/README.md"
grep -q 'opencode attach http://127.0.0.1:4096' "$ROOT/README.md"
# This fails explicitly because negated grep does not trip errexit when it matches.
if grep -q 'host\.containers\.internal:<published-port>' "$ROOT/README.md"; then
  printf 'README must not document host.containers.internal project attach flow\n' >&2
  exit 1
fi
grep -q '/workspace/general' "$ROOT/docs/usage/shared/usage.md"
grep -q '/workspace/development' "$ROOT/docs/usage/shared/usage.md"
grep -q '/workspace/projects' "$ROOT/docs/usage/shared/usage.md"
grep -q '/workspace/project' "$ROOT/docs/usage/shared/usage.md"
grep -q '/root' "$ROOT/docs/usage/shared/usage.md"
grep -q 'serve --hostname 0.0.0.0 --port 4096' "$ROOT/docs/usage/shared/usage.md"
grep -q 'http://127.0.0.1:4096' "$ROOT/docs/usage/shared/usage.md"
# This fails explicitly because negated grep does not trip errexit when it matches.
if grep -q 'host\.containers\.internal:<published-port>' "$ROOT/docs/usage/shared/usage.md"; then
  printf 'usage docs must not document host.containers.internal project attach flow\n' >&2
  exit 1
fi
grep -q 'arm64' "$ROOT/docs/usage/shared/usage.md"
grep -q '`nu`' "$ROOT/docs/usage/shared/usage.md"
grep -q '`scripts/agent/shared/opencode-build`' "$ROOT/docs/usage/shared/usage.md"
grep -q 'scripts/agent/shared/opencode-shell <workspace> <project> \[command...\]`' "$ROOT/docs/usage/shared/usage.md"
grep -q 'opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>' "$ROOT/docs/usage/shared/usage.md"
grep -q '<development-root-basename>' "$ROOT/docs/usage/shared/usage.md"
grep -q '<workspace>-<project>' "$ROOT/docs/usage/shared/usage.md"
grep -q '`nu`' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'git' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'opencode attach http://127.0.0.1:4096' "$ROOT/docs/usage/shared/architecture.md"
# This fails explicitly because negated grep does not trip errexit when it matches.
if grep -q 'host\.containers\.internal:<published-port>' "$ROOT/docs/usage/shared/architecture.md"; then
  printf 'architecture docs must not document host.containers.internal project attach flow\n' >&2
  exit 1
fi
grep -q '/workspace/projects' "$ROOT/docs/usage/shared/architecture.md"
grep -q '^IMAGE_ID=.1234567890ab.$' "$ROOT/tests/agent/shared/test-opencode-shell.sh"
grep -q '^OLD_IMAGE_ID=.fedcba098765.$' "$ROOT/tests/agent/shared/test-opencode-shell.sh"
grep -q '`scripts/agent/shared/opencode-shell`' "$ROOT/AGENTS.md"
grep -q '\[command...\]' "$ROOT/AGENTS.md"
grep -q '`config/agent`' "$ROOT/AGENTS.md"
grep -q '\[repo base\]/category/subcategory/scope/file' "$ROOT/AGENTS.md"
grep -q '\[repo base\]/scripts/agent/shared/opencode-run' "$ROOT/AGENTS.md"
grep -q '^- `plans`$' "$ROOT/AGENTS.md"
grep -q '^- `docs/superpowers/...`$' "$ROOT/AGENTS.md"
grep -q '^- `docs/superpowers/plans/2026-04-16-opencode-project-runtime-and-status.md`$' "$ROOT/AGENTS.md"
grep -q '`config/containers/shared/Containerfile`' "$ROOT/AGENTS.md"
grep -q '`tests/agent/shared/test-all.sh`' "$ROOT/AGENTS.md"
grep -q '`.dockerignore`' "$ROOT/AGENTS.md"
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
  'config/' \
  'scripts/' \
  'docs/' \
  'tests/' \
  'lib/' \
  'config/containers/' \
  'config/containers/shared/' \
  'config/containers/shared/Containerfile'
do
  if grep -qxF "$ignored_repo_path" "$ROOT/.dockerignore"; then
    printf '.dockerignore must not exclude repo-owned path: %s\n' "$ignored_repo_path" >&2
    exit 1
  fi
done

echo "OpenCode layout checks passed"
