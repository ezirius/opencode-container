#!/usr/bin/env bash
set -euo pipefail

__env_OPENCODE_IMAGE_NAME="${OPENCODE_IMAGE_NAME-}"
__env_OPENCODE_PROJECT_PREFIX="${OPENCODE_PROJECT_PREFIX-}"
__env_OPENCODE_REPO_URL="${OPENCODE_REPO_URL-}"
__env_OPENCODE_GITHUB_API_BASE="${OPENCODE_GITHUB_API_BASE-}"
__env_OPENCODE_NPM_REGISTRY_BASE="${OPENCODE_NPM_REGISTRY_BASE-}"
__env_OPENCODE_UBUNTU_LTS_VERSION="${OPENCODE_UBUNTU_LTS_VERSION-}"
__env_OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT-}"
__env_OPENCODE_DEVELOPMENT_ROOT="${OPENCODE_DEVELOPMENT_ROOT-}"
__env_OPENCODE_CONTAINER_RUNTIME_HOME="${OPENCODE_CONTAINER_RUNTIME_HOME-}"
__env_OPENCODE_CONTAINER_WORKSPACE_DIR="${OPENCODE_CONTAINER_WORKSPACE_DIR-}"
__env_OPENCODE_CONTAINER_DEVELOPMENT_DIR="${OPENCODE_CONTAINER_DEVELOPMENT_DIR-}"
__env_OPENCODE_CONTAINER_RUNTIME_ENV_FILE="${OPENCODE_CONTAINER_RUNTIME_ENV_FILE-}"
__env_OPENCODE_CONTAINER_RUNTIME_STATE_DIR="${OPENCODE_CONTAINER_RUNTIME_STATE_DIR-}"
__env_OPENCODE_VERSION="${OPENCODE_VERSION-}"
__env_OPENCODE_SELECT_INDEX="${OPENCODE_SELECT_INDEX-}"
__env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE="${OPENCODE_WRAPPER_CONTEXT_OVERRIDE-}"
__env_OPENCODE_COMMITSTAMP_OVERRIDE="${OPENCODE_COMMITSTAMP_OVERRIDE-}"
__env_OPENCODE_SOURCE_OVERRIDE_DIR="${OPENCODE_SOURCE_OVERRIDE_DIR-}"
__env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK="${OPENCODE_SKIP_BUILD_CONTEXT_CHECK-}"

if [[ -n "${ROOT:-}" && -f "$ROOT/config/shared/opencode.conf" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/config/shared/opencode.conf"
fi

if [[ -n "${ROOT:-}" && -f "$ROOT/config/shared/tool-versions.conf" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/config/shared/tool-versions.conf"
fi

[[ -z "$__env_OPENCODE_IMAGE_NAME" ]] || OPENCODE_IMAGE_NAME="$__env_OPENCODE_IMAGE_NAME"
[[ -z "$__env_OPENCODE_PROJECT_PREFIX" ]] || OPENCODE_PROJECT_PREFIX="$__env_OPENCODE_PROJECT_PREFIX"
[[ -z "$__env_OPENCODE_REPO_URL" ]] || OPENCODE_REPO_URL="$__env_OPENCODE_REPO_URL"
[[ -z "$__env_OPENCODE_GITHUB_API_BASE" ]] || OPENCODE_GITHUB_API_BASE="$__env_OPENCODE_GITHUB_API_BASE"
[[ -z "$__env_OPENCODE_NPM_REGISTRY_BASE" ]] || OPENCODE_NPM_REGISTRY_BASE="$__env_OPENCODE_NPM_REGISTRY_BASE"
[[ -z "$__env_OPENCODE_UBUNTU_LTS_VERSION" ]] || OPENCODE_UBUNTU_LTS_VERSION="$__env_OPENCODE_UBUNTU_LTS_VERSION"
[[ -z "$__env_OPENCODE_BASE_ROOT" ]] || OPENCODE_BASE_ROOT="$__env_OPENCODE_BASE_ROOT"
[[ -z "$__env_OPENCODE_DEVELOPMENT_ROOT" ]] || OPENCODE_DEVELOPMENT_ROOT="$__env_OPENCODE_DEVELOPMENT_ROOT"
[[ -z "$__env_OPENCODE_CONTAINER_RUNTIME_HOME" ]] || OPENCODE_CONTAINER_RUNTIME_HOME="$__env_OPENCODE_CONTAINER_RUNTIME_HOME"
[[ -z "$__env_OPENCODE_CONTAINER_WORKSPACE_DIR" ]] || OPENCODE_CONTAINER_WORKSPACE_DIR="$__env_OPENCODE_CONTAINER_WORKSPACE_DIR"
[[ -z "$__env_OPENCODE_CONTAINER_DEVELOPMENT_DIR" ]] || OPENCODE_CONTAINER_DEVELOPMENT_DIR="$__env_OPENCODE_CONTAINER_DEVELOPMENT_DIR"
[[ -z "$__env_OPENCODE_CONTAINER_RUNTIME_ENV_FILE" ]] || OPENCODE_CONTAINER_RUNTIME_ENV_FILE="$__env_OPENCODE_CONTAINER_RUNTIME_ENV_FILE"
[[ -z "$__env_OPENCODE_CONTAINER_RUNTIME_STATE_DIR" ]] || OPENCODE_CONTAINER_RUNTIME_STATE_DIR="$__env_OPENCODE_CONTAINER_RUNTIME_STATE_DIR"
[[ -z "$__env_OPENCODE_VERSION" ]] || OPENCODE_VERSION="$__env_OPENCODE_VERSION"
[[ -z "$__env_OPENCODE_SELECT_INDEX" ]] || OPENCODE_SELECT_INDEX="$__env_OPENCODE_SELECT_INDEX"
[[ -z "$__env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE" ]] || OPENCODE_WRAPPER_CONTEXT_OVERRIDE="$__env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE"
[[ -z "$__env_OPENCODE_COMMITSTAMP_OVERRIDE" ]] || OPENCODE_COMMITSTAMP_OVERRIDE="$__env_OPENCODE_COMMITSTAMP_OVERRIDE"
[[ -z "$__env_OPENCODE_SOURCE_OVERRIDE_DIR" ]] || OPENCODE_SOURCE_OVERRIDE_DIR="$__env_OPENCODE_SOURCE_OVERRIDE_DIR"
[[ -z "$__env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK" ]] || OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$__env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK"
unset __env_OPENCODE_IMAGE_NAME __env_OPENCODE_PROJECT_PREFIX __env_OPENCODE_REPO_URL __env_OPENCODE_GITHUB_API_BASE __env_OPENCODE_NPM_REGISTRY_BASE __env_OPENCODE_UBUNTU_LTS_VERSION __env_OPENCODE_BASE_ROOT __env_OPENCODE_DEVELOPMENT_ROOT __env_OPENCODE_CONTAINER_RUNTIME_HOME __env_OPENCODE_CONTAINER_WORKSPACE_DIR __env_OPENCODE_CONTAINER_DEVELOPMENT_DIR __env_OPENCODE_CONTAINER_RUNTIME_ENV_FILE __env_OPENCODE_CONTAINER_RUNTIME_STATE_DIR __env_OPENCODE_VERSION __env_OPENCODE_SELECT_INDEX __env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE __env_OPENCODE_COMMITSTAMP_OVERRIDE __env_OPENCODE_SOURCE_OVERRIDE_DIR __env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK

[[ -n "${OPENCODE_IMAGE_NAME:-}" ]] || fail "missing OPENCODE_IMAGE_NAME in config/shared/opencode.conf"
[[ -n "${OPENCODE_PROJECT_PREFIX:-}" ]] || fail "missing OPENCODE_PROJECT_PREFIX in config/shared/opencode.conf"
[[ -n "${OPENCODE_REPO_URL:-}" ]] || fail "missing OPENCODE_REPO_URL in config/shared/opencode.conf"
[[ -n "${OPENCODE_GITHUB_API_BASE:-}" ]] || fail "missing OPENCODE_GITHUB_API_BASE in config/shared/opencode.conf"
[[ -n "${OPENCODE_NPM_REGISTRY_BASE:-}" ]] || fail "missing OPENCODE_NPM_REGISTRY_BASE in config/shared/opencode.conf"
[[ -n "${OPENCODE_UBUNTU_LTS_VERSION:-}" ]] || fail "missing OPENCODE_UBUNTU_LTS_VERSION in config/shared/opencode.conf"
[[ -n "${OPENCODE_TOOL_BUN_VERSION:-}" ]] || fail "missing OPENCODE_TOOL_BUN_VERSION in config/shared/tool-versions.conf"
[[ -n "${OPENCODE_BASE_ROOT:-}" ]] || fail "missing OPENCODE_BASE_ROOT in config/shared/opencode.conf"
[[ -n "${OPENCODE_DEVELOPMENT_ROOT:-}" ]] || fail "missing OPENCODE_DEVELOPMENT_ROOT in config/shared/opencode.conf"
[[ -n "${OPENCODE_CONTAINER_RUNTIME_HOME:-}" ]] || fail "missing OPENCODE_CONTAINER_RUNTIME_HOME in config/shared/opencode.conf"
[[ -n "${OPENCODE_CONTAINER_WORKSPACE_DIR:-}" ]] || fail "missing OPENCODE_CONTAINER_WORKSPACE_DIR in config/shared/opencode.conf"
[[ -n "${OPENCODE_CONTAINER_DEVELOPMENT_DIR:-}" ]] || fail "missing OPENCODE_CONTAINER_DEVELOPMENT_DIR in config/shared/opencode.conf"
[[ -n "${OPENCODE_CONTAINER_RUNTIME_ENV_FILE:-}" ]] || fail "missing OPENCODE_CONTAINER_RUNTIME_ENV_FILE in config/shared/opencode.conf"
[[ -n "${OPENCODE_CONTAINER_RUNTIME_STATE_DIR:-}" ]] || fail "missing OPENCODE_CONTAINER_RUNTIME_STATE_DIR in config/shared/opencode.conf"
[[ -n "${OPENCODE_VERSION:-}" ]] || fail "missing OPENCODE_VERSION in config/shared/opencode.conf"
OPENCODE_SELECT_INDEX="${OPENCODE_SELECT_INDEX:-}"

OPENCODE_LABEL_NAMESPACE="opencode.wrapper"
OPENCODE_LABEL_WORKSPACE="$OPENCODE_LABEL_NAMESPACE.workspace"
OPENCODE_LABEL_LANE="$OPENCODE_LABEL_NAMESPACE.lane"
OPENCODE_LABEL_UPSTREAM="$OPENCODE_LABEL_NAMESPACE.upstream"
OPENCODE_LABEL_UPSTREAM_REF="$OPENCODE_LABEL_NAMESPACE.upstream_ref"
OPENCODE_LABEL_WRAPPER="$OPENCODE_LABEL_NAMESPACE.context"
OPENCODE_LABEL_COMMITSTAMP="$OPENCODE_LABEL_NAMESPACE.commitstamp"

fail() {
  echo "Error: $*" >&2
  exit 1
}

usage_error() {
  local usage="$*"
  local command_name
  command_name="${usage%% *}"
  echo "Usage: $usage" >&2
  if [[ -n "$command_name" ]]; then
    echo "See \`$command_name --help\` for details." >&2
  fi
  exit 1
}

show_help() {
  printf '%s\n' "$1"
  exit 0
}

contains_line() {
  local haystack="$1"
  local needle="$2"
  [[ -n "$haystack" ]] || return 1
  printf '%s\n' "$haystack" | grep -Fxq -- "$needle"
}

require_podman() {
  command -v podman >/dev/null 2>&1 || fail "podman is not installed or not on PATH"
}

require_python3() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"
}

require_git() {
  command -v git >/dev/null 2>&1 || fail "git is required"
}

require_curl() {
  command -v curl >/dev/null 2>&1 || fail "curl is required"
}

require_mktemp() {
  command -v mktemp >/dev/null 2>&1 || fail "mktemp is required"
}

require_workspace_root() {
  [[ -n "$OPENCODE_BASE_ROOT" ]] || fail "OPENCODE_BASE_ROOT is empty"
}

normalize_path() {
  local raw="$1"
  while [[ "$raw" != "/" && "$raw" == */ ]]; do
    raw="${raw%/}"
  done
  printf '%s' "$raw"
}

expand_home_path() {
  local raw="$1"
  case "$raw" in
    '~') printf '%s' "$HOME" ;;
    '~/'*) printf '%s' "$HOME/${raw#\~/}" ;;
    *) printf '%s' "$raw" ;;
  esac
}

