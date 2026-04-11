#!/usr/bin/env bash
set -euo pipefail

__env_OPENCODE_IMAGE_NAME="${OPENCODE_IMAGE_NAME-}"
__env_OPENCODE_PROJECT_PREFIX="${OPENCODE_PROJECT_PREFIX-}"
__env_OPENCODE_REPO_URL="${OPENCODE_REPO_URL-}"
__env_OPENCODE_GHCR_IMAGE="${OPENCODE_GHCR_IMAGE-}"
__env_OPENCODE_GITHUB_API_BASE="${OPENCODE_GITHUB_API_BASE-}"
__env_OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT-}"
__env_OPENCODE_HOST_SERVER_PORT="${OPENCODE_HOST_SERVER_PORT-}"
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

[[ -z "$__env_OPENCODE_IMAGE_NAME" ]] || OPENCODE_IMAGE_NAME="$__env_OPENCODE_IMAGE_NAME"
[[ -z "$__env_OPENCODE_PROJECT_PREFIX" ]] || OPENCODE_PROJECT_PREFIX="$__env_OPENCODE_PROJECT_PREFIX"
[[ -z "$__env_OPENCODE_REPO_URL" ]] || OPENCODE_REPO_URL="$__env_OPENCODE_REPO_URL"
[[ -z "$__env_OPENCODE_GHCR_IMAGE" ]] || OPENCODE_GHCR_IMAGE="$__env_OPENCODE_GHCR_IMAGE"
[[ -z "$__env_OPENCODE_GITHUB_API_BASE" ]] || OPENCODE_GITHUB_API_BASE="$__env_OPENCODE_GITHUB_API_BASE"
[[ -z "$__env_OPENCODE_BASE_ROOT" ]] || OPENCODE_BASE_ROOT="$__env_OPENCODE_BASE_ROOT"
[[ -z "$__env_OPENCODE_HOST_SERVER_PORT" ]] || OPENCODE_HOST_SERVER_PORT="$__env_OPENCODE_HOST_SERVER_PORT"
[[ -z "$__env_OPENCODE_VERSION" ]] || OPENCODE_VERSION="$__env_OPENCODE_VERSION"
[[ -z "$__env_OPENCODE_SELECT_INDEX" ]] || OPENCODE_SELECT_INDEX="$__env_OPENCODE_SELECT_INDEX"
[[ -z "$__env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE" ]] || OPENCODE_WRAPPER_CONTEXT_OVERRIDE="$__env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE"
[[ -z "$__env_OPENCODE_COMMITSTAMP_OVERRIDE" ]] || OPENCODE_COMMITSTAMP_OVERRIDE="$__env_OPENCODE_COMMITSTAMP_OVERRIDE"
[[ -z "$__env_OPENCODE_SOURCE_OVERRIDE_DIR" ]] || OPENCODE_SOURCE_OVERRIDE_DIR="$__env_OPENCODE_SOURCE_OVERRIDE_DIR"
[[ -z "$__env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK" ]] || OPENCODE_SKIP_BUILD_CONTEXT_CHECK="$__env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK"
unset __env_OPENCODE_IMAGE_NAME __env_OPENCODE_PROJECT_PREFIX __env_OPENCODE_REPO_URL __env_OPENCODE_GHCR_IMAGE __env_OPENCODE_GITHUB_API_BASE __env_OPENCODE_BASE_ROOT __env_OPENCODE_VERSION __env_OPENCODE_SELECT_INDEX __env_OPENCODE_WRAPPER_CONTEXT_OVERRIDE __env_OPENCODE_COMMITSTAMP_OVERRIDE __env_OPENCODE_SOURCE_OVERRIDE_DIR __env_OPENCODE_SKIP_BUILD_CONTEXT_CHECK

