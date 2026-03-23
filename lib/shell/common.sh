#!/usr/bin/env bash
set -euo pipefail

OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT:-$HOME/Documents/Ezirius/.applications-data/OpenCode}"
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

require_arm64_host() {
  local machine_arch

  machine_arch="$(uname -m)"
  case "$machine_arch" in
    arm64|aarch64) ;;
    *) fail "unsupported host architecture: $machine_arch (requires ARM64 host)" ;;
  esac
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

normalize_path() {
  local raw="$1"

  while [[ "$raw" != "/" && "$raw" = */ ]]; do
    raw="${raw%/}"
  done

  printf '%s' "$raw"
}

hash_workspace_path() {
  local raw="$1"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$raw" | shasum -a 256 | cut -c1-12
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$raw" | sha256sum | cut -c1-12
  else
    fail "requires shasum or sha256sum to derive a unique container name"
  fi
}

resolve_workspace() {
  local input="${1:?workspace required}"

  input="$(normalize_path "$input")"

  WORKSPACE_INPUT="$input"

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

  if [[ "$input" = /* ]]; then
    CONTAINER_NAME="opencode-${SAFE_WORKSPACE_NAME}-$(hash_workspace_path "$WORKSPACE_ROOT")"
  else
    CONTAINER_NAME="opencode-${SAFE_WORKSPACE_NAME}"
  fi
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
  echo "==> Workspace arg:   $WORKSPACE_INPUT"
  echo "==> Workspace root: $WORKSPACE_ROOT"
  echo "==> Config dir:      $CONFIG_DIR"
  echo "==> Data dir:        $DATA_DIR"
  echo "==> Workspace name:  $WORKSPACE_NAME"
  echo "==> Container:       $CONTAINER_NAME"
  echo "==> Image:           $OPENCODE_IMAGE_NAME"
  echo "==> Platform:        $OPENCODE_PLATFORM"
  echo "==> OpenCode ver:    $OPENCODE_VERSION"
}
