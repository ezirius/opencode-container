#!/usr/bin/env bash

set -euo pipefail

# This test checks that the repo keeps the Hermes-style layout and command surface.

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

# These checks prove the normalized Hermes-style paths are present.
test -f "$ROOT/README.md"
test -f "$ROOT/AGENTS.md"
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
grep -q '^OPENCODE_CONTAINER_HOME="/home/opencode"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_WORKSPACE="/workspace/general"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_DEVELOPMENT="/workspace/development"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_CONTAINER_PROJECT="/workspace/project"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"
grep -q '^OPENCODE_HOST_WORKSPACE_DIRNAME="opencode-general"$' "$ROOT/config/agent/shared/opencode-settings-shared.conf"

# These checks make sure docs and script headers describe the current behavior.
grep -q '`scripts/agent/shared/opencode-build`' "$ROOT/README.md"
grep -q '`scripts/agent/shared/opencode-run`' "$ROOT/README.md"
grep -q '`scripts/agent/shared/opencode-shell`' "$ROOT/README.md"
grep -q '/workspace/general' "$ROOT/docs/usage/shared/usage.md"
grep -q '/workspace/development' "$ROOT/docs/usage/shared/usage.md"
grep -q '/workspace/project' "$ROOT/docs/usage/shared/usage.md"
grep -q '^# This file holds the shared shell helpers used by the wrapper scripts\.$' "$ROOT/lib/shell/shared/common.sh"
grep -q '^# This script builds a fresh OpenCode image from the saved repo settings\.$' "$ROOT/scripts/agent/shared/opencode-build"
grep -q '^# This script starts one saved workspace container and opens OpenCode inside it\.$' "$ROOT/scripts/agent/shared/opencode-run"
grep -q '^# This script opens bash by default, or runs a command inside a running workspace container\.$' "$ROOT/scripts/agent/shared/opencode-shell"

echo "OpenCode Hermes-style layout checks passed"