OPENCODE_IMAGE_NAME="${OPENCODE_IMAGE_NAME:-opencode-local}"
OPENCODE_PROJECT_PREFIX="${OPENCODE_PROJECT_PREFIX:-opencode}"
OPENCODE_REPO_URL="${OPENCODE_REPO_URL:-https://github.com/anomalyco/opencode.git}"
OPENCODE_GHCR_IMAGE="${OPENCODE_GHCR_IMAGE:-ghcr.io/anomalyco/opencode}"
OPENCODE_GITHUB_API_BASE="${OPENCODE_GITHUB_API_BASE:-https://api.github.com}"
OPENCODE_BASE_ROOT="${OPENCODE_BASE_ROOT:-$HOME/Documents/Ezirius/.applications-data/.containers-artificial-intelligence}"
OPENCODE_HOST_SERVER_PORT="${OPENCODE_HOST_SERVER_PORT:-}"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
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
  echo "Usage: $*" >&2
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
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//'
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
# Wrapper-managed environment for the OpenCode container.
#
# Examples:
# OPENCODE_CONFIG=/home/opencode/.config/opencode/opencode.json
# OPENCODE_CONFIG_DIR=/workspace/opencode-workspace/.opencode
# OPENCODE_MODEL=anthropic/claude-sonnet-4-5
# OPENCODE_HOST_SERVER_PORT=4096
EOF
}

load_workspace_server_port_config() {
  local workspace="$1"
  local config_file

  config_file="$(workspace_config_env_file "$workspace")"

  if [[ -f "$config_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$config_file"
    set +a
  fi
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
  container_port_publish_spec "$OPENCODE_HOST_SERVER_PORT" 4096 'OPENCODE_HOST_SERVER_PORT'
}

container_workspace_dir() {
  printf '%s' "/workspace/opencode-workspace"
}

container_config_dir() {
  printf '%s/.config/opencode' "$(container_workspace_dir)"
}

container_runtime_env_file() {
  printf '%s' "/tmp/opencode-wrapper-runtime.env"
}

workspace_mount_spec() {
  local workspace="$1"
  printf '%s:%s' "$(workspace_dir "$workspace")" "$(container_workspace_dir)"
}

workspace_home_mount_spec() {
  local workspace="$1"
  local image_ref="$2"
  printf '%s:%s' "$(workspace_home_dir "$workspace")" "$(image_runtime_home_dir "$image_ref")"
}

development_mount_spec() {
  printf '%s:%s' "$HOME/Documents/Ezirius/Development/OpenCode" "/workspace/opencode-development"
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
    printf '%s' 'dev'
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
  if [[ -n "${OPENCODE_COMMITSTAMP_OVERRIDE:-}" ]]; then
    printf '%s' "$OPENCODE_COMMITSTAMP_OVERRIDE"
    return 0
  fi
  require_git
  git log -1 --format='%cd-%h' --date=format:'%Y%m%d-%H%M%S'
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
  local toplevel base fallback_repo
  toplevel="$(git_toplevel "$workdir" 2>/dev/null || true)"
  if [[ -n "$toplevel" ]]; then
    base="$(basename "$toplevel")"
    if [[ "$base" == "opencode-container" ]] && git_is_primary_worktree "$workdir"; then
      printf 'main'
      return 0
    fi
    printf '%s' "$(sanitize_name "$base")"
    return 0
  fi

  fallback_repo="$(fallback_repo_root "$workdir" 2>/dev/null || true)"
  if [[ -n "$fallback_repo" ]]; then
    base="$(basename "$workdir")"
    if [[ "$base" == "opencode-container" ]]; then
      printf 'main'
    else
      printf '%s' "$(sanitize_name "$base")"
    fi
    return 0
  fi

  if in_linked_worktree "$workdir"; then
    sanitize_name "$(basename "$(git -C "$workdir" rev-parse --show-toplevel)")"
  else
    printf 'main'
  fi
}

require_clean_worktree() {
  require_git
  git diff --quiet || fail "working tree has unstaged changes"
  git diff --cached --quiet || fail "working tree has staged changes"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || fail "working tree has untracked files"
}

require_no_unpushed_commits() {
  require_git
  git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1 || fail "current branch does not track an upstream branch"
  local counts ahead behind
  counts="$(git rev-list --left-right --count '@{upstream}'...HEAD)"
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
  require_clean_worktree
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

image_config_user() {
  local image="$1"
  local normalized value
  normalized="$(normalize_image_ref "$image")"
  value="$(podman image inspect -f '{{.Config.User}}' "$image" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "<no value>" ]]; then
    value="$(podman image inspect -f '{{.Config.User}}' "$normalized" 2>/dev/null || true)"
  fi
  if [[ -z "$value" || "$value" == "<no value>" ]]; then
    value="$(podman image inspect -f '{{.Config.User}}' "localhost/$normalized" 2>/dev/null || true)"
  fi
  [[ "$value" == "<no value>" ]] && value=""
  printf '%s' "$value"
}

image_env_value() {
  local image="$1"
  local key="$2"
  local normalized env_lines line
  normalized="$(normalize_image_ref "$image")"
  env_lines="$(podman image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$image" 2>/dev/null || true)"
  if [[ -z "$env_lines" ]]; then
    env_lines="$(podman image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$normalized" 2>/dev/null || true)"
  fi
  if [[ -z "$env_lines" ]]; then
    env_lines="$(podman image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "localhost/$normalized" 2>/dev/null || true)"
  fi

  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] || continue
    printf '%s' "${line#*=}"
    return 0
  done <<< "$env_lines"

  return 1
}

