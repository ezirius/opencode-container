#!/usr/bin/env bash

set -euo pipefail

# This file holds the shared shell helpers used by the wrapper scripts.

# This finds the repo root when a script did not pass it in first.
if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

# This loads the saved repo settings so the helpers all read the same values.
# shellcheck disable=SC1090
source "$ROOT/config/agent/shared/opencode-settings-shared.conf"

declare -a OPENCODE_WORKSPACE_NAMES=()
declare -a OPENCODE_WORKSPACE_OFFSETS=()

# This stops the current command with one clear failure message.
fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

# This checks that a workspace name only uses safe characters.
opencode_validate_workspace_name() {
  local name="$1"

  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ || "$name" == '.' || "$name" == '..' ]]; then
    printf "Workspace name %s may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.' or '..'.\n" "$name" >&2
    exit 1
  fi
}

# This checks that a project name is a direct-child directory token.
opencode_require_project_name() {
  local project_name="$1"
  [[ -n "$project_name" ]] || fail "project name must not be empty"
  [[ "$project_name" != */* ]] || fail "project name must not contain path separators"
  [[ "$project_name" != *:* ]] || fail "project name must not contain ':'"
  [[ "$project_name" != '.' ]] || fail "project name must not be '.'"
  [[ "$project_name" != '..' ]] || fail "project name must not be '..'"
}

# This escapes special regex symbols so names are matched safely.
opencode_regex_escape() {
  local value="$1"
  printf '%s\n' "$value" | sed 's/[][(){}.^$*+?|\\]/\\&/g'
}

# This builds the regex used to find OpenCode images with the saved version.
opencode_image_name_regex() {
  local escaped_basename escaped_version
  escaped_basename="$(opencode_regex_escape "$OPENCODE_IMAGE_BASENAME")"
  escaped_version="$(opencode_regex_escape "$OPENCODE_VERSION")"
  printf '^%s-%s-[0-9]{8}-[0-9]{6}-[0-9]{3}$\n' "$escaped_basename" "$escaped_version"
}

# This builds the regex used to find containers for one workspace.
opencode_container_filter_regex() {
  local workspace="$1"
  local escaped_basename escaped_workspace

  escaped_basename="$(opencode_regex_escape "$OPENCODE_IMAGE_BASENAME")"
  escaped_workspace="$(opencode_regex_escape "$workspace")"
  printf '^%s-%s-[0-9]' "$escaped_basename" "$escaped_workspace"
}

# This expands a leading tilde so saved host paths work as expected in config.
opencode_expand_home_path() {
  local raw="$1"
  case "$raw" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "$HOME/${raw#\~/}" ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

# This matches one exact container name and nothing else.
opencode_container_name_regex() {
  local container_name="$1"
  printf '^%s$\n' "$(opencode_regex_escape "$container_name")"
}

# This tells us whether the current stdin is a real interactive terminal.
opencode_use_interactive_tty() {
  [[ -t 0 ]]
}

# This runs interactive Podman commands in a way that still works from pipes.
opencode_exec_podman_interactive_command() {
  local subcommand="$1"
  shift

  if opencode_use_interactive_tty; then
    exec podman "$subcommand" -it "$@"
  fi

  exec podman "$subcommand" -i "$@"
}

# This checks for real git changes while ignoring harmless host junk.
opencode_git_has_meaningful_worktree_changes() {
  local checkout_root="$1"
  local numstat_output summary_output untracked_output additions deletions

  git -C "$checkout_root" update-index -q --refresh >/dev/null 2>&1 || true

  numstat_output="$(git -C "$checkout_root" diff --numstat 2>/dev/null || true)"
  while IFS=$'\t' read -r additions deletions _; do
    [[ -n "$additions" ]] || continue
    if [[ "$additions" != "0" || "$deletions" != "0" ]]; then
      return 0
    fi
  done <<< "$numstat_output"

  summary_output="$(git -C "$checkout_root" diff --summary 2>/dev/null || true)"
  [[ -n "$summary_output" ]] && return 0

  numstat_output="$(git -C "$checkout_root" diff --cached --numstat 2>/dev/null || true)"
  while IFS=$'\t' read -r additions deletions _; do
    [[ -n "$additions" ]] || continue
    if [[ "$additions" != "0" || "$deletions" != "0" ]]; then
      return 0
    fi
  done <<< "$numstat_output"

  summary_output="$(git -C "$checkout_root" diff --cached --summary 2>/dev/null || true)"
  [[ -n "$summary_output" ]] && return 0

  untracked_output="$(git -C "$checkout_root" ls-files --others --exclude-standard 2>/dev/null || true)"
  [[ -n "$untracked_output" ]] && return 0

  return 1
}

# This makes sure we only build from a saved, tidy checkout.
opencode_require_clean_committed_checkout() {
  local checkout_root="${1:-$ROOT}"
  git -C "$checkout_root" rev-parse --verify HEAD >/dev/null 2>&1 || fail 'Build requires the current checkout to have at least one commit.'
  if opencode_git_has_meaningful_worktree_changes "$checkout_root"; then
    fail 'Build requires a clean checkout with all changes committed.'
  fi
}

# This checks whether the current branch has a configured upstream.
opencode_git_has_upstream() {
  local checkout_root="${1:-$ROOT}"
  git -C "$checkout_root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1
}

# This resolves the configured upstream ref for the current branch.
opencode_git_upstream_ref() {
  local checkout_root="${1:-$ROOT}"
  git -C "$checkout_root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
}

# This extracts the remote name from the upstream ref.
opencode_git_upstream_remote() {
  local checkout_root="${1:-$ROOT}"
  local upstream_ref
  upstream_ref="$(opencode_git_upstream_ref "$checkout_root")"
  printf '%s\n' "${upstream_ref%%/*}"
}

# This resolves the remote default branch ref for the upstream remote.
opencode_git_remote_default_ref() {
  local checkout_root="${1:-$ROOT}"
  local remote_name remote_head
  remote_name="$(opencode_git_upstream_remote "$checkout_root")"
  remote_head="$(git -C "$checkout_root" symbolic-ref "refs/remotes/${remote_name}/HEAD" 2>/dev/null || true)"
  [[ -n "$remote_head" ]] || fail "Build could not determine the remote default branch for ${remote_name}."
  printf '%s\n' "${remote_head#refs/remotes/}"
}

# This checks whether the configured upstream is exactly the remote default branch ref.
opencode_git_upstream_is_remote_default_branch() {
  local checkout_root="${1:-$ROOT}"
  local upstream_ref remote_default_ref
  upstream_ref="$(opencode_git_upstream_ref "$checkout_root")"
  remote_default_ref="$(opencode_git_remote_default_ref "$checkout_root")"
  [[ "$upstream_ref" == "$remote_default_ref" ]]
}

# This prints the ahead/behind counts against the configured upstream.
opencode_git_branch_ahead_behind() {
  local checkout_root="${1:-$ROOT}"
  git -C "$checkout_root" rev-list --left-right --count HEAD...@{upstream}
}

# This enforces the build checkout policy for local-only and upstreamed branches.
opencode_require_build_ready_checkout() {
  local checkout_root="${1:-$ROOT}"
  local counts ahead behind

  opencode_require_clean_committed_checkout "$checkout_root"

  if ! opencode_git_has_upstream "$checkout_root"; then
    return 0
  fi

  if ! opencode_git_upstream_is_remote_default_branch "$checkout_root"; then
    return 0
  fi

  counts="$(opencode_git_branch_ahead_behind "$checkout_root")"
  ahead="$(printf '%s\n' "$counts" | awk '{print $1}')"
  behind="$(printf '%s\n' "$counts" | awk '{print $2}')"

  if [[ "$ahead" != '0' || "$behind" != '0' ]]; then
    fail 'Build requires the current branch to be pushed and in sync with its upstream when tracking the remote default branch.'
  fi
}

# This reads the saved workspace list and splits it into names and offsets.
opencode_load_workspaces() {
  local entry name offset
  OPENCODE_WORKSPACE_NAMES=()
  OPENCODE_WORKSPACE_OFFSETS=()

  for entry in $OPENCODE_WORKSPACES; do
    name="${entry%%:*}"
    offset="${entry#*:}"
    [[ -n "$name" && -n "$offset" && "$name" != "$offset" ]] || fail 'Each OPENCODE_WORKSPACES entry must look like name:offset.'
    opencode_validate_workspace_name "$name"
    [[ "$offset" =~ ^[0-9]+$ ]] || fail "Workspace offset for $name must be numeric."
    OPENCODE_WORKSPACE_NAMES+=("$name")
    OPENCODE_WORKSPACE_OFFSETS+=("$offset")
  done

  [[ ${#OPENCODE_WORKSPACE_NAMES[@]} -gt 0 ]] || fail 'Please configure at least one workspace in OPENCODE_WORKSPACES.'
}

# This prints a small menu and returns the workspace the person picked.
opencode_pick_workspace() {
  local selection index
  printf 'Pick a workspace:\n' >&2
  for index in "${!OPENCODE_WORKSPACE_NAMES[@]}"; do
    printf '%d) %s\n' "$((index + 1))" "${OPENCODE_WORKSPACE_NAMES[$index]}" >&2
  done
  printf 'Selection: ' >&2
  read -r selection

  if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#OPENCODE_WORKSPACE_NAMES[@]} )); then
    printf '%s\n' "${OPENCODE_WORKSPACE_NAMES[$((selection - 1))]}"
    return 0
  fi

  for index in "${!OPENCODE_WORKSPACE_NAMES[@]}"; do
    if [[ "$selection" == "${OPENCODE_WORKSPACE_NAMES[$index]}" ]]; then
      printf '%s\n' "$selection"
      return 0
    fi
  done

  fail 'Please pick one of the configured workspaces.'
}

# This looks up the saved port offset for one workspace.
opencode_workspace_offset() {
  local workspace="$1"
  local index
  for index in "${!OPENCODE_WORKSPACE_NAMES[@]}"; do
    if [[ "$workspace" == "${OPENCODE_WORKSPACE_NAMES[$index]}" ]]; then
      printf '%s\n' "${OPENCODE_WORKSPACE_OFFSETS[$index]}"
      return 0
    fi
  done
  fail "Workspace $workspace is not configured."
}

# This derives the stable host port used for the wrapper's long-lived OpenCode server.
opencode_workspace_server_port() {
  local workspace="$1"
  local offset
  offset="$(opencode_workspace_offset "$workspace")"
  printf '%s\n' "$((4096 + offset))"
}

# This lists direct-child project names from the configured development root.
project_names_from_development_root() {
  local candidate project_name
  local -a project_names=()
  local development_root

  development_root="$(opencode_expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")"

  [[ -d "$development_root" ]] || return 0

  shopt -s nullglob
  for candidate in "$development_root"/*; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    project_name="${candidate##*/}"
    [[ -n "$project_name" ]] || continue
    [[ "$project_name" != */* ]] || continue
    [[ "$project_name" != *:* ]] || continue
    [[ "$project_name" != '.' && "$project_name" != '..' ]] || continue
    project_names+=("$project_name")
  done
  shopt -u nullglob

  [[ ${#project_names[@]} -gt 0 ]] || return 0
  printf '%s\n' "${project_names[@]}" | sort
}

# This resolves the full host project path for one direct-child project.
project_root_dir() {
  local project_name="$1"
  opencode_require_project_name "$project_name"
  printf '%s/%s' "$(opencode_expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")" "$project_name"
}

# This prints a small menu and returns the project the person picked.
opencode_pick_project() {
  local project_names selection index
  local -a options=()

  project_names="$(project_names_from_development_root)"
  [[ -n "$project_names" ]] || fail "no projects found under $OPENCODE_DEVELOPMENT_ROOT"
  while IFS= read -r selection; do
    [[ -n "$selection" ]] || continue
    options+=("$selection")
  done <<< "$project_names"

  printf 'Pick a project:\n' >&2
  for index in "${!options[@]}"; do
    printf '%d) %s\n' "$((index + 1))" "${options[$index]}" >&2
  done
  printf 'Selection: ' >&2
  read -r selection

  if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#options[@]} )); then
    printf '%s\n' "${options[$((selection - 1))]}"
    return 0
  fi

  for index in "${!options[@]}"; do
    if [[ "$selection" == "${options[$index]}" ]]; then
      printf '%s\n' "$selection"
      return 0
    fi
  done

  fail 'Please pick one of the discovered projects.'
}

# This checks that the selected project exists as a direct child project.
opencode_resolve_project_name() {
  local project_name="${1-}"
  if [[ -n "$project_name" ]]; then
    opencode_require_project_name "$project_name"
    [[ -d "$(project_root_dir "$project_name")" && ! -L "$(project_root_dir "$project_name")" ]] || fail "project '$project_name' was not found under $OPENCODE_DEVELOPMENT_ROOT"
    printf '%s\n' "$project_name"
    return 0
  fi
  opencode_pick_project
}

# This resolves the host home path for one workspace.
opencode_host_home_dir() {
  local workspace="$1"
  printf '%s/%s/%s\n' "$(opencode_expand_home_path "$OPENCODE_BASE_PATH")" "$workspace" "$OPENCODE_HOST_HOME_DIRNAME"
}

# This resolves the host workspace path for one workspace.
opencode_host_workspace_dir() {
  local workspace="$1"
  printf '%s/%s/%s\n' "$(opencode_expand_home_path "$OPENCODE_BASE_PATH")" "$workspace" "$OPENCODE_HOST_WORKSPACE_DIRNAME"
}

# This formats the fixed project mount for the selected project.
opencode_project_mount_spec() {
  local project_name="$1"
  printf '%s:%s\n' "$(project_root_dir "$project_name")" "$OPENCODE_CONTAINER_PROJECT"
}

# This finds the newest local image that matches the saved OpenCode naming rules.
opencode_latest_image() {
  local image_name normalized image_regex
  image_regex="$(opencode_image_name_regex)"
  while IFS= read -r image_name; do
    [[ -n "$image_name" ]] || continue
    normalized="${image_name#localhost/}"
    if [[ "$normalized" =~ $image_regex ]]; then
      printf '%s\n' "$normalized"
      return 0
    fi
  done < <(podman images --sort created --format '{{.Repository}}' 2>/dev/null || true)
  printf '\n'
}

# This lists all containers for one workspace, even stopped ones.
opencode_workspace_containers() {
  local workspace="$1"
  podman ps -aq --format '{{.Names}}' --filter "name=$(opencode_container_filter_regex "$workspace")" 2>/dev/null || true
}

# This finds the newest running container for one workspace.
opencode_running_container() {
  local workspace="$1"
  local containers
  containers="$(podman ps --sort created --format '{{.Names}}' --filter "name=$(opencode_container_filter_regex "$workspace")" | grep -Ev -- '-next-[0-9]+$' || true)"
  printf '%s\n' "$containers" | sed '/^$/d' | head -n 1
}

# This checks whether one exact container is running right now.
opencode_container_is_running() {
  local container_name="$1"
  local running_container
  running_container="$(podman ps --format '{{.Names}}' --filter "name=$(opencode_container_name_regex "$container_name")" | head -n 1)"
  [[ "$running_container" == "$container_name" ]]
}

# This waits a little because a container may need a moment to show up as running.
opencode_wait_for_running_container() {
  local container_name="$1"
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if opencode_container_is_running "$container_name"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# This confirms a running container stays up across the short pre-attach window.
opencode_wait_for_stable_running_container() {
  local container_name="$1"
  local attempt
  for attempt in 1 2; do
    if ! opencode_container_is_running "$container_name"; then
      return 1
    fi
    sleep 1
  done
  opencode_container_is_running "$container_name"
}

# This gathers a short state summary without failing the wrapper when diagnostics break.
opencode_container_state_summary() {
  local container_name="$1"
  local summary
  if summary="$(podman inspect --format 'status={{.State.Status}} running={{.State.Running}} exit_code={{.State.ExitCode}}' "$container_name" 2>/dev/null)"; then
    [[ -n "$summary" ]] && printf '%s\n' "$summary" && return 0
  fi
  printf 'unavailable\n'
}

# This reads recent container logs without failing the wrapper when Podman cannot provide them.
opencode_container_recent_logs() {
  local container_name="$1"
  local logs
  if logs="$(podman logs --tail 20 "$container_name" 2>/dev/null)"; then
    [[ -n "$logs" ]] && printf '%s\n' "$logs" || printf '(no recent logs)\n'
    return 0
  fi
  return 1
}

# This prints a compact diagnostic block for startup failures.
opencode_print_container_startup_diagnostics() {
  local container_name="$1"
  local recent_logs
  printf 'Container state: %s\n' "$(opencode_container_state_summary "$container_name")" >&2
  if ! recent_logs="$(opencode_container_recent_logs "$container_name")"; then
    printf 'Recent container logs: unavailable\n' >&2
    return 0
  fi
  printf 'Recent container logs:\n%s\n' "$recent_logs" >&2
}

# This checks whether a container already mounts the selected project at the fixed project path.
opencode_container_project_matches() {
  local container_name="$1"
  local project_name="$2"
  local mounts expected
  expected="$(project_root_dir "$project_name"):$OPENCODE_CONTAINER_PROJECT"
  mounts="$(podman inspect --format '{{range .Mounts}}{{println .Source ":" .Destination}}{{end}}' "$container_name" 2>/dev/null || true)"
  printf '%s\n' "$mounts" | sed 's/[[:space:]]*:[[:space:]]*/:/g' | grep -Fqx -- "$expected"
}

# This prints a yellow warning when the terminal supports color.
opencode_warn() {
  local message="$1"
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    printf '\033[33mwarning:\033[0m %s\n' "$message" >&2
    return 0
  fi
  printf 'warning: %s\n' "$message" >&2
}

# This maps each required Linux release asset to the upstream dist directory name.
opencode_release_asset_dist_dir() {
  local asset_name="$1"
  case "$asset_name" in
    opencode-linux-x64-baseline-musl.tar.gz) printf 'opencode-linux-x64-baseline-musl\n' ;;
    opencode-linux-arm64-musl.tar.gz) printf 'opencode-linux-arm64-musl\n' ;;
    *) fail "unsupported release asset: $asset_name" ;;
  esac
}