sanitize_name() {
  local raw="$1"
  local sanitized
  sanitized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$sanitized" ]] || fail "failed to derive a safe name from: $raw"
  printf '%s' "$sanitized"
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
      ''|.) ;;
      ..)
        if ((${#normalized[@]} > 0)); then
          unset 'normalized[${#normalized[@]}-1]'
        fi
        ;;
      *) normalized+=("$segment") ;;
    esac
  done

  if ((${#normalized[@]} == 0)); then
    printf '/'
    return 0
  fi

  local joined=""
  local item
  for item in "${normalized[@]}"; do
    joined+="/$item"
  done
  printf '%s' "$joined"
}

require_workspace_name() {
  local name="$1"
  [[ -n "$name" ]] || fail "workspace name must not be empty"
  [[ "$name" != */* ]] || fail "workspace name must not contain path separators"
  [[ "$name" != "." ]] || fail "workspace name must not be '.'"
  [[ "$name" != ".." ]] || fail "workspace name must not be '..'"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "workspace name may only contain letters, numbers, dots, underscores, and hyphens"
}

workspace_base_root() {
  normalize_absolute_path "$(expand_home_path "$OPENCODE_BASE_ROOT")"
}

workspace_root_dir() {
  local workspace="$1"
  printf '%s/%s' "$(workspace_base_root)" "$workspace"
}

workspace_home_dir() {
  local workspace="$1"
  printf '%s/opencode-home' "$(workspace_root_dir "$workspace")"
}

workspace_dir() {
  local workspace="$1"
  printf '%s/opencode-workspace' "$(workspace_root_dir "$workspace")"
}

workspace_config_dir() {
  local workspace="$1"
  printf '%s/.config/opencode' "$(workspace_dir "$workspace")"
}

workspace_config_env_file() {
  local workspace="$1"
  printf '%s/config.env' "$(workspace_config_dir "$workspace")"
}

workspace_secrets_env_file() {
  local workspace="$1"
  printf '%s/secrets.env' "$(workspace_config_dir "$workspace")"
}

env_file_has_assignments() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 1
  grep -Eq '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$env_file"
}

ensure_workspace_layout() {
  local workspace="$1"
  require_workspace_name "$workspace"
  mkdir -p "$(workspace_home_dir "$workspace")" "$(workspace_dir "$workspace")" "$(workspace_config_dir "$workspace")"
}

seed_workspace_config_env_file() {
  local workspace="$1"
  local config_file
  config_file="$(workspace_config_env_file "$workspace")"
  [[ -f "$config_file" ]] && return 0

  mkdir -p "$(dirname "$config_file")"
  cat > "$config_file" <<'EOF'
# Wrapper-managed non-secret environment for the OpenCode container.
#
# Use secrets.env for tokens, keys, passwords, and other secrets.
#
# Non-secret examples:
  # OPENCODE_CONFIG=~/.config/opencode/opencode.json
  # OPENCODE_CONFIG_DIR=.opencode
# OPENCODE_MODEL=anthropic/claude-sonnet-4-5
# OPENCODE_HOST_SERVER_PORT=4096
EOF
}

parse_env_assignment_line() {
  local line="$1"
  line="${line%$'\r'}"
  [[ -n "${line//[[:space:]]/}" ]] || return 1
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1
  line="${line#${line%%[![:space:]]*}}"
  if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+ ]]; then
    line="${line#export}"
    line="${line#${line%%[![:space:]]*}}"
  fi
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || return 1
  printf '%s' "$line"
}

env_file_value() {
  local env_file="$1"
  local wanted_key="$2"
  local line parsed key value matched_value="" found=0

  [[ -f "$env_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    parsed="$(parse_env_assignment_line "$line" 2>/dev/null || true)"
    [[ -n "$parsed" ]] || continue
    key="${parsed%%=*}"
    value="${parsed#*=}"
    if [[ "$key" == "$wanted_key" ]]; then
      matched_value="$value"
      found=1
    fi
  done < "$env_file"

  [[ "$found" == "1" ]] || return 1
  printf '%s' "$matched_value"
}

workspace_env_value() {
  local workspace="$1"
  local wanted_key="$2"
  local value

  if value="$(env_file_value "$(workspace_secrets_env_file "$workspace")" "$wanted_key" 2>/dev/null)"; then
    printf '%s' "$value"
    return 0
  fi

  if value="$(env_file_value "$(workspace_config_env_file "$workspace")" "$wanted_key" 2>/dev/null)"; then
    printf '%s' "$value"
    return 0
  fi

  return 1
}

workspace_server_port() {
  local workspace="$1"
  local value

  value="$(workspace_env_value "$workspace" 'OPENCODE_HOST_SERVER_PORT' 2>/dev/null || true)"
  [[ -n "$value" ]] || return 1
  value="$(normalize_host_port_env_value "$value")"
  [[ -n "$value" ]] || return 1
  validate_host_port "$value" 'OPENCODE_HOST_SERVER_PORT'
  printf '%s' "$value"
}

normalize_host_port_env_value() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"

  if [[ $value =~ ^\"([0-9]+)\"([[:space:]]*#.*)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ $value =~ ^\'([0-9]+)\'([[:space:]]*#.*)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  value="${value%%#*}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

validate_host_port() {
  local value="$1"
  local label="$2"

  [[ -n "$value" ]] || return 0
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$label must be numeric"
  (( value >= 1 && value <= 65535 )) || fail "$label must be between 1 and 65535"
}

container_port_publish_spec() {
  local configured_port="$1"
  local container_port="$2"
  local label="$3"

  validate_host_port "$configured_port" "$label"
  if [[ -n "$configured_port" ]]; then
    printf '127.0.0.1:%s:%s' "$configured_port" "$container_port"
    return 0
  fi

  printf '127.0.0.1::%s' "$container_port"
}

opencode_server_port_publish_spec() {
  local configured_port="$1"
  [[ -n "$configured_port" ]] || return 1
  container_port_publish_spec "$configured_port" 4096 'OPENCODE_HOST_SERVER_PORT'
}

container_workspace_dir() {
  printf '%s' "$OPENCODE_CONTAINER_WORKSPACE_DIR"
}

container_config_dir() {
  printf '%s/.config/opencode' "$(container_workspace_dir)"
}

container_runtime_env_file() {
  printf '%s' "$OPENCODE_CONTAINER_RUNTIME_ENV_FILE"
}

runtime_home_dir() {
  printf '%s' "$OPENCODE_CONTAINER_RUNTIME_HOME"
}

container_development_dir() {
  printf '%s' "$OPENCODE_CONTAINER_DEVELOPMENT_DIR"
}

container_runtime_state_dir() {
  printf '%s' "$OPENCODE_CONTAINER_RUNTIME_STATE_DIR"
}

container_config_env_file() {
  printf '%s/config.env' "$(container_config_dir)"
}

container_secrets_env_file() {
  printf '%s/secrets.env' "$(container_config_dir)"
}

workspace_mount_spec() {
  local workspace="$1"
  printf '%s:%s' "$(workspace_dir "$workspace")" "$(container_workspace_dir)"
}

workspace_home_mount_spec() {
  local workspace="$1"
  local _image_ref="$2"
  printf '%s:%s' "$(workspace_home_dir "$workspace")" "$(runtime_home_dir)"
}

development_mount_spec() {
  printf '%s:%s' "$(normalize_absolute_path "$(expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")")" "$(container_development_dir)"
}

development_root_exists() {
  local development_root
  development_root="$(normalize_absolute_path "$(expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")")"
  [[ -d "$development_root" ]]
}

validate_lane() {
  local lane="$1"
  [[ "$lane" == "production" || "$lane" == "test" ]] || fail "lane must be 'production' or 'test'"
}

validate_upstream_selector() {
  local selector="$1"
  [[ -n "$selector" ]] || fail "upstream selector must not be empty"
  [[ "$selector" == "main" || "$selector" == "latest" || "$selector" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "upstream selector must be 'main', 'latest', or an exact release tag"
}

api_get() {
  local url="$1"
  require_curl
  curl -fsSL "$url"
}

release_tag_display() {
  local tag="$1"
  printf '%s' "${tag#v}"
}

list_release_tags() {
  api_get "$OPENCODE_GITHUB_API_BASE/repos/anomalyco/opencode/releases" | python3 -c 'import json, sys
data = json.load(sys.stdin)
seen = set()
for item in data if isinstance(data, list) else [data]:
    if item.get("draft") or item.get("prerelease"):
        continue
    tag = (item.get("tag_name") or "").strip()
    if not tag:
        continue
    display = tag[1:] if tag.startswith("v") else tag
    if display in seen:
        continue
    seen.add(display)
    print(display)'
}

latest_release_tag() {
  api_get "$OPENCODE_GITHUB_API_BASE/repos/anomalyco/opencode/releases/latest" | python3 -c 'import json, sys
data = json.load(sys.stdin)
tag = (data.get("tag_name") or "").strip()
if not tag:
    raise SystemExit("failed to resolve latest OpenCode release")
print(tag[1:] if tag.startswith("v") else tag)'
}

latest_ubuntu_lts_version() {
  api_get 'https://changelogs.ubuntu.com/meta-release-lts' | python3 -c 'import re, sys
versions = []
for line in sys.stdin:
    match = re.match(r"Version:\s*([0-9]+\.[0-9]+)", line.strip())
    if match:
        versions.append(tuple(int(part) for part in match.group(1).split(".")))
if not versions:
    raise SystemExit("failed to resolve latest Ubuntu LTS version")
latest = sorted(versions)[-1]
print(f"{latest[0]}.{latest[1]:02d}")'
}

notify_if_newer_ubuntu_lts_exists() {
  local latest_lts
  latest_lts="$(latest_ubuntu_lts_version 2>/dev/null || true)"
  [[ -n "$latest_lts" ]] || return 0
  if [[ "$latest_lts" != "$OPENCODE_UBUNTU_LTS_VERSION" ]]; then
    printf 'Notice: newer Ubuntu LTS available (%s); build continues with pinned Ubuntu LTS %s\n' "$latest_lts" "$OPENCODE_UBUNTU_LTS_VERSION"
  fi
}

resolve_upstream_selector() {
  local selector="$1"
  validate_upstream_selector "$selector"
  case "$selector" in
    main) printf 'main' ;;
    latest) latest_release_tag ;;
    v*) printf '%s' "${selector#v}" ;;
    *) printf '%s' "$selector" ;;
  esac
}

upstream_ref_for_selector() {
  local selector="$1"
  local resolved
  resolved="$(resolve_upstream_selector "$selector")"
  if [[ "$resolved" == "main" ]]; then
    printf '%s' 'main'
  else
    printf 'v%s' "$resolved"
  fi
}

select_upstream_selector() {
  local choices=("main")
  local tag
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    choices+=("$tag")
  done < <(list_release_tags)

  local selection
  selection="$(select_menu_option "Select an upstream version" "${choices[@]}")"
  printf '%s' "${choices[$((selection - 1))]}"
}

git_commitstamp() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  if [[ -n "${OPENCODE_COMMITSTAMP_OVERRIDE:-}" ]]; then
    printf '%s' "$OPENCODE_COMMITSTAMP_OVERRIDE"
    return 0
  fi
  require_git
  git -C "$workdir" log -1 --format='%cd-%h' --date=format:'%Y%m%d-%H%M%S'
}

git_is_primary_worktree() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  local git_dir common_dir

  require_git
  git_dir="$(git -C "$workdir" rev-parse --git-dir 2>/dev/null)" || return 1
  common_dir="$(git -C "$workdir" rev-parse --git-common-dir 2>/dev/null)" || return 1

  git_dir="$(normalize_absolute_path "$workdir/$git_dir")"
  common_dir="$(normalize_absolute_path "$workdir/$common_dir")"

  [[ "$git_dir" == "$common_dir" ]]
}

in_linked_worktree() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  ! git_is_primary_worktree "$workdir"
}

git_toplevel() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  git -C "$workdir" rev-parse --show-toplevel 2>/dev/null
}

fallback_repo_root() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  local parent_dir parent_base repo_base candidate

  parent_dir="$(dirname "$workdir")"
  parent_base="$(basename "$parent_dir")"
  if [[ "$parent_base" == *-worktrees ]]; then
    repo_base="${parent_base%-worktrees}"
    candidate="$parent_dir/../$repo_base"
    if git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
      normalize_absolute_path "$candidate"
      return 0
    fi
  fi

  return 1
}

current_wrapper_context() {
  if [[ -n "${OPENCODE_WRAPPER_CONTEXT_OVERRIDE:-}" ]]; then
    printf '%s' "$OPENCODE_WRAPPER_CONTEXT_OVERRIDE"
    return 0
  fi

  require_git
  local workdir="${1:-${ROOT:-$(pwd)}}"
  local toplevel base fallback_repo current_branch
  if git_is_primary_worktree "$workdir"; then
    current_branch="$(git_current_branch "$workdir" 2>/dev/null || true)"
    if [[ -z "$current_branch" || "$current_branch" == "main" ]]; then
      printf 'main'
    else
      sanitize_name "$current_branch"
    fi
    return 0
  fi

  toplevel="$(git_toplevel "$workdir" 2>/dev/null || true)"
  if [[ -n "$toplevel" ]]; then
    base="$(basename "$toplevel")"
    printf '%s' "$(sanitize_name "$base")"
    return 0
  fi

  fallback_repo="$(fallback_repo_root "$workdir" 2>/dev/null || true)"
  if [[ -n "$fallback_repo" ]]; then
    base="$(basename "$workdir")"
    printf '%s' "$(sanitize_name "$base")"
    return 0
  fi

  if in_linked_worktree "$workdir"; then
    sanitize_name "$(basename "$(git -C "$workdir" rev-parse --show-toplevel)")"
  else
    printf 'main'
  fi
}

require_clean_worktree() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  require_git
  git -C "$workdir" diff --quiet || fail "working tree has unstaged changes"
  git -C "$workdir" diff --cached --quiet || fail "working tree has staged changes"
  [[ -z "$(git -C "$workdir" ls-files --others --exclude-standard)" ]] || fail "working tree has untracked files"
}

require_no_unpushed_commits() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  require_git
  git -C "$workdir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1 || fail "current branch does not track an upstream branch"
  local counts ahead behind
  counts="$(git -C "$workdir" rev-list --left-right --count '@{upstream}'...HEAD)"
  behind="${counts%%[[:space:]]*}"
  ahead="${counts##*[[:space:]]}"
  [[ "$behind" == "0" ]] || fail "branch is behind its upstream"
  [[ "$ahead" == "0" ]] || fail "branch has unpushed commits"
}

git_current_branch() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  git -C "$workdir" rev-parse --abbrev-ref HEAD 2>/dev/null
}

git_has_tracking_branch() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  git -C "$workdir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1
}

git_is_in_sync_with_upstream() {
  local workdir="${1:-${ROOT:-$(pwd)}}"
  local ahead behind
  git_has_tracking_branch "$workdir" || return 1
  ahead="$(git -C "$workdir" rev-list --count '@{u}'..HEAD 2>/dev/null || printf '1')"
  behind="$(git -C "$workdir" rev-list --count HEAD..'@{u}' 2>/dev/null || printf '1')"
  [[ "$ahead" == "0" && "$behind" == "0" ]]
}

validate_build_context() {
  local lane="$1"
  local workdir="${2:-${ROOT:-$(pwd)}}"
  validate_lane "$lane"
  [[ "${OPENCODE_SKIP_BUILD_CONTEXT_CHECK:-}" == "1" ]] && return 0
  require_clean_worktree "$workdir"
  if [[ "$lane" == "production" ]]; then
    git_is_primary_worktree "$workdir" || fail "production builds must run from the canonical main checkout"
    [[ "$(git_current_branch "$workdir")" == "main" ]] || fail "production builds must run from branch 'main'"
    git_has_tracking_branch "$workdir" || fail "production builds require a tracking branch"
    git_is_in_sync_with_upstream "$workdir" || fail "production builds require the canonical main checkout to be in sync with its upstream"
  fi
}

image_ref() {
  local lane="$1"
  local upstream="$2"
  local wrapper="$3"
  local commitstamp="$4"
  printf '%s:%s-%s-%s-%s' "$OPENCODE_IMAGE_NAME" "$lane" "$upstream" "$wrapper" "$commitstamp"
}

container_name() {
  local workspace="$1"
  local lane="$2"
  local upstream="$3"
  local wrapper="$4"
  printf '%s-%s-%s-%s-%s' "$OPENCODE_PROJECT_PREFIX" "$workspace" "$lane" "$upstream" "$wrapper"
}

normalize_image_ref() {
  local ref="$1"
  ref="${ref%%@*}"
  case "$ref" in
    localhost/*) printf '%s' "${ref#localhost/}" ;;
    *) printf '%s' "$ref" ;;
  esac
}

image_exists() {
  local image="$1"
  podman image exists "$image"
}

image_label() {
  local image="$1"
  local label_key="$2"
  local value normalized
  normalized="$(normalize_image_ref "$image")"
  value="$(podman image inspect -f "{{ index .Labels \"$label_key\" }}" "$image" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "<no value>" ]]; then
    value="$(podman image inspect -f "{{ index .Labels \"$label_key\" }}" "$normalized" 2>/dev/null || true)"
  fi
  if [[ -z "$value" || "$value" == "<no value>" ]]; then
    value="$(podman image inspect -f "{{ index .Labels \"$label_key\" }}" "localhost/$normalized" 2>/dev/null || true)"
  fi
  [[ "$value" == "<no value>" ]] && value=""
  printf '%s' "$value"
}

container_exists() {
  local name="$1"
  podman container exists "$name"
}

container_running() {
  local name="$1"
  [[ "$(podman inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" == "true" ]]
}

container_label() {
  local name="$1"
  local label_key="$2"
  local value
  value="$(podman inspect -f "{{ index .Config.Labels \"$label_key\" }}" "$name" 2>/dev/null || true)"
  [[ "$value" == "<no value>" ]] && value=""
  printf '%s' "$value"
}

container_image_ref() {
  local name="$1"
  normalize_image_ref "$(podman inspect -f '{{.ImageName}}' "$name" 2>/dev/null || true)"
}

container_mount_source_for_destination() {
  local name="$1" destination="$2"
  podman inspect -f '{{range .Mounts}}{{printf "%s\t%s\n" .Destination .Source}}{{end}}' "$name" 2>/dev/null | while IFS=$'\t' read -r row_destination row_source; do
    [[ "$row_destination" == "$destination" ]] || continue
    printf '%s' "$row_source"
    return 0
  done
}

container_mounts_match_workspace_config() {
  local container_name="$1" workspace="$2" image_ref="$3"
  local expected_home expected_workspace expected_development actual_home actual_workspace actual_development

  expected_home="$(workspace_home_dir "$workspace")"
  expected_workspace="$(workspace_dir "$workspace")"
  expected_development=""
  if development_root_exists; then
    expected_development="$(normalize_absolute_path "$(expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")")"
  fi

  actual_home="$(container_mount_source_for_destination "$container_name" "$(runtime_home_dir)" 2>/dev/null || true)"
  actual_workspace="$(container_mount_source_for_destination "$container_name" "$(container_workspace_dir)" 2>/dev/null || true)"
  actual_development="$(container_mount_source_for_destination "$container_name" "$(container_development_dir)" 2>/dev/null || true)"

  [[ "$actual_home" == "$expected_home" && "$actual_workspace" == "$expected_workspace" && "$actual_development" == "$expected_development" ]]
}

project_image_refs() {
  local seen_refs=""
  local ref normalized
  podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | while IFS= read -r ref; do
    [[ "$ref" == "$OPENCODE_IMAGE_NAME:"* || "$ref" == "localhost/$OPENCODE_IMAGE_NAME:"* ]] || continue
    normalized="$(normalize_image_ref "$ref")"
    contains_line "$seen_refs" "$normalized" && continue
    if [[ -z "$seen_refs" ]]; then
      seen_refs="$normalized"
    else
      seen_refs+=$'\n'"$normalized"
    fi
    printf '%s\n' "$normalized"
  done
}

project_image_rows() {
  local ref lane upstream wrapper commitstamp
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    lane="$(image_label "$ref" "$OPENCODE_LABEL_LANE")"
    upstream="$(image_label "$ref" "$OPENCODE_LABEL_UPSTREAM")"
    wrapper="$(image_label "$ref" "$OPENCODE_LABEL_WRAPPER")"
    commitstamp="$(image_label "$ref" "$OPENCODE_LABEL_COMMITSTAMP")"
    [[ -n "$lane" && -n "$upstream" && -n "$wrapper" && -n "$commitstamp" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$ref" "$lane" "$upstream" "$wrapper" "$commitstamp"
  done < <(project_image_refs)
}

sorted_project_image_rows() {
  project_image_rows | sort -t $'\t' -k2,2 -k5,5r
}

project_container_names() {
  podman ps -a --format '{{.Names}}' 2>/dev/null | while IFS= read -r name; do
    [[ "$name" == "$OPENCODE_PROJECT_PREFIX-"* ]] || continue
    printf '%s\n' "$name"
  done
}

project_container_rows() {
  local name workspace lane upstream wrapper commitstamp status image_ref
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    workspace="$(container_label "$name" "$OPENCODE_LABEL_WORKSPACE")"
    lane="$(container_label "$name" "$OPENCODE_LABEL_LANE")"
    upstream="$(container_label "$name" "$OPENCODE_LABEL_UPSTREAM")"
    wrapper="$(container_label "$name" "$OPENCODE_LABEL_WRAPPER")"
    commitstamp="$(container_label "$name" "$OPENCODE_LABEL_COMMITSTAMP")"
    image_ref="$(container_image_ref "$name")"
    [[ -n "$workspace" && -n "$lane" && -n "$upstream" && -n "$wrapper" && -n "$commitstamp" ]] || continue
    status="stopped"
    container_running "$name" && status="running"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status" "$image_ref"
  done < <(project_container_names)
}

sorted_project_container_rows() {
  project_container_rows | sort -t $'\t' -k3,3 -k6,6r
}

workspace_container_rows() {
  local workspace="$1"
  sorted_project_container_rows | while IFS=$'\t' read -r name row_workspace lane upstream wrapper commitstamp status image_ref; do
    [[ "$row_workspace" == "$workspace" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$row_workspace" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status" "$image_ref"
  done
}

newest_matching_image_ref() {
  local lane="$1"
  local upstream="$2"
  local wrapper="$3"
  local ref row_lane row_upstream row_wrapper commitstamp
  while IFS=$'\t' read -r ref row_lane row_upstream row_wrapper commitstamp; do
    [[ -n "$ref" ]] || continue
    [[ "$row_lane" == "$lane" && "$row_upstream" == "$upstream" && "$row_wrapper" == "$wrapper" ]] || continue
    printf '%s' "$ref"
    return 0
  done < <(sorted_project_image_rows)
  return 1
}

picker_display_row_from_target() {
  local lane="$1" upstream="$2" wrapper="$3" commitstamp="$4" status="$5"
  printf '%s\t%s\t%s\t%s\t%s' "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
}

format_picker_table() {
  local rows=("$@")
  local row lane upstream wrapper commitstamp status
  local lane_w=4 upstream_w=8 wrapper_w=7 commit_w=6 status_w=6
  local formatted=()

  for row in "${rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r lane upstream wrapper commitstamp status <<< "$row"
    (( ${#lane} > lane_w )) && lane_w=${#lane}
    (( ${#upstream} > upstream_w )) && upstream_w=${#upstream}
    (( ${#wrapper} > wrapper_w )) && wrapper_w=${#wrapper}
    (( ${#commitstamp} > commit_w )) && commit_w=${#commitstamp}
    (( ${#status} > status_w )) && status_w=${#status}
  done

  printf -v row "%-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "lane" "upstream" "wrapper" "commit" "status"
  formatted+=("$row")
  printf -v row "%-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$(printf '%*s' "$lane_w" '' | tr ' ' '-')" "$(printf '%*s' "$upstream_w" '' | tr ' ' '-')" "$(printf '%*s' "$wrapper_w" '' | tr ' ' '-')" "$(printf '%*s' "$commit_w" '' | tr ' ' '-')" "$(printf '%*s' "$status_w" '' | tr ' ' '-')"
  formatted+=("$row")

  for row in "${rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r lane upstream wrapper commitstamp status <<< "$row"
    printf -v row "%-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
    formatted+=("$row")
  done

  printf '%s\n' "${formatted[@]}"
}

select_menu_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local index=1 choice index_width option_count

  [[ ${#options[@]} -gt 0 ]] || fail "no options available"
  if [[ -n "$OPENCODE_SELECT_INDEX" ]]; then
    choice="$OPENCODE_SELECT_INDEX"
    [[ "$choice" =~ ^[0-9]+$ ]] || fail "OPENCODE_SELECT_INDEX must be numeric"
    (( choice >= 1 && choice <= ${#options[@]} )) || fail "OPENCODE_SELECT_INDEX is out of range"
    printf '%s' "$choice"
    return 0
  fi

  printf '%s\n' "$prompt" >&2
  option_count="${#options[@]}"
  index_width="${#option_count}"

  for choice in "${options[@]}"; do
    printf '%*d. %s\n' "$index_width" "$index" "$choice" >&2
    index=$((index + 1))
  done

  while true; do
    printf 'Select an option [1-%d]: ' "${#options[@]}" >&2
    IFS= read -r choice || fail "selection aborted"
    [[ "$choice" =~ ^[0-9]+$ ]] || continue
    if (( choice >= 1 && choice <= ${#options[@]} )); then
      printf '%s' "$choice"
      return 0
    fi
  done
}

workspace_target_rows() {
  local workspace="$1"
  local row name row_workspace lane upstream wrapper commitstamp status image_ref
  local container_image_refs=""
  local ref

  while IFS=$'\t' read -r name row_workspace lane upstream wrapper commitstamp status image_ref; do
    [[ -n "$name" ]] || continue
    printf 'container\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status" "$image_ref"
    if [[ -n "$container_image_refs" ]]; then
      container_image_refs+=$'\n'
    fi
    container_image_refs+="$image_ref"
  done < <(workspace_container_rows "$workspace")

  while IFS=$'\t' read -r ref lane upstream wrapper commitstamp; do
    [[ -n "$ref" ]] || continue
    contains_line "$container_image_refs" "$ref" && continue
    printf 'image\t%s\t%s\t%s\t%s\t%s\timage only\t%s\n' "$ref" "$lane" "$upstream" "$wrapper" "$commitstamp" "$ref"
  done < <(sorted_project_image_rows)
}

container_picker_display_rows() {
  local rows="$1"
  local row
  while IFS=$'\t' read -r name _workspace lane upstream wrapper commitstamp status _image_ref; do
    [[ -n "$name" ]] || continue
    row="$(picker_display_row_from_target "$lane" "$upstream" "$wrapper" "$commitstamp" "$status")"
    printf '%s\n' "$row"
  done <<< "$rows"
}

resolve_row_from_picker() {
  local prompt="$1"
  local rows="$2"
  local selection selection_line display_count=0 formatted_count=0
  local display_rows=() formatted_options=() header_line="" divider_line=""

  [[ -n "$rows" ]] || fail "no options available"

  while IFS= read -r selection_line; do
    [[ -n "$selection_line" ]] || continue
    display_rows+=("$selection_line")
    display_count=$((display_count + 1))
  done < <(container_picker_display_rows "$rows")

  [[ "$display_count" -gt 0 ]] || fail "no container picker rows available"

  set +u
  while IFS= read -r selection_line; do
    [[ -n "$selection_line" ]] || continue
    formatted_options+=("$selection_line")
    formatted_count=$((formatted_count + 1))
    if [[ "$formatted_count" -eq 1 ]]; then
      header_line="$selection_line"
    elif [[ "$formatted_count" -eq 2 ]]; then
      divider_line="$selection_line"
    fi
  done < <(format_picker_table "${display_rows[@]}")
  set -u

  [[ "$formatted_count" -ge 3 ]] || fail "failed to format container picker options"

  prompt+=$'\n'"$header_line"
  prompt+=$'\n'"$divider_line"
  set +u
  selection="$(select_menu_option "$prompt" "${formatted_options[@]:2}")"
  set -u
  selection_line="$(printf '%s\n' "$rows" | sed -n "${selection}p")"
  [[ -n "$selection_line" ]] || fail "failed to resolve selected container target"
  printf '%s' "$selection_line"
}

resolve_target_details_for_workspace() {
  local workspace="$1"
  local rows selection selection_line display_count=0 formatted_count=0
  local display_rows=() formatted_options=() header_line="" divider_line="" prompt kind ref lane upstream wrapper commitstamp status image_ref

  rows="$(workspace_target_rows "$workspace")"
  [[ -n "$rows" ]] || fail "no OpenCode targets found for workspace '$workspace'"

  while IFS=$'\t' read -r kind ref lane upstream wrapper commitstamp status image_ref; do
    [[ -n "$kind" ]] || continue
    display_rows+=("$(picker_display_row_from_target "$lane" "$upstream" "$wrapper" "$commitstamp" "$status")")
  done <<< "$rows"

  if [[ $(printf '%s\n' "$rows" | sed '/^$/d' | wc -l | tr -d ' ') == "1" ]]; then
    printf '%s' "$rows"
    return 0
  fi

  set +u
  while IFS= read -r selection_line; do
    [[ -n "$selection_line" ]] || continue
    formatted_options+=("$selection_line")
    formatted_count=$((formatted_count + 1))
    if [[ "$formatted_count" -eq 1 ]]; then
      header_line="$selection_line"
    elif [[ "$formatted_count" -eq 2 ]]; then
      divider_line="$selection_line"
    fi
  done < <(format_picker_table "${display_rows[@]}")
  set -u

  prompt="Select a target for workspace '$workspace'"
  prompt+=$'\n'"$header_line"
  prompt+=$'\n'"$divider_line"
  set +u
  selection="$(select_menu_option "$prompt" "${formatted_options[@]:2}")"
  set -u
  selection_line="$(printf '%s\n' "$rows" | sed -n "${selection}p")"
  [[ -n "$selection_line" ]] || fail "failed to resolve selected workspace target"
  printf '%s' "$selection_line"
}

resolve_existing_explicit_container() {
  local workspace="$1" lane="$2" upstream_selector="$3"
  local rows row name row_workspace row_lane row_upstream row_wrapper commitstamp status image_ref resolved_upstream
  validate_lane "$lane"
  resolved_upstream="$(resolve_upstream_selector "$upstream_selector")"

  rows="$(project_container_rows | while IFS=$'\t' read -r name row_workspace row_lane row_upstream row_wrapper commitstamp status image_ref; do
    [[ -n "$name" ]] || continue
    [[ "$row_workspace" == "$workspace" && "$row_lane" == "$lane" && "$row_upstream" == "$resolved_upstream" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$row_workspace" "$row_lane" "$row_upstream" "$row_wrapper" "$commitstamp" "$status" "$image_ref"
  done)"
  [[ -n "$rows" ]] || fail "no matching container exists for workspace=$workspace lane=$lane upstream=$resolved_upstream"

  if [[ $(printf '%s\n' "$rows" | sed '/^$/d' | wc -l | tr -d ' ') != "1" ]]; then
    row="$(resolve_row_from_picker "Select a container for workspace '$workspace'" "$rows")"
  else
    row="$rows"
  fi

  IFS=$'\t' read -r name _row_workspace _row_lane _row_upstream _row_wrapper _commitstamp _status _image_ref <<< "$row"
  printf '%s' "$name"
}

resolve_container_for_workspace() {
  local workspace="$1" rows row name
  rows="$(workspace_container_rows "$workspace")"
  [[ -n "$rows" ]] || fail "no existing container found for workspace '$workspace'"
  row="$(resolve_row_from_picker "Select a container for workspace '$workspace'" "$rows")"
  IFS=$'\t' read -r name _workspace _lane _upstream _wrapper _commitstamp _status _image_ref <<< "$row"
  printf '%s' "$name"
}

print_container_summary() {
  local workspace="$1" container_name="$2" status image
  local server_url development_mount
  status="stopped"
  container_running "$container_name" && status="running"
  if [[ "$status" == "running" ]]; then
    ensure_managed_server_for_container "$container_name"
  fi
  image="$(container_image_ref "$container_name")"
  server_url="$(server_url_for_container "$container_name" 2>/dev/null || true)"
  printf 'Container: %s\n' "$container_name"
  printf 'Workspace: %s\n' "$workspace"
  printf 'Workspace Dir: %s\n' "$(container_workspace_dir)"
  printf 'Status: %s\n' "$status"
  [[ -n "$image" ]] && printf 'Image: %s\n' "$image"
  [[ -n "$server_url" ]] && printf 'Server: %s\n' "$server_url"
  [[ -n "$(container_label "$container_name" "$OPENCODE_LABEL_LANE")" ]] && printf 'Lane: %s\n' "$(container_label "$container_name" "$OPENCODE_LABEL_LANE")"
  [[ -n "$(container_label "$container_name" "$OPENCODE_LABEL_UPSTREAM")" ]] && printf 'Upstream: %s\n' "$(container_label "$container_name" "$OPENCODE_LABEL_UPSTREAM")"
  [[ -n "$(container_label "$container_name" "$OPENCODE_LABEL_WRAPPER")" ]] && printf 'Wrapper: %s\n' "$(container_label "$container_name" "$OPENCODE_LABEL_WRAPPER")"
  [[ -n "$(container_label "$container_name" "$OPENCODE_LABEL_COMMITSTAMP")" ]] && printf 'Commit Stamp: %s\n' "$(container_label "$container_name" "$OPENCODE_LABEL_COMMITSTAMP")"
  printf 'Home Mount: %s\n' "$(workspace_home_dir "$workspace")"
  printf 'Workspace Mount: %s\n' "$(workspace_dir "$workspace")"
  development_mount='(not mounted)'
  if development_root_exists; then
    development_mount="$(normalize_absolute_path "$(expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")")"
  fi
  printf 'Development Mount: %s\n' "$development_mount"
}

create_or_replace_container() {
  local container_name="$1" image_ref="$2" workspace="$3" lane="$4" upstream="$5" wrapper="$6" commitstamp="$7"
  local server_port server_publish_spec
  local -a run_args

  server_port="$(workspace_server_port "$workspace" 2>/dev/null || true)"
  server_publish_spec="$(opencode_server_port_publish_spec "$server_port" 2>/dev/null || true)"

  if container_exists "$container_name"; then
    podman rm -f "$container_name" >/dev/null
  fi

  run_args=(
    run -d
    --name "$container_name"
    --restart unless-stopped
    -e "HOME=$(runtime_home_dir)"
    -e "OPENCODE_CONTAINER_RUNTIME_HOME=$(runtime_home_dir)"
    -e "OPENCODE_CONTAINER_WORKSPACE_DIR=$(container_workspace_dir)"
    -e "OPENCODE_CONTAINER_DEVELOPMENT_DIR=$(container_development_dir)"
    -e "OPENCODE_CONTAINER_RUNTIME_ENV_FILE=$(container_runtime_env_file)"
    -e "OPENCODE_CONTAINER_RUNTIME_STATE_DIR=$(container_runtime_state_dir)"
    -e "OPENCODE_WRAPPER_RUNTIME_ENV_FILE=$(container_runtime_env_file)"
    -e "OPENCODE_WRAPPER_CONFIG_ENV_FILE=$(container_config_env_file)"
    -e "OPENCODE_WRAPPER_SECRETS_ENV_FILE=$(container_secrets_env_file)"
    --label "$OPENCODE_LABEL_WORKSPACE=$workspace"
    --label "$OPENCODE_LABEL_LANE=$lane"
    --label "$OPENCODE_LABEL_UPSTREAM=$upstream"
    --label "$OPENCODE_LABEL_WRAPPER=$wrapper"
    --label "$OPENCODE_LABEL_COMMITSTAMP=$commitstamp"
  )
  if [[ -n "$server_publish_spec" ]]; then
    run_args+=( -p "$server_publish_spec" )
  fi
  if development_root_exists; then
    run_args+=( -v "$(development_mount_spec)" )
  fi
  run_args+=(
    -v "$(workspace_home_mount_spec "$workspace" "$image_ref")"
    -v "$(workspace_mount_spec "$workspace")"
    "$image_ref"
  )

  podman "${run_args[@]}" >/dev/null
}

host_port_for_container_port() {
  local container_name="$1"
  local container_port="$2"
  local mapped
  mapped="$(podman port "$container_name" "$container_port/tcp" 2>/dev/null | tr -d '\r' | sed -n '1p')" || return 1
  [[ -n "$mapped" ]] || return 1
  printf '%s' "${mapped##*:}"
}

container_server_port_matches_workspace_config() {
  local container_name="$1"
  local workspace="$2"
  local desired_port actual_port

  desired_port="$(workspace_server_port "$workspace" 2>/dev/null || true)"
  actual_port="$(host_port_for_container_port "$container_name" 4096 2>/dev/null || true)"

  if [[ -z "$desired_port" ]]; then
    [[ -z "$actual_port" ]]
    return
  fi

  [[ "$desired_port" == "$actual_port" ]]
}

container_matches_workspace_runtime_config() {
  local container_name="$1"
  local workspace="$2"
  local image_ref="$3"
  container_server_port_matches_workspace_config "$container_name" "$workspace" &&
    container_mounts_match_workspace_config "$container_name" "$workspace" "$image_ref"
}

ensure_running_container_matches_image_and_runtime() {
  local container_name="$1" image_ref="$2" workspace="$3" lane="$4" upstream="$5" wrapper="$6" commitstamp="$7"
  local current_image_ref

  if container_exists "$container_name"; then
    current_image_ref="$(container_image_ref "$container_name" 2>/dev/null || true)"
    if [[ "$current_image_ref" != "$(normalize_image_ref "$image_ref")" ]]; then
      create_or_replace_container "$container_name" "$image_ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
    elif ! container_matches_workspace_runtime_config "$container_name" "$workspace" "$image_ref"; then
      create_or_replace_container "$container_name" "$image_ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
    elif ! container_running "$container_name"; then
      podman start "$container_name" >/dev/null
    fi
  else
    create_or_replace_container "$container_name" "$image_ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
  fi

  ensure_managed_server_for_container "$container_name"
}

server_url_for_container() {
  local container_name="$1"
  local workspace port
  workspace="$(container_label "$container_name" "$OPENCODE_LABEL_WORKSPACE")"
  [[ -n "$workspace" ]] || return 1
  workspace_server_port "$workspace" >/dev/null 2>&1 || return 1
  server_active_for_container "$container_name" || return 1
  port="$(host_port_for_container_port "$container_name" 4096 2>/dev/null || true)"
  [[ -n "$port" ]] || return 1
  printf 'http://127.0.0.1:%s' "$port"
}

server_healthcheck_path() {
  printf '%s' '/global/health'
}

server_healthcheck_url() {
  local container_name="$1"
  local base_url
  base_url="$(server_url_for_container_base "$container_name" 2>/dev/null || true)"
  [[ -n "$base_url" ]] || return 1
  printf '%s%s' "$base_url" "$(server_healthcheck_path)"
}

server_url_for_container_base() {
  local container_name="$1"
  local port
  port="$(host_port_for_container_port "$container_name" 4096 2>/dev/null || true)"
  [[ -n "$port" ]] || return 1
  printf 'http://127.0.0.1:%s' "$port"
}

start_managed_server_in_container() {
  local container_name="$1"
  local runtime_env_file workspace_dir runtime_state_dir
  runtime_env_file="$(container_runtime_env_file)"
  workspace_dir="$(container_workspace_dir)"
  runtime_state_dir="$(container_runtime_state_dir)"
  podman exec "$container_name" /bin/sh -lc ". \"$runtime_env_file\" 2>/dev/null || true; cd \"$workspace_dir\"; mkdir -p \"$runtime_state_dir\"; if [ -f \"$runtime_state_dir/server.pid\" ] && kill -0 \"\$(cat \"$runtime_state_dir/server.pid\")\" 2>/dev/null; then exit 0; fi; nohup opencode serve --hostname 0.0.0.0 --port 4096 >\"$runtime_state_dir/server.log\" 2>&1 & echo \$! >\"$runtime_state_dir/server.pid\"" >/dev/null
}

server_active_for_container() {
  local container_name="$1"
  local health_url
  require_curl
  health_url="$(server_healthcheck_url "$container_name" 2>/dev/null || true)"
  [[ -n "$health_url" ]] || return 1
  curl -fsSL "$health_url" >/dev/null 2>&1
}

wait_for_server_for_container() {
  local container_name="$1"
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if server_active_for_container "$container_name"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

ensure_managed_server_for_container() {
  local container_name="$1"
  local workspace server_port
  workspace="$(container_label "$container_name" "$OPENCODE_LABEL_WORKSPACE")"
  [[ -n "$workspace" ]] || return 0
  server_port="$(workspace_server_port "$workspace" 2>/dev/null || true)"
  [[ -n "$server_port" ]] || return 0
  container_running "$container_name" || return 0
  if ! server_active_for_container "$container_name"; then
    start_managed_server_in_container "$container_name"
    wait_for_server_for_container "$container_name" || fail "managed server failed to start for container: $container_name"
  fi
}

start_or_reuse_target() {
  local workspace="$1" kind="$2" ref="$3" lane="$4" upstream="$5" wrapper="$6" commitstamp="$7"
  local resolved_container_name
  local existing_image_ref

  if [[ "$kind" == "container" ]]; then
    existing_image_ref="$(container_image_ref "$ref")"
    [[ -n "$existing_image_ref" ]] || fail "failed to resolve backing image for container: $ref"
    ensure_running_container_matches_image_and_runtime "$ref" "$existing_image_ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
    printf '%s' "$ref"
    return 0
  fi

  resolved_container_name="$(container_name "$workspace" "$lane" "$upstream" "$wrapper")"
  ensure_running_container_matches_image_and_runtime "$resolved_container_name" "$ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
  printf '%s' "$resolved_container_name"
}

use_exec_tty() {
  [[ -t 0 ]]
}

exec_podman_interactive_command() {
  local subcommand="$1"
  shift
  if use_exec_tty; then
    exec podman "$subcommand" -it "$@"
  else
    exec podman "$subcommand" -i "$@"
  fi
}

exec_opencode_in_container() {
  local container_name="$1"
  local runtime_env_file workspace_dir
  shift
  runtime_env_file="$(container_runtime_env_file)"
  workspace_dir="$(container_workspace_dir)"
  exec_podman_interactive_command exec --workdir "$workspace_dir" "$container_name" /bin/sh -lc ". \"$runtime_env_file\" 2>/dev/null || true; cd \"$workspace_dir\"; exec opencode \"\$@\"" sh "$@"
}

exec_shell_in_container() {
  local container_name="$1"
  local runtime_env_file workspace_dir
  shift
  runtime_env_file="$(container_runtime_env_file)"
  workspace_dir="$(container_workspace_dir)"
  if [[ $# -gt 0 ]]; then
    exec_podman_interactive_command exec --workdir "$workspace_dir" "$container_name" /bin/sh -lc ". \"$runtime_env_file\" 2>/dev/null || true; cd \"$workspace_dir\"; exec \"\$@\"" sh "$@"
  else
    exec_podman_interactive_command exec --workdir "$workspace_dir" "$container_name" /bin/sh -lc ". \"$runtime_env_file\" 2>/dev/null || true; cd \"$workspace_dir\"; exec /bin/sh"
  fi
}

build_release_image() {
  local release_url="$1" release_sha512="$2" target_image="$3" lane="$4" upstream="$5" upstream_ref="$6" wrapper="$7" commitstamp="$8"
  podman build \
    -f "$ROOT/config/containers/Containerfile.wrapper" \
    -t "$target_image" \
    --arch "$(container_runtime_arch)" \
    --build-arg "UBUNTU_VERSION=$OPENCODE_UBUNTU_LTS_VERSION" \
    --build-arg "OPENCODE_CONTAINER_WORKSPACE_DIR=$OPENCODE_CONTAINER_WORKSPACE_DIR" \
    --build-arg "OPENCODE_CONTAINER_RUNTIME_HOME=$OPENCODE_CONTAINER_RUNTIME_HOME" \
    --build-arg "OPENCODE_RELEASE_ARCHIVE_URL=$release_url" \
    --build-arg "OPENCODE_RELEASE_ARCHIVE_SHA512=$release_sha512" \
    --build-arg "OPENCODE_WRAPPER_LANE=$lane" \
    --build-arg "OPENCODE_WRAPPER_UPSTREAM=$upstream" \
    --build-arg "OPENCODE_WRAPPER_UPSTREAM_REF=$upstream_ref" \
    --build-arg "OPENCODE_WRAPPER_CONTEXT=$wrapper" \
    --build-arg "OPENCODE_WRAPPER_COMMITSTAMP=$commitstamp" \
    "$ROOT" >/dev/null
}

release_binary_package_name() {
  local arch
  arch="$(container_runtime_arch)"
  case "$arch" in
    x86_64|amd64) printf '%s' 'opencode-linux-x64' ;;
    aarch64|arm64) printf '%s' 'opencode-linux-arm64' ;;
    *) fail "unsupported architecture for official OpenCode release packages: $arch" ;;
  esac
}

container_runtime_arch() {
  local arch
  if [[ -n "${OPENCODE_CONTAINER_ARCH:-}" ]]; then
    printf '%s' "$OPENCODE_CONTAINER_ARCH"
    return 0
  fi

  arch="$(podman info --format '{{.Host.Arch}}' 2>/dev/null || true)"
  if [[ -n "$arch" ]]; then
    printf '%s' "$arch"
    return 0
  fi

  uname -m
}

package_registry_metadata() {
  local package_name="$1" package_version="$2"
  api_get "$OPENCODE_NPM_REGISTRY_BASE/$package_name/$package_version"
}

package_download_url() {
  local package_name="$1" package_version="$2"
  package_registry_metadata "$package_name" "$package_version" | python3 -c 'import json, sys
data = json.load(sys.stdin)
url = ((data.get("dist") or {}).get("tarball") or "").strip()
if not url:
    raise SystemExit("failed to resolve package tarball url")
print(url)'
}

package_download_sha512_hex() {
  local package_name="$1" package_version="$2"
  package_registry_metadata "$package_name" "$package_version" | python3 -c 'import base64, hashlib, json, sys
data = json.load(sys.stdin)
integrity = ((data.get("dist") or {}).get("integrity") or "").strip()
if not integrity.startswith("sha512-"):
    raise SystemExit("failed to resolve package sha512 integrity")
print(base64.b64decode(integrity.split("-", 1)[1]).hex())'
}

release_binary_package_url() {
  local upstream_version="$1"
  package_download_url "$(release_binary_package_name)" "$upstream_version"
}

release_binary_package_sha512_hex() {
  local upstream_version="$1"
  package_download_sha512_hex "$(release_binary_package_name)" "$upstream_version"
}

clone_upstream_source() {
  local ref="$1"
  local destination="$2"

  require_git
  if [[ "$ref" == "dev" || "$ref" == "main" ]]; then
    git clone --depth 1 --branch main "$OPENCODE_REPO_URL" "$destination" >/dev/null 2>&1 || fail "failed to clone upstream main"
    return 0
  fi

  git clone --depth 1 --branch "$ref" "$OPENCODE_REPO_URL" "$destination" >/dev/null 2>&1 || fail "failed to clone upstream ref '$ref'"
}

build_source_image() {
  local source_ref="$1"
  local target_image="$2"
  local lane="$3"
  local upstream_resolved="$4"
  local wrapper_context="$5"
  local commitstamp="$6"
  local temp_dir
  local source_dir
  local source_dockerfile

  require_mktemp
  require_podman

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN
  source_dir="$temp_dir/source"
  mkdir -p "$temp_dir/config/containers"
  mkdir -p "$temp_dir/config/shared"
  cp "$ROOT/config/containers/entrypoint.sh" "$temp_dir/config/containers/entrypoint.sh"
  cp "$ROOT/config/containers/install-tools.sh" "$temp_dir/config/containers/install-tools.sh"
  cp "$ROOT/config/shared/opencode.conf" "$temp_dir/config/shared/opencode.conf"
  cp "$ROOT/config/shared/tool-versions.conf" "$temp_dir/config/shared/tool-versions.conf"

  if [[ -n "${OPENCODE_SOURCE_OVERRIDE_DIR:-}" ]]; then
    mkdir -p "$source_dir"
    cp -R "$OPENCODE_SOURCE_OVERRIDE_DIR"/. "$source_dir" || fail "failed to copy overridden OpenCode source tree"
  else
    clone_upstream_source "$source_ref" "$source_dir"
  fi

  source_dockerfile="$temp_dir/Containerfile.source-base"
  cat > "$source_dockerfile" <<'EOF'
FROM oven/bun:__OPENCODE_TOOL_BUN_VERSION__ AS build

WORKDIR /src
COPY source/ /src/
RUN bun install
RUN bun run --cwd packages/opencode build --single --skip-embed-web-ui
RUN set -eu; \
    matches="$(find /src/packages/opencode/dist -type f -path '*/bin/opencode')"; \
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"; \
    [ "$count" = "1" ] || { printf 'expected exactly one opencode binary, found %s\n' "$count" >&2; exit 1; }; \
    cp "$matches" /tmp/opencode

FROM ubuntu:__OPENCODE_UBUNTU_LTS_VERSION__

ARG OPENCODE_CONTAINER_WORKSPACE_DIR=__OPENCODE_CONTAINER_WORKSPACE_DIR__
ARG OPENCODE_CONTAINER_RUNTIME_HOME=__OPENCODE_CONTAINER_RUNTIME_HOME__

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

COPY config/shared/tool-versions.conf /tmp/opencode-tool-versions.conf
COPY config/containers/install-tools.sh /tmp/opencode-install-tools.sh

RUN bash /tmp/opencode-install-tools.sh \
  && useradd -m -s /bin/bash opencode \
  && mkdir -p "$OPENCODE_CONTAINER_WORKSPACE_DIR" "$OPENCODE_CONTAINER_RUNTIME_HOME" \
  && chown -R root:root /workspace "$OPENCODE_CONTAINER_RUNTIME_HOME" \
  && rm -f /tmp/opencode-tool-versions.conf /tmp/opencode-install-tools.sh

COPY --from=build /tmp/opencode /usr/local/bin/opencode
COPY config/containers/entrypoint.sh /usr/local/bin/opencode-wrapper-entrypoint
RUN chmod 755 /usr/local/bin/opencode-wrapper-entrypoint

USER root
WORKDIR $OPENCODE_CONTAINER_WORKSPACE_DIR

ENV HOME=$OPENCODE_CONTAINER_RUNTIME_HOME

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/opencode-wrapper-entrypoint"]
CMD ["sleep", "infinity"]
EOF
  sed -i "s/__OPENCODE_UBUNTU_LTS_VERSION__/$OPENCODE_UBUNTU_LTS_VERSION/g" "$source_dockerfile"
  sed -i "s/__OPENCODE_TOOL_BUN_VERSION__/$OPENCODE_TOOL_BUN_VERSION/g" "$source_dockerfile"
  sed -i "s|__OPENCODE_CONTAINER_WORKSPACE_DIR__|$OPENCODE_CONTAINER_WORKSPACE_DIR|g" "$source_dockerfile"
  sed -i "s|__OPENCODE_CONTAINER_RUNTIME_HOME__|$OPENCODE_CONTAINER_RUNTIME_HOME|g" "$source_dockerfile"

  podman build \
    -f "$source_dockerfile" \
    -t "$target_image" \
    --arch "$(container_runtime_arch)" \
    --build-arg "OPENCODE_CONTAINER_WORKSPACE_DIR=$OPENCODE_CONTAINER_WORKSPACE_DIR" \
    --build-arg "OPENCODE_CONTAINER_RUNTIME_HOME=$OPENCODE_CONTAINER_RUNTIME_HOME" \
    --label "$OPENCODE_LABEL_LANE=$lane" \
    --label "$OPENCODE_LABEL_UPSTREAM=$upstream_resolved" \
    --label "$OPENCODE_LABEL_UPSTREAM_REF=$source_ref" \
    --label "$OPENCODE_LABEL_WRAPPER=$wrapper_context" \
    --label "$OPENCODE_LABEL_COMMITSTAMP=$commitstamp" \
    "$temp_dir" >/dev/null
}