image_runtime_home_dir() {
  local image="$1"
  local runtime_home runtime_user

  runtime_home="$(image_env_value "$image" HOME 2>/dev/null || true)"
  if [[ -n "$runtime_home" ]]; then
    printf '%s' "$runtime_home"
    return 0
  fi

  runtime_user="$(image_config_user "$image")"
  runtime_user="${runtime_user%%:*}"

  case "$runtime_user" in
    ''|root|0)
      printf '%s' '/root'
      ;;
    *[!A-Za-z0-9._-]*)
      fail "failed to resolve runtime home for image '$image'"
      ;;
    *)
      printf '/home/%s' "$runtime_user"
      ;;
  esac
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
  podman inspect -f '{{.ImageName}}' "$name" 2>/dev/null || true
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
  local index=1 choice

  [[ ${#options[@]} -gt 0 ]] || fail "no options available"
  if [[ -n "$OPENCODE_SELECT_INDEX" ]]; then
    choice="$OPENCODE_SELECT_INDEX"
    [[ "$choice" =~ ^[0-9]+$ ]] || fail "OPENCODE_SELECT_INDEX must be numeric"
    (( choice >= 1 && choice <= ${#options[@]} )) || fail "OPENCODE_SELECT_INDEX is out of range"
    printf '%s' "$choice"
    return 0
  fi

  printf '%s\n' "$prompt" >&2
  for choice in "${options[@]}"; do
    printf '%d. %s\n' "$index" "$choice" >&2
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

resolve_target_details_for_workspace() {
  local workspace="$1"
  local rows selection selection_line
  local display_rows=() formatted_options=() prompt kind ref lane upstream wrapper commitstamp status image_ref

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

  while IFS= read -r selection_line; do
    formatted_options+=("$selection_line")
  done < <(format_picker_table "${display_rows[@]}")

  prompt="Select a target for workspace '$workspace'"
  prompt+=$'\n'"${formatted_options[0]}"
  prompt+=$'\n'"${formatted_options[1]}"
  selection="$(select_menu_option "$prompt" "${formatted_options[@]:2}")"
  selection_line="$(printf '%s\n' "$rows" | sed -n "${selection}p")"
  [[ -n "$selection_line" ]] || fail "failed to resolve selected workspace target"
  printf '%s' "$selection_line"
}

resolve_existing_explicit_container() {
  local workspace="$1" lane="$2" upstream_selector="$3"
  local wrapper resolved_upstream name
  wrapper="$(current_wrapper_context)"
  validate_lane "$lane"
  resolved_upstream="$(resolve_upstream_selector "$upstream_selector")"
  name="$(container_name "$workspace" "$lane" "$resolved_upstream" "$wrapper")"
  container_exists "$name" || fail "no matching container exists: $name"
  printf '%s' "$name"
}

resolve_container_for_workspace() {
  local workspace="$1" target_row kind ref lane upstream wrapper commitstamp status image_ref
  target_row="$(resolve_target_details_for_workspace "$workspace")"
  IFS=$'\t' read -r kind ref lane upstream wrapper commitstamp status image_ref <<< "$target_row"
  [[ "$kind" == "container" ]] || fail "selected target is not an existing container for workspace '$workspace'"
  printf '%s' "$ref"
}

print_container_summary() {
  local workspace="$1" container_name="$2" status image
  local server_url
  status="stopped"
  container_running "$container_name" && status="running"
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
  printf 'Development Mount: %s\n' "$HOME/Documents/Ezirius/Development/OpenCode"
}

create_or_replace_container() {
  local container_name="$1" image_ref="$2" workspace="$3" lane="$4" upstream="$5" wrapper="$6" commitstamp="$7"
  local server_publish_spec
  if container_exists "$container_name"; then
    podman rm -f "$container_name" >/dev/null
  fi

  load_workspace_server_port_config "$workspace"
  server_publish_spec="$(opencode_server_port_publish_spec)"

  podman run -d \
    --name "$container_name" \
    --restart unless-stopped \
    --label "$OPENCODE_LABEL_WORKSPACE=$workspace" \
    --label "$OPENCODE_LABEL_LANE=$lane" \
    --label "$OPENCODE_LABEL_UPSTREAM=$upstream" \
    --label "$OPENCODE_LABEL_WRAPPER=$wrapper" \
    --label "$OPENCODE_LABEL_COMMITSTAMP=$commitstamp" \
    -p "$server_publish_spec" \
    -v "$(workspace_home_mount_spec "$workspace" "$image_ref")" \
    -v "$(workspace_mount_spec "$workspace")" \
    -v "$(development_mount_spec)" \
    "$image_ref" >/dev/null
}

host_port_for_container_port() {
  local container_name="$1"
  local container_port="$2"
  local mapped
  mapped="$(podman port "$container_name" "$container_port/tcp" 2>/dev/null | tr -d '\r' | sed -n '1p')" || return 1
  [[ -n "$mapped" ]] || return 1
  printf '%s' "${mapped##*:}"
}

server_url_for_container() {
  local container_name="$1"
  local port
  port="$(host_port_for_container_port "$container_name" 4096 2>/dev/null || true)"
  [[ -n "$port" ]] || return 1
  printf 'http://127.0.0.1:%s' "$port"
}

start_or_reuse_target() {
  local workspace="$1" kind="$2" ref="$3" lane="$4" upstream="$5" wrapper="$6" commitstamp="$7"
  local resolved_container_name

  if [[ "$kind" == "container" ]]; then
    if ! container_running "$ref"; then
      podman start "$ref" >/dev/null
    fi
    printf '%s' "$ref"
    return 0
  fi

  resolved_container_name="$(container_name "$workspace" "$lane" "$upstream" "$wrapper")"
  if container_exists "$resolved_container_name"; then
    if [[ "$(container_image_ref "$resolved_container_name" 2>/dev/null || true)" != "$ref" ]]; then
      create_or_replace_container "$resolved_container_name" "$ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
    elif ! container_running "$resolved_container_name"; then
      podman start "$resolved_container_name" >/dev/null
    fi
  else
    create_or_replace_container "$resolved_container_name" "$ref" "$workspace" "$lane" "$upstream" "$wrapper" "$commitstamp"
  fi
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
  shift
  exec_podman_interactive_command exec --workdir "$(container_workspace_dir)" "$container_name" /bin/sh -lc '. /tmp/opencode-wrapper-runtime.env 2>/dev/null || true; cd /workspace/opencode-workspace; exec opencode "$@"' sh "$@"
}

exec_shell_in_container() {
  local container_name="$1"
  shift
  if [[ $# -gt 0 ]]; then
    exec_podman_interactive_command exec --workdir "$(container_workspace_dir)" "$container_name" /bin/sh -lc '. /tmp/opencode-wrapper-runtime.env 2>/dev/null || true; cd /workspace/opencode-workspace; exec "$@"' sh "$@"
  else
    exec_podman_interactive_command exec --workdir "$(container_workspace_dir)" "$container_name" /bin/sh -lc '. /tmp/opencode-wrapper-runtime.env 2>/dev/null || true; cd /workspace/opencode-workspace; exec /bin/sh'
  fi
}

upstream_image_candidates() {
  local upstream="$1"
  if [[ "$upstream" == "main" ]]; then
    return 0
  fi
  printf '%s:%s\n' "$OPENCODE_GHCR_IMAGE" "$upstream"
  printf '%s:v%s\n' "$OPENCODE_GHCR_IMAGE" "$upstream"
}

upstream_image_available() {
  local image_ref="$1"
  podman manifest inspect "$image_ref" >/dev/null 2>&1
}

official_image_ref_for_upstream() {
  local upstream_selector="$1"
  local resolved candidate
  resolved="$(resolve_upstream_selector "$upstream_selector")"
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if upstream_image_available "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(upstream_image_candidates "$resolved")
  return 1
}

build_wrapper_image_from_base() {
  local base_image="$1" target_image="$2" lane="$3" upstream="$4" upstream_ref="$5" wrapper="$6" commitstamp="$7"
  podman build \
    -f "$ROOT/config/containers/Containerfile.wrapper" \
    -t "$target_image" \
    --build-arg "BASE_IMAGE=$base_image" \
    --build-arg "OPENCODE_WRAPPER_LANE=$lane" \
    --build-arg "OPENCODE_WRAPPER_UPSTREAM=$upstream" \
    --build-arg "OPENCODE_WRAPPER_UPSTREAM_REF=$upstream_ref" \
    --build-arg "OPENCODE_WRAPPER_CONTEXT=$wrapper" \
    --build-arg "OPENCODE_WRAPPER_COMMITSTAMP=$commitstamp" \
    "$ROOT" >/dev/null
}

clone_upstream_source() {
  local ref="$1"
  local destination="$2"

  require_git
  if [[ "$ref" == "dev" || "$ref" == "main" ]]; then
    git clone --depth 1 --branch dev "$OPENCODE_REPO_URL" "$destination" >/dev/null 2>&1 || fail "failed to clone upstream main"
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
  local base_image
  local source_dockerfile

  require_mktemp
  require_podman

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN
  source_dir="$temp_dir/source"

  if [[ -n "${OPENCODE_SOURCE_OVERRIDE_DIR:-}" ]]; then
    mkdir -p "$source_dir"
    cp -R "$OPENCODE_SOURCE_OVERRIDE_DIR"/. "$source_dir" || fail "failed to copy overridden OpenCode source tree"
  else
    clone_upstream_source "$source_ref" "$source_dir"
  fi

  source_dockerfile="$temp_dir/Containerfile.source-base"
  cat > "$source_dockerfile" <<'EOF'
FROM oven/bun:1 AS build

WORKDIR /src
COPY source/ /src/
RUN bun install
RUN bun run --cwd packages/opencode build --single --skip-embed-web-ui
RUN cp "$(find /src/packages/opencode/dist -path '*/bin/opencode' | head -n 1)" /tmp/opencode

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    fd-find \
    git \
    jq \
    less \
    procps \
    python3 \
    ripgrep \
    tini \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd || true \
  && useradd -m -s /bin/bash opencode \
  && mkdir -p /workspace/opencode-workspace \
  && chown -R opencode:opencode /workspace /home/opencode \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /tmp/opencode /usr/local/bin/opencode

USER opencode
WORKDIR /workspace/opencode-workspace

ENV HOME=/home/opencode

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
EOF

  base_image="opencode-source-base:${lane}-${upstream_resolved}-${wrapper_context}-${commitstamp}"

  podman build \
    -f "$source_dockerfile" \
    -t "$base_image" \
    "$temp_dir" >/dev/null

  build_wrapper_image_from_base "$base_image" "$target_image" "$lane" "$upstream_resolved" "$source_ref" "$wrapper_context" "$commitstamp"
  podman rmi "$base_image" >/dev/null 2>&1 || true
}
