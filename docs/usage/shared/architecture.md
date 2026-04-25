# OpenCode Wrapper Architecture

This repo keeps a small wrapper around an OpenCode container with three responsibility layers:

- `config/agent/shared/opencode-settings-shared.conf` owns runtime and build configuration.
- `lib/shell/shared/common.sh` owns shared shell helpers for config loading, workspace parsing, project lookup, and container lookup.
- `scripts/agent/shared/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `config/containers/shared/Containerfile` is a thin local `Containerfile` that stays close to the official upstream container.
- `lib/shell/shared/common.sh` is the only shared shell library path.
- `scripts/agent/shared/opencode-build` builds the thin local image from the official upstream base while keeping the old git safety checks.
- `scripts/agent/shared/opencode-run` first ensures a shared per-workspace runtime container exists, mounts the host development root there at `/workspace/projects`, keeps that shared container published on the stable host port, creates containers directly with their canonical names, and uses project containers to run `opencode attach` against that shared runtime.
- `scripts/agent/shared/opencode-shell` connects to an existing workspace/project container and opens `nu` by default.
- `tests/agent/shared/*` verify behavior and layout.

## Upstream Boundary

- The official upstream container is the runtime source.
- The official upstream container is the base image, not the final runtime image used by the wrapper.
- This wrapper's mount paths, `/root` home mapping, project picker, and shared-runtime-plus-project-container lifecycle are wrapper convention, not upstream-required behavior.
- The wrapper pins version `1.14.24` and `arm64` in config so runtime selection is explicit.
- The local `Containerfile` stays thin and adds `git`, `bash`, and `nushell`.
- Local images and containers use wrapper-owned names derived from the pinned version, a build timestamp, and the full image ID.
- `opencode-build` and `opencode-run` share a best-effort pinned-version freshness check before expensive or interactive container work.
- OpenCode release lookup failures never fail build or run.
- Freshness warning color and pause behavior are TTY-gated so non-interactive tests and automation keep plain, non-blocking stderr.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The wrapper mounts the workspace home at `/root` to stay aligned with the upstream root user.
- The host workspace dirname is `opencode-general`.
- The container workspace path is `/workspace/general`.
- The development root mount is `/workspace/development`.
- The shared runtime projects path is `/workspace/projects`.
- The selected project mount is `/workspace/project`.
- Project-facing commands should run from `/workspace/project`.
