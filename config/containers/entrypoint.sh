#!/bin/sh
set -eu

CONTAINER_WORKSPACE_DIR="${OPENCODE_CONTAINER_WORKSPACE_DIR:?missing OPENCODE_CONTAINER_WORKSPACE_DIR}"
CONTAINER_RUNTIME_ENV_FILE="${OPENCODE_CONTAINER_RUNTIME_ENV_FILE:?missing OPENCODE_CONTAINER_RUNTIME_ENV_FILE}"

RUNTIME_ENV_FILE="${OPENCODE_WRAPPER_RUNTIME_ENV_FILE:-$CONTAINER_RUNTIME_ENV_FILE}"
CONFIG_ENV_FILE="${OPENCODE_WRAPPER_CONFIG_ENV_FILE:-$CONTAINER_WORKSPACE_DIR/.config/opencode/config.env}"
SECRETS_ENV_FILE="${OPENCODE_WRAPPER_SECRETS_ENV_FILE:-$CONTAINER_WORKSPACE_DIR/.config/opencode/secrets.env}"
CR="$(printf '\r')"

trim_leading_spaces() {
  value="$1"
  value=${value#"${value%%[![:space:]]*}"}
  printf '%s' "$value"
}

trim_trailing_spaces() {
  value="$1"
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

normalise_assignment_value() {
  value="$1"
  rest=
  suffix=

  value=${value%"$CR"}
  value=$(trim_leading_spaces "$value")
  value=$(trim_trailing_spaces "$value")

  case "$value" in
    \"*)
      rest=${value#\"}
      inner=${rest%%\"*}
      suffix=${rest#"$inner"}
      if [ "$suffix" != "$rest" ]; then
        suffix=${suffix#\"}
        suffix=$(trim_leading_spaces "$suffix")
        case "$suffix" in
          ''|'#'*)
            printf '%s' "$inner"
            return 0
            ;;
        esac
      fi
      ;;
    \'*)
      rest=${value#\'}
      inner=${rest%%\'*}
      suffix=${rest#"$inner"}
      if [ "$suffix" != "$rest" ]; then
        suffix=${suffix#\'}
        suffix=$(trim_leading_spaces "$suffix")
        case "$suffix" in
          ''|'#'*)
            printf '%s' "$inner"
            return 0
            ;;
        esac
      fi
      ;;
  esac

  value=${value%%#*}
  value=$(trim_trailing_spaces "$value")
  printf '%s' "$value"
}

append_single_quoted() {
  value="$1"
  printf "'"
  while :; do
    case "$value" in
      *"'"*)
        prefix=${value%%\'*}
        printf "%s'\\''" "$prefix"
        value=${value#*\'}
        ;;
      *)
        printf "%s'" "$value"
        return 0
        ;;
    esac
  done
}

append_env_assignments() {
  file="$1"
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$CR"}
    line=$(trim_leading_spaces "$line")
    case "$line" in
      ''|'#'*)
        continue
        ;;
      export*)
        case "$line" in
          export[[:space:]]*)
            line=${line#export}
            line=${line#"${line%%[![:space:]]*}"}
            ;;
        esac
        ;;
    esac

    case "$line" in
      [A-Za-z_][A-Za-z0-9_]*=*)
        key=${line%%=*}
        case "$key" in
          OPENCODE_CONFIG|OPENCODE_CONFIG_DIR)
            continue
            ;;
        esac
        value=${line#*=}
        value=$(normalise_assignment_value "$value")
        printf 'export %s=' "$key" >> "$TMP_RUNTIME_ENV_FILE"
        append_single_quoted "$value" >> "$TMP_RUNTIME_ENV_FILE"
        printf '\n' >> "$TMP_RUNTIME_ENV_FILE"
        ;;
    esac
  done < "$file"
}

TMP_RUNTIME_ENV_FILE="$(mktemp "${RUNTIME_ENV_FILE}.XXXXXX")"
chmod 600 "$TMP_RUNTIME_ENV_FILE"
append_env_assignments "$CONFIG_ENV_FILE"
append_env_assignments "$SECRETS_ENV_FILE"
mv -f "$TMP_RUNTIME_ENV_FILE" "$RUNTIME_ENV_FILE"

exec "$@"
