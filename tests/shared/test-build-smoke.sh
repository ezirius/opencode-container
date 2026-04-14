#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${OPENCODE_ENABLE_SMOKE_BUILDS:-0}" != "1" ]]; then
	printf 'Skipping smoke builds (set OPENCODE_ENABLE_SMOKE_BUILDS=1 to enable)\n'
	exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
	printf 'Skipping smoke builds (podman not available)\n'
	exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export OPENCODE_BASE_ROOT="$TMPDIR/workspaces"
export OPENCODE_DEVELOPMENT_ROOT="$TMPDIR/opencode-development"
export OPENCODE_IMAGE_NAME="opencode-smoke-local"
export OPENCODE_COMMITSTAMP_OVERRIDE="20260412-220000-smoke01"
export OPENCODE_SKIP_BUILD_CONTEXT_CHECK=1

mkdir -p "$OPENCODE_DEVELOPMENT_ROOT"

"$ROOT/scripts/shared/opencode-build" test latest >"$TMPDIR/build.out"

IMAGE_REF="opencode-smoke-local:test-1.4.3-main-20260412-220000-smoke01"

grep -Fq 'Build source: official release v1.4.3' "$TMPDIR/build.out"
podman image exists "$IMAGE_REF"

ENTRYPOINT="$(podman image inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_REF")"
USER_NAME="$(podman image inspect --format '{{.Config.User}}' "$IMAGE_REF")"
WORKDIR="$(podman image inspect --format '{{.Config.WorkingDir}}' "$IMAGE_REF")"

[[ "$ENTRYPOINT" == '["/usr/bin/tini","--","/usr/local/bin/opencode-wrapper-entrypoint"]' ]]
[[ "$USER_NAME" == 'root' ]]
[[ "$WORKDIR" == '/workspace/opencode-workspace' ]]

podman run --rm --entrypoint /bin/sh "$IMAGE_REF" -lc 'opencode --version >/dev/null && bash --version >/dev/null && curl --version >/dev/null && test -x /usr/bin/tini'

printf 'Smoke build checks passed\n'
