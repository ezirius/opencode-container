#!/usr/bin/env bash
set -euo pipefail

OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT:-$HOME/Documents/OpenCode}"
OPENCODE_IMAGE_NAME="${OPENCODE_IMAGE_NAME:-opencode-arm64}"
OPENCODE_PLATFORM="${OPENCODE_PLATFORM:-linux/arm64}"
OPENCODE_VERSION="${OPENCODE_VERSION:-1.2.27}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

usage_error() {
  echo "Usage: $*" >&2
  exit 1
}

require_podman() {
  command -v podman >/dev/null 2>&1 || fail "podman is not installed or not on PATH"
}

require_workspace_root() {
  [[ -n "$OPENCODE_BASE_ROOT" ]] || fail "OPENCODE_BASE_ROOT is empty"
}

sanitize_name() {
  local raw="$1"
  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//'
}

resolve_workspace() {
  local input="${1:?workspace required}"

  if [[ "$input" = /* ]]; then
    WORKSPACE_ROOT="$input"
    WORKSPACE_NAME="$(basename "$WORKSPACE_ROOT")"
  else
    require_workspace_root
    WORKSPACE_NAME="$input"
    WORKSPACE_ROOT="$OPENCODE_BASE_ROOT/$WORKSPACE_NAME"
  fi

  SAFE_WORKSPACE_NAME="$(sanitize_name "$WORKSPACE_NAME")"
  [[ -n "$SAFE_WORKSPACE_NAME" ]] || fail "workspace name resolved to an empty container-safe name"

  CONFIG_DIR="$WORKSPACE_ROOT/configurations"
  DATA_DIR="$WORKSPACE_ROOT/data"
  CONTAINER_NAME="opencode-${SAFE_WORKSPACE_NAME}"
}

ensure_workspace_dirs() {
  mkdir -p "$WORKSPACE_ROOT" "$CONFIG_DIR" "$DATA_DIR"
}

image_exists() {
  podman image exists "$OPENCODE_IMAGE_NAME"
}

container_exists() {
  podman container exists "$CONTAINER_NAME"
}

container_running() {
  podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q '^true$'
}

require_image() {
  image_exists || fail "image not found: $OPENCODE_IMAGE_NAME"
}

require_container() {
  container_exists || fail "container not found: $CONTAINER_NAME"
}

require_running_container() {
  require_container
  container_running || fail "container is not running: $CONTAINER_NAME"
}

print_workspace_summary() {
  echo "==> Workspace root: $WORKSPACE_ROOT"
  echo "==> Config dir:      $CONFIG_DIR"
  echo "==> Data dir:        $DATA_DIR"
  echo "==> Workspace name:  $WORKSPACE_NAME"
  echo "==> Container:       $CONTAINER_NAME"
  echo "==> Image:           $OPENCODE_IMAGE_NAME"
  echo "==> Platform:        $OPENCODE_PLATFORM"
  echo "==> OpenCode ver:    $OPENCODE_VERSION"
}
