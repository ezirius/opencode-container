# OpenCode Wrapper Architecture

This repo keeps a small wrapper around an OpenCode container with three responsibility layers:

- `config/agent/shared/opencode-settings-shared.conf` owns runtime and build configuration.
- `lib/shell/shared/common.sh` owns shared shell helpers for config loading, workspace parsing, project lookup, and container lookup.
- `scripts/agent/shared/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `config/containers/shared/Containerfile` builds the runtime image and reflects the config contract through build args.
- `lib/shell/shared/common.sh` is the only shared shell library path.
- `scripts/agent/shared/opencode-build` builds an image from config.
- `scripts/agent/shared/opencode-run` starts a selected workspace, mounts host paths into the container, recreates stale exact-match containers when the mounted project changes, and attaches to OpenCode.
- `scripts/agent/shared/opencode-shell` connects to an existing workspace container.
- `tests/agent/shared/*` verify behavior and layout.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The host workspace dirname is `opencode-general`.
- The container workspace path is `/workspace/general`.
- The development root mount is `/workspace/development`.
- The selected project mount is `/workspace/project`.
- Project-facing commands should run from `/workspace/project`.
