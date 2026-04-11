#!/bin/sh
set -eu

RUNTIME_ENV_FILE="/tmp/opencode-wrapper-runtime.env"
CONFIG_ENV_FILE="/workspace/opencode-workspace/.config/opencode/config.env"
SECRETS_ENV_FILE="/workspace/opencode-workspace/.config/opencode/secrets.env"

append_env_assignments() {
  file="$1"
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*)
        continue
        ;;
      export\ *)
        line=${line#export }
        ;;
    esac

    case "$line" in
      [A-Za-z_][A-Za-z0-9_]*=*)
        printf '%s\n' "$line" >> "$RUNTIME_ENV_FILE"
        ;;
    esac
  done < "$file"
}

: > "$RUNTIME_ENV_FILE"
append_env_assignments "$CONFIG_ENV_FILE"
append_env_assignments "$SECRETS_ENV_FILE"

exec "$@"
