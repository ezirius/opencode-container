#!/usr/bin/env bash

set -euo pipefail

# This file holds the shared shell helpers used by the wrapper scripts.

# This finds the repo root when a script did not pass it in first.
if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

# This loads the saved repo settings so the helpers all read the same values.
# shellcheck disable=SC1090
source "$ROOT/configs/shared/opencode/opencode-settings-shared.conf"

declare -a OPENCODE_WORKSPACE_NAMES=()
declare -a OPENCODE_WORKSPACE_OFFSETS=()

# This tells us whether stderr supports coloured wrapper output.
opencode_use_colour_terminal() {
  [[ -t 2 && -z "${NO_COLOR:-}" ]]
}

# This stops the current command with one clear failure message.
fail() {
  if opencode_use_colour_terminal; then
    printf '\033[31m%s\033[0m\n' "$*" >&2
    exit 1
  fi
  printf '%s\n' "$*" >&2
  exit 1
}

# This prints an active prompt in green when the terminal supports colour.
opencode_active_prompt() {
  local message="$1"
  if opencode_use_colour_terminal; then
    printf '\033[32m%b\033[0m' "$message" >&2
    return 0
  fi
  printf '%b' "$message" >&2
}

# This prints a success message in green when the terminal supports colour.
opencode_success() {
  local message="$1"
  if opencode_use_colour_terminal; then
    printf '\033[32m%s\033[0m\n' "$message" >&2
    return 0
  fi
  printf '%s\n' "$message" >&2
}

# This checks that a workspace name only uses safe characters.
opencode_validate_workspace_name() {
  local name="$1"

  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ || "$name" == '-'* || "$name" == '.' || "$name" == '..' ]]; then
    printf "Workspace name %s may only contain letters, numbers, dots, underscores, and hyphens, must not start with '-', and must not be '.' or '..'.\n" "$name" >&2
    exit 1
  fi
}

