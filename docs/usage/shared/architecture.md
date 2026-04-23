# OpenCode Wrapper Architecture

This repo keeps a small wrapper around an OpenCode container with three responsibility layers:

- `config/agent/shared/opencode-settings-shared.conf` owns runtime and build configuration.
- `lib/shell/shared/common.sh` owns shared shell helpers for config loading, workspace parsing, project lookup, and container lookup.
- `scripts/agent/shared/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `config/containers/shared/Containerfile` is a thin local `Containerfile` that stays close to the official upstream container.
- `lib/shell/shared/common.sh` is the only shared shell library path.
- `scripts/agent/shared/opencode-build` builds the thin local image from the official upstream base while keeping the old git safety checks.
- `scripts/agent/shared/opencode-run` starts a selected workspace, mounts host paths into the container, starts upstream `serve` mode on port `4096`, publishes a stable host port by default unless `--no-ports` is requested, recreates stale exact-match containers when the mounted project changes, and uses `opencode attach` against that long-lived server.
- `scripts/agent/shared/opencode-shell` connects to an existing workspace container and opens `nu` by default.
- `tests/agent/shared/*` verify behavior and layout.

## Upstream Boundary

- The official upstream container is the runtime source.
- The official upstream container is the base image, not the final runtime image used by the wrapper.
- This wrapper's mount paths, `/root` home mapping, project picker, and one-container-per-workspace lifecycle are wrapper convention, not upstream-required behavior.
- The wrapper pins version `1.14.21` and `arm64` in config so runtime selection is explicit.
- The local `Containerfile` stays thin and adds `git`, `bash`, and `nushell`.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The wrapper mounts the workspace home at `/root` to stay aligned with the upstream root user.
- The host workspace dirname is `opencode-general`.
- The container workspace path is `/workspace/general`.
- The development root mount is `/workspace/development`.
- The selected project mount is `/workspace/project`.
- Project-facing commands should run from `/workspace/project`.