# This returns the two official Linux musl release assets needed by the wrapper image build.
opencode_release_asset_names() {
  printf 'opencode-linux-x64-baseline-musl.tar.gz\n'
  printf 'opencode-linux-arm64-musl.tar.gz\n'
}

# This fetches the pinned upstream release metadata from GitHub.
opencode_release_metadata_json() {
  curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/tags/${OPENCODE_RELEASE_TAG}"
}

# This extracts one asset field from the pinned upstream release metadata.
opencode_release_asset_field() {
  local metadata_json="$1"
  local asset_name="$2"
  local field_name="$3"
  local compact_json asset_block
  compact_json="$(printf '%s' "$metadata_json" | tr -d '\n')"
  asset_block="$(printf '%s' "$compact_json" | sed -n "s/.*{\([^{}]*\"name\":\"${asset_name}\"[^{}]*\)}.*/\1/p")"
  [[ -n "$asset_block" ]] || fail "failed to find release metadata for ${asset_name}"
  printf '%s' "$asset_block" | sed -n "s/.*\"${field_name}\":\"\([^\"]*\)\".*/\1/p"
}

# This downloads and stages one official OpenCode binary into the upstream dist layout.
opencode_stage_release_asset() {
  local checkout_root="$1"
  local metadata_json="$2"
  local asset_name="$3"
  local asset_url asset_sha stage_dir archive_path unpack_dir
  asset_url="$(opencode_release_asset_field "$metadata_json" "$asset_name" browser_download_url)"
  asset_sha="$(opencode_release_asset_field "$metadata_json" "$asset_name" digest)"
  [[ -n "$asset_url" ]] || fail "failed to resolve download url for ${asset_name}"
  [[ "$asset_sha" == sha256:* ]] || fail "failed to resolve sha256 digest for ${asset_name}"

  stage_dir="$checkout_root/dist/$(opencode_release_asset_dist_dir "$asset_name")/bin"
  archive_path="$checkout_root/dist/${asset_name}"
  unpack_dir="$checkout_root/dist/.tmp-${asset_name%.tar.gz}"

  # This recreates the staged output so each build starts from known release assets.
  rm -rf "$stage_dir" "$unpack_dir"
  mkdir -p "$stage_dir" "$unpack_dir"

  curl -fsSL "$asset_url" -o "$archive_path"
  printf '%s  %s\n' "${asset_sha#sha256:}" "$archive_path" | sha256sum -c - >/dev/null
  tar -xzf "$archive_path" -C "$unpack_dir"
  install -m 755 "$unpack_dir/opencode" "$stage_dir/opencode"
  rm -rf "$unpack_dir" "$archive_path"
}

# This stages the official upstream Linux release binaries into the local build context.
opencode_stage_release_binaries() {
  local checkout_root="$1"
  local metadata_json asset_name
  metadata_json="$(opencode_release_metadata_json)"
  while IFS= read -r asset_name; do
    [[ -n "$asset_name" ]] || continue
    opencode_stage_release_asset "$checkout_root" "$metadata_json" "$asset_name"
  done < <(opencode_release_asset_names)
}

# This fetches the newest published upstream OpenCode release version.
opencode_latest_release_version() {
  local latest_json latest_tag
  latest_json="$(curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/latest" 2>/dev/null)" || return 1
  latest_tag="$(printf '%s' "$latest_json" | tr -d '\n' | sed -n 's/.*"tag_name":"v\{0,1\}\([^"]*\)".*/\1/p')"
  [[ -n "$latest_tag" ]] || return 1
  printf '%s\n' "$latest_tag"
}

# This resolves the newest published Alpine tag line from Docker Hub.
opencode_latest_alpine_version() {
  local tags_json
  tags_json="$(curl -fsSL 'https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100' 2>/dev/null)" || return 1
  printf '%s' "$tags_json" | grep -Eo '"name":"[0-9]+\.[0-9]+"' | sed 's/"name":"//; s/"$//' | sort -V | sed -n '$p'
}

# This resolves the current Docker Hub digest for the pinned Alpine tag.
opencode_current_alpine_digest() {
  local tag_json tag_digest
  tag_json="$(curl -fsSL "https://hub.docker.com/v2/repositories/library/alpine/tags/${OPENCODE_ALPINE_VERSION}" 2>/dev/null)" || return 1
  tag_digest="$(printf '%s' "$tag_json" | tr -d '\n' | sed -n 's/.*"digest":"\([^"]*\)".*/\1/p')"
  [[ -n "$tag_digest" ]] || return 1
  printf '%s\n' "$tag_digest"
}

# This checks pinned versions and prints warnings without blocking a reproducible build.
opencode_warn_if_pins_are_outdated() {
  local latest_version latest_alpine_version current_alpine_digest
  if latest_version="$(opencode_latest_release_version)" && [[ "$latest_version" != "$OPENCODE_VERSION" ]]; then
    opencode_warn "newer OpenCode version available: ${latest_version}"
  fi

  if latest_alpine_version="$(opencode_latest_alpine_version)" && [[ -n "$latest_alpine_version" && "$latest_alpine_version" != "$OPENCODE_ALPINE_VERSION" ]]; then
    opencode_warn "newer Alpine version available: ${latest_alpine_version}"
  fi

  if current_alpine_digest="$(opencode_current_alpine_digest)" && [[ "$current_alpine_digest" != "$OPENCODE_ALPINE_DIGEST" ]]; then
    opencode_warn "newer Alpine digest available for ${OPENCODE_ALPINE_VERSION}"
  fi
}

# This resolves the uid that should own mounted workspace paths on the host.
opencode_host_uid() {
  local uid
  uid="$(id -u)"
  if [[ "$uid" == '0' ]]; then
    printf '%s\n' "${SUDO_UID:-0}"
    return 0
  fi
  printf '%s\n' "$uid"
}

# This resolves the gid that should own mounted workspace paths on the host.
opencode_host_gid() {
  local gid
  gid="$(id -g)"
  if [[ "$gid" == '0' ]]; then
    printf '%s\n' "${SUDO_GID:-0}"
    return 0
  fi
  printf '%s\n' "$gid"
}