# This checks whether a project name is safe without exiting the current shell.
opencode_project_name_is_safe() {
  local project_name="$1"
  [[ -n "$project_name" ]] || return 1
  [[ "$project_name" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$project_name" != */* ]] || return 1
  [[ "$project_name" != *:* ]] || return 1
  [[ "$project_name" != '.' ]] || return 1
  [[ "$project_name" != '..' ]] || return 1
  [[ "$project_name" != '--' ]] || return 1
}

# This checks that a project name is a direct-child directory token.
opencode_require_project_name() {
  local project_name="$1"
  [[ -n "$project_name" ]] || fail "project name must not be empty"
  opencode_project_name_is_safe "$project_name" || fail "project name $project_name may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.', '..', or '--'"
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
  printf '^%s-%s-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}$\n' "$escaped_basename" "$escaped_version"
}

# This builds the canonical container name for one image, workspace, and project.
opencode_container_name() {
  local image_name="$1"
  local workspace="$2"
  local project_name="$3"
  printf '%s-%s-%s\n' "$image_name" "$workspace" "$project_name"
}

# This builds the canonical shared runtime container name for one workspace.
opencode_shared_container_name() {
  local image_name="$1"
  local workspace="$2"
  printf '%s-%s-%s\n' "$image_name" "$workspace" "$OPENCODE_SHARED_CONTAINER_SCOPE"
}

# This checks whether a container name uses the shared runtime scope suffix.
opencode_container_has_shared_runtime_scope() {
  local container_name="$1"
  [[ "$container_name" == *-"$OPENCODE_SHARED_CONTAINER_SCOPE" ]]
}

# This builds the broad regex used to find OpenCode container candidates.
opencode_container_candidate_regex() {
  local escaped_basename
  escaped_basename="$(opencode_regex_escape "$OPENCODE_IMAGE_BASENAME")"
  printf '^%s-' "$escaped_basename"
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

# This tells us whether stderr is a real terminal for warning output.
opencode_use_warning_terminal() {
  [[ -t 2 ]]
}

# This pauses only when a person can see stderr and answer on stdin.
opencode_pause_for_interactive_warning() {
  local _pressed_key

  if [[ -t 0 && -t 2 ]]; then
    printf 'Press any key to continue...' >&2
    IFS= read -r -n 1 -s _pressed_key
    printf '\n' >&2
  fi
}

# This fetches the latest upstream OpenCode release version without failing callers.
opencode_latest_upstream_version() {
  local release_json tag_regex

  opencode_require_release_check_settings

  if ! release_json="$(curl -fsSL --connect-timeout "$OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS" --max-time "$OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS" "$OPENCODE_RELEASE_API_URL" 2>/dev/null)"; then
    printf '\n'
    return 0
  fi

  tag_regex='"tag_name"[[:space:]]*:[[:space:]]*"v([0-9]+\.[0-9]+\.[0-9]+)"'
  if [[ "$release_json" =~ $tag_regex ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '\n'
}

# This compares simple numeric upstream versions like 1.14.25 against a pinned version.
opencode_version_is_newer_than() {
  local candidate_version="$1"
  local pinned_version="$2"
  local candidate_major candidate_minor candidate_patch pinned_major pinned_minor pinned_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate_version"
  IFS=. read -r pinned_major pinned_minor pinned_patch <<< "$pinned_version"

  (( candidate_major > pinned_major )) && return 0
  (( candidate_major < pinned_major )) && return 1
  (( candidate_minor > pinned_minor )) && return 0
  (( candidate_minor < pinned_minor )) && return 1
  (( candidate_patch > pinned_patch ))
}

# This checks that the saved server port is numeric before runtime helpers use it.
opencode_require_server_port() {
  [[ "$OPENCODE_SERVER_PORT" =~ ^[0-9]+$ ]] || fail 'OPENCODE_SERVER_PORT must be numeric.'
}

# This checks that one saved config value is not empty before helpers use it.
opencode_require_config_value() {
  local value="$1"
  local name="$2"
  [[ -n "$value" ]] || fail "$name must not be empty."
}

# This checks that one saved config value is numeric before helpers use it.
opencode_require_numeric_config_value() {
  local value="$1"
  local name="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$name must be numeric."
}

# This checks the saved release lookup settings before network helpers use them.
opencode_require_release_check_settings() {
  opencode_require_config_value "$OPENCODE_RELEASE_API_URL" 'OPENCODE_RELEASE_API_URL'
  opencode_require_numeric_config_value "$OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS" 'OPENCODE_RELEASE_CONNECT_TIMEOUT_SECONDS'
  opencode_require_numeric_config_value "$OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS" 'OPENCODE_RELEASE_MAX_TIMEOUT_SECONDS'
}

# This checks the saved runtime wait settings before readiness helpers use them.
opencode_require_runtime_wait_settings() {
  opencode_require_numeric_config_value "$OPENCODE_RUNNING_WAIT_ATTEMPTS" 'OPENCODE_RUNNING_WAIT_ATTEMPTS'
  opencode_require_numeric_config_value "$OPENCODE_RUNNING_WAIT_SECONDS" 'OPENCODE_RUNNING_WAIT_SECONDS'
  opencode_require_numeric_config_value "$OPENCODE_STABLE_WAIT_ATTEMPTS" 'OPENCODE_STABLE_WAIT_ATTEMPTS'
  opencode_require_numeric_config_value "$OPENCODE_STABLE_WAIT_SECONDS" 'OPENCODE_STABLE_WAIT_SECONDS'
  opencode_require_numeric_config_value "$OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS" 'OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS'
  opencode_require_numeric_config_value "$OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS" 'OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS'
  opencode_require_numeric_config_value "$OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS" 'OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS'
  opencode_require_numeric_config_value "$OPENCODE_PUBLISHED_URL_WAIT_SECONDS" 'OPENCODE_PUBLISHED_URL_WAIT_SECONDS'
}

# This checks the saved attach settings before interactive attach helpers use them.
opencode_require_attach_settings() {
  opencode_require_config_value "$OPENCODE_ATTACH_HOST" 'OPENCODE_ATTACH_HOST'
}

# This builds the private in-container attach URL from the saved host and port.
opencode_attach_url() {
  opencode_require_server_port
  opencode_require_attach_settings
  printf 'http://%s:%s\n' "$OPENCODE_ATTACH_HOST" "$OPENCODE_SERVER_PORT"
}

# This warns when the pinned OpenCode version is not the latest upstream release.
opencode_warn_if_pinned_version_is_stale() {
  local latest_version

  latest_version="$(opencode_latest_upstream_version)"
  [[ -n "$latest_version" ]] || return 0
  opencode_version_is_newer_than "$latest_version" "$OPENCODE_VERSION" || return 0

  opencode_warn "newer OpenCode version available (${latest_version}); continuing with pinned version ${OPENCODE_VERSION}"
  opencode_pause_for_interactive_warning
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

# This resolves the current local branch name from HEAD.
opencode_git_current_branch() {
  local checkout_root="${1:-$ROOT}"
  git -C "$checkout_root" symbolic-ref --quiet --short HEAD
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

# This warns when cached origin HEAD is stale without changing build policy decisions.
opencode_warn_if_origin_head_is_not_main() {
  local checkout_root="${1:-$ROOT}"
  local remote_head
  remote_head="$(git -C "$checkout_root" symbolic-ref 'refs/remotes/origin/HEAD' 2>/dev/null || true)"
  [[ -n "$remote_head" ]] || return 0
  if [[ "$remote_head" != 'refs/remotes/origin/main' ]]; then
    opencode_warn "local origin/HEAD points to ${remote_head}, expected refs/remotes/origin/main; ignoring cached remote HEAD for build policy."
  fi
}

# This prints the ahead/behind counts against the configured upstream.
opencode_git_branch_ahead_behind() {
  local checkout_root="${1:-$ROOT}"
  git -C "$checkout_root" rev-list --left-right --count HEAD...@{upstream}
}

# This enforces the build checkout policy for main and local worktree branches.
opencode_require_build_ready_checkout() {
  local checkout_root="${1:-$ROOT}"
  local branch_name counts ahead behind upstream_ref

  opencode_require_clean_committed_checkout "$checkout_root"
  if ! branch_name="$(opencode_git_current_branch "$checkout_root" 2>/dev/null)"; then
    fail 'Build requires an attached branch HEAD.'
  fi

  if [[ "$branch_name" != 'main' ]]; then
    if opencode_git_has_upstream "$checkout_root"; then
      fail 'Build only allows remote-tracking builds from main. Use a clean committed local worktree branch or main tracking origin/main.'
    fi
    return 0
  fi

  upstream_ref="$(opencode_git_upstream_ref "$checkout_root" 2>/dev/null || true)"
  if [[ "$upstream_ref" != 'origin/main' ]]; then
    fail 'Build requires main to track origin/main.'
  fi

  counts="$(opencode_git_branch_ahead_behind "$checkout_root")"
  ahead="$(printf '%s\n' "$counts" | awk '{print $1}')"
  behind="$(printf '%s\n' "$counts" | awk '{print $2}')"

  if [[ "$ahead" != '0' || "$behind" != '0' ]]; then
    fail 'Build requires main to be pushed and in sync with origin/main.'
  fi

  opencode_warn_if_origin_head_is_not_main "$checkout_root"
}

# This reads the saved workspace list and splits it into names and offsets.
opencode_load_workspaces() {
  local entry name offset index
  OPENCODE_WORKSPACE_NAMES=()
  OPENCODE_WORKSPACE_OFFSETS=()

  opencode_require_server_port

  for entry in $OPENCODE_WORKSPACES; do
    name="${entry%%:*}"
    offset="${entry#*:}"
    [[ -n "$name" && -n "$offset" && "$name" != "$offset" ]] || fail 'Each OPENCODE_WORKSPACES entry must look like name:offset.'
    opencode_validate_workspace_name "$name"
    [[ "$offset" =~ ^[0-9]+$ ]] || fail "Workspace offset for $name must be numeric."

    for index in "${!OPENCODE_WORKSPACE_NAMES[@]}"; do
      if [[ "${OPENCODE_WORKSPACE_NAMES[$index]}" == "$name" ]]; then
        fail "Workspace name $name is configured more than once."
      fi

      if [[ "${OPENCODE_WORKSPACE_OFFSETS[$index]}" == "$offset" ]]; then
        fail "Workspace offset $offset is configured more than once."
      fi
    done

    OPENCODE_WORKSPACE_NAMES+=("$name")
    OPENCODE_WORKSPACE_OFFSETS+=("$offset")
  done

  [[ ${#OPENCODE_WORKSPACE_NAMES[@]} -gt 0 ]] || fail 'Please configure at least one workspace in OPENCODE_WORKSPACES.'
}

# This prints a small menu and returns the workspace the person picked.
opencode_pick_workspace() {
  local selection index
  while true; do
    opencode_active_prompt 'Pick a workspace:\n'
    for index in "${!OPENCODE_WORKSPACE_NAMES[@]}"; do
      printf '%d) %s\n' "$((index + 1))" "${OPENCODE_WORKSPACE_NAMES[$index]}" >&2
    done
    opencode_active_prompt 'Selection: '
    if ! read -r selection; then
      fail 'Selection aborted.'
    fi
    if [[ "$selection" == 'q' ]]; then
      fail 'Selection cancelled.'
    fi

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

    printf 'Please pick one of the configured workspaces.\n' >&2
  done
}

# This looks up the saved port offset for one workspace.
opencode_workspace_offset() {
  local workspace="$1"
  local index

  # This lets helper-only callers resolve workspace ports without preloading first.
  if [[ ${#OPENCODE_WORKSPACE_NAMES[@]} -eq 0 ]]; then
    opencode_load_workspaces
  fi

  for index in "${!OPENCODE_WORKSPACE_NAMES[@]}"; do
    if [[ "$workspace" == "${OPENCODE_WORKSPACE_NAMES[$index]}" ]]; then
      printf '%s\n' "${OPENCODE_WORKSPACE_OFFSETS[$index]}"
      return 0
    fi
  done
  fail "Workspace $workspace is not configured."
}

# This derives the stable host port used when the wrapper publishes one workspace server.
opencode_workspace_published_port() {
  local workspace="$1"
  local offset
  offset="$(opencode_workspace_offset "$workspace")"
  printf '%s\n' "$((OPENCODE_SERVER_PORT + offset))"
}

# This checks whether the current host shell is running on macOS.
opencode_host_is_macos() {
  [[ "$(uname -s)" == 'Darwin' ]]
}

# This checks whether the current host shell is running on Linux.
opencode_host_is_linux() {
  [[ "$(uname -s)" == 'Linux' ]]
}

# This builds the browser URL for the published workspace server port.
opencode_workspace_published_url() {
  local workspace="$1"
  printf 'http://127.0.0.1:%s\n' "$(opencode_workspace_published_port "$workspace")"
}

# This lists direct-child project names from the configured development root.
project_names_from_development_root() {
  local candidate project_name
  local -a project_names=()
  local development_root
  local nullglob_was_enabled=0

  development_root="$(opencode_expand_home_path "$OPENCODE_DEVELOPMENT_ROOT")"

  [[ -d "$development_root" ]] || return 0

  if shopt -q nullglob; then
    nullglob_was_enabled=1
  else
    shopt -s nullglob
  fi
  for candidate in "$development_root"/*; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    project_name="${candidate##*/}"
    if ! opencode_project_name_is_safe "$project_name"; then
      continue
    fi
    project_names+=("$project_name")
  done
  if [[ "$nullglob_was_enabled" != '1' ]]; then
    shopt -u nullglob
  fi

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

  while true; do
    opencode_active_prompt 'Pick a project:\n'
    for index in "${!options[@]}"; do
      printf '%d) %s\n' "$((index + 1))" "${options[$index]}" >&2
    done
    opencode_active_prompt 'Selection: '
    if ! read -r selection; then
      fail 'Selection aborted.'
    fi
    if [[ "$selection" == 'q' ]]; then
      fail 'Selection cancelled.'
    fi

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

    printf 'Please pick one of the discovered projects.\n' >&2
  done
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
  local container_name

  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    if opencode_container_workspace_matches "$container_name" "$workspace"; then
      printf '%s\n' "$container_name"
    fi
  done < <(podman ps -aq --format '{{.Names}}' --filter "name=$(opencode_container_candidate_regex)" 2>/dev/null || true)
}

# This finds the newest running shared runtime container for one workspace.
opencode_running_shared_container() {
  local workspace="$1"
  local container_name

  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    if opencode_container_workspace_matches "$container_name" "$workspace" && opencode_container_has_shared_runtime_scope "$container_name"; then
      printf '%s\n' "$container_name"
      return 0
    fi
  done < <(podman ps --sort created --format '{{.Names}}' --filter "name=$(opencode_container_candidate_regex)" 2>/dev/null || true)

  printf '\n'
}

# This finds the newest existing shared runtime container for one workspace.
opencode_existing_shared_container() {
  local workspace="$1"
  local container_name

  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    if opencode_container_workspace_matches "$container_name" "$workspace" && opencode_container_has_shared_runtime_scope "$container_name"; then
      printf '%s\n' "$container_name"
      return 0
    fi
  done < <(podman ps -aq --format '{{.Names}}' --filter "name=$(opencode_container_candidate_regex)" 2>/dev/null || true)

  printf '\n'
}

# This finds the newest running container for one workspace and project.
opencode_running_container() {
  local workspace="$1"
  local project_name="${2-}"
  local container_name

  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    if opencode_container_workspace_matches "$container_name" "$workspace" && { [[ -z "$project_name" ]] || opencode_container_project_matches "$container_name" "$project_name"; }; then
      printf '%s\n' "$container_name"
      return 0
    fi
  done < <(podman ps --sort created --format '{{.Names}}' --filter "name=$(opencode_container_candidate_regex)" 2>/dev/null || true)

  printf '\n'
}

# This checks whether one exact container is running right now.
opencode_container_is_running() {
  local container_name="$1"
  local running_container
  running_container="$(podman ps --format '{{.Names}}' --filter "name=$(opencode_container_name_regex "$container_name")" | head -n 1)"
  [[ "$running_container" == "$container_name" ]]
}

# This checks whether one exact container exists in any state right now.
opencode_container_exists() {
  local container_name="$1"
  local existing_container
  existing_container="$(podman ps -aq --format '{{.Names}}' --filter "name=$(opencode_container_name_regex "$container_name")" | head -n 1)"
  [[ "$existing_container" == "$container_name" ]]
}

# This waits a little because a container may need a moment to show up as running.
opencode_wait_for_running_container() {
  local container_name="$1"
  local attempt
  opencode_require_runtime_wait_settings
  for ((attempt = 1; attempt <= OPENCODE_RUNNING_WAIT_ATTEMPTS; attempt++)); do
    if opencode_container_is_running "$container_name"; then
      return 0
    fi
    sleep "$OPENCODE_RUNNING_WAIT_SECONDS"
  done
  return 1
}

# This confirms a running container stays up across the short pre-attach window.
opencode_wait_for_stable_running_container() {
  local container_name="$1"
  local attempt
  opencode_require_runtime_wait_settings
  for ((attempt = 1; attempt <= OPENCODE_STABLE_WAIT_ATTEMPTS; attempt++)); do
    if ! opencode_container_is_running "$container_name"; then
      return 1
    fi
    if (( attempt < OPENCODE_STABLE_WAIT_ATTEMPTS )); then
      sleep "$OPENCODE_STABLE_WAIT_SECONDS"
    fi
  done
  opencode_container_is_running "$container_name"
}

# This waits briefly for the published host URL to answer before opening a browser.
opencode_wait_for_published_url() {
  local url="$1"
  local attempt
  opencode_require_runtime_wait_settings
  for ((attempt = 1; attempt <= OPENCODE_PUBLISHED_URL_WAIT_ATTEMPTS; attempt++)); do
    if curl -fsS --connect-timeout "$OPENCODE_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS" --max-time "$OPENCODE_PUBLISHED_URL_MAX_TIMEOUT_SECONDS" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$OPENCODE_PUBLISHED_URL_WAIT_SECONDS"
  done
  return 1
}

# This detaches the browser launcher so it survives the wrapper handing control to exec.
opencode_open_published_url_detached() {
  local url="$1"

  if opencode_host_is_macos; then
    nohup open "$url" >/dev/null 2>&1 < /dev/null &
    return 0
  fi

  if opencode_host_is_linux; then
    nohup bash -c '
      if xdg-open "$1" >/dev/null 2>&1; then
        exit 0
      fi
      gio open "$1" >/dev/null 2>&1 || true
    ' _ "$url" >/dev/null 2>&1 < /dev/null &
  fi
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

# This checks whether a container already mounts the selected workspace at the fixed workspace path.
opencode_container_workspace_matches() {
  local container_name="$1"
  local workspace="$2"
  local mounts expected
  expected="$(opencode_host_workspace_dir "$workspace"):$OPENCODE_CONTAINER_WORKSPACE"
  mounts="$(podman inspect --format '{{range .Mounts}}{{println .Source ":" .Destination}}{{end}}' "$container_name" 2>/dev/null || true)"
  printf '%s\n' "$mounts" | sed 's/[[:space:]]*:[[:space:]]*/:/g' | grep -Fqx -- "$expected"
}

# This prints an amber warning when the terminal supports colour.
opencode_warn() {
  local message="$1"
  if opencode_use_warning_terminal && [[ -z "${NO_COLOR:-}" ]]; then
    printf '\033[33mwarning:\033[0m %s\n' "$message" >&2
    return 0
  fi
  printf 'warning: %s\n' "$message" >&2
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
