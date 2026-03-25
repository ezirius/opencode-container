#!/usr/bin/env bash
set -euo pipefail

OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT:-$HOME/Documents/Ezirius/.applications-data/OpenCode}"
OPENCODE_IMAGE_NAME="${OPENCODE_IMAGE_NAME:-opencode-arm64}"
UBUNTU_VERSION="${UBUNTU_VERSION:-latest-lts}"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"

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

require_python3() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to resolve latest versions"
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

require_workspace_name() {
  local name="$1"

  [[ "$name" != */* ]] || fail "workspace name must not contain path separators: $name"
  [[ "$name" != "." ]] || fail "workspace name must not be '.'"
  [[ "$name" != ".." ]] || fail "workspace name must not be '..'"
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

expand_home_path() {
  local raw="$1"

  case "$raw" in
    '~')
      printf '%s' "$HOME"
      ;;
    '~/'*)
      printf '%s' "$HOME/${raw#\~/}"
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

normalize_absolute_path() {
  local raw="$1"
  local segment
  local -a parts=()
  local -a normalized=()

  [[ "$raw" = /* ]] || fail "path must be absolute: $raw"

  raw="$(normalize_path "$raw")"
  IFS='/' read -r -a parts <<< "${raw#/}"

  for segment in "${parts[@]}"; do
    case "$segment" in
      ''|.)
        ;;
      ..)
        if ((${#normalized[@]} > 0)); then
          unset 'normalized[${#normalized[@]}-1]'
        fi
        ;;
      *)
        normalized+=("$segment")
        ;;
    esac
  done

  if ((${#normalized[@]} == 0)); then
    printf '/'
  else
    local joined=""
    local item
    for item in "${normalized[@]}"; do
      joined+="/$item"
    done
    printf '%s' "$joined"
  fi
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
    WORKSPACE_ROOT="$(normalize_absolute_path "$input")"
    WORKSPACE_NAME="$(basename "$WORKSPACE_ROOT")"
  else
    local workspace_base_root

    require_workspace_root
    require_workspace_name "$input"
    WORKSPACE_NAME="$input"
    workspace_base_root="$(expand_home_path "$OPENCODE_BASE_ROOT")"
    WORKSPACE_ROOT="$(normalize_absolute_path "$(normalize_path "$workspace_base_root")/$WORKSPACE_NAME")"
  fi

  SAFE_WORKSPACE_NAME="$(sanitize_name "$WORKSPACE_NAME")"
  [[ -n "$SAFE_WORKSPACE_NAME" ]] || fail "workspace name resolved to an empty container-safe name"

  CONFIG_DIR="$WORKSPACE_ROOT/configurations"
  DATA_DIR="$WORKSPACE_ROOT/data"

  CONTAINER_NAME="opencode-${SAFE_WORKSPACE_NAME}-$(hash_workspace_path "$WORKSPACE_ROOT")"
}

ensure_workspace_dirs() {
  mkdir -p "$WORKSPACE_ROOT" "$CONFIG_DIR" "$DATA_DIR"
}

image_exists() {
  podman image exists "$OPENCODE_IMAGE_NAME"
}

image_id() {
  podman image inspect -f '{{.Id}}' "$OPENCODE_IMAGE_NAME" 2>/dev/null
}

image_label() {
  local key="$1"
  local value

  value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "$OPENCODE_IMAGE_NAME" 2>/dev/null || true)"
  if [[ "$value" == "<no value>" ]]; then
    value=""
  fi
  printf '%s' "$value"
}

container_exists() {
  podman container exists "$CONTAINER_NAME"
}

container_image_id() {
  podman inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null
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

use_exec_tty() {
  [[ -t 0 ]]
}

resolve_latest_ubuntu_lts_version() {
  python3 - <<'PY'
from urllib.request import urlopen

url = 'https://changelogs.ubuntu.com/meta-release-lts'
text = urlopen(url, timeout=15).read().decode('utf-8', 'replace')
blocks = [b.strip() for b in text.split('\n\n') if b.strip()]
latest = None
for block in blocks:
    data = {}
    for line in block.splitlines():
        if ': ' in line:
            key, value = line.split(': ', 1)
            data[key] = value
    if data.get('Supported') == '1' and 'Version' in data:
        latest = '.'.join(data['Version'].split()[0].split('.')[:2])
if not latest:
    raise SystemExit('failed to resolve latest Ubuntu LTS version')
print(latest)
PY
}

resolve_latest_opencode_version() {
  python3 - <<'PY'
import json
from urllib.request import urlopen

url = 'https://registry.npmjs.org/opencode-ai/latest'
data = json.load(urlopen(url, timeout=15))
version = data.get('version')
if not version:
    raise SystemExit('failed to resolve latest opencode-ai version')
print(version)
PY
}

resolve_ubuntu_version() {
  if [[ "$UBUNTU_VERSION" == "latest-lts" ]]; then
    resolve_latest_ubuntu_lts_version
  else
    printf '%s\n' "$UBUNTU_VERSION"
  fi
}

resolve_opencode_version() {
  if [[ "$OPENCODE_VERSION" == "latest" ]]; then
    resolve_latest_opencode_version
  else
    printf '%s\n' "$OPENCODE_VERSION"
  fi
}

print_workspace_summary() {
  echo "==> Workspace arg:   $WORKSPACE_INPUT"
  echo "==> Workspace root: $WORKSPACE_ROOT"
  echo "==> Config dir:      $CONFIG_DIR"
  echo "==> Data dir:        $DATA_DIR"
  echo "==> Workspace name:  $WORKSPACE_NAME"
  echo "==> Container:       $CONTAINER_NAME"
  echo "==> Image:           $OPENCODE_IMAGE_NAME"
  echo "==> Platform:        linux/arm64"
  echo "==> Ubuntu ver cfg:  $UBUNTU_VERSION"
  echo "==> OpenCode ver cfg:$OPENCODE_VERSION"
}
