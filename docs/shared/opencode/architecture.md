# OpenCode Wrapper Architecture

This repo keeps a small wrapper around an OpenCode container with three responsibility layers:

- `configs/shared/opencode/opencode-settings-shared.conf` owns runtime and build configuration.
- `libs/shared/opencode/common.sh` owns shared shell helpers for config loading, workspace parsing, project lookup, and container lookup.
- `scripts/shared/opencode/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `configs/shared/opencode/Containerfile` is a thin local `Containerfile` that stays close to the official upstream container.
- `libs/shared/opencode/common.sh` is the only shared shell library path.
- `scripts/shared/opencode/opencode-build` builds the thin local image from the official upstream base while enforcing the documented clean-checkout and branch policy.
- `scripts/shared/opencode/opencode-run` first ensures a shared per-workspace runtime container exists, mounts the host development root there at `/workspace/projects`, keeps that shared container published on the stable host port derived from `OPENCODE_SERVER_PORT + workspace offset`, creates containers directly with their canonical names, and project containers run `opencode attach http://$OPENCODE_ATTACH_HOST:$OPENCODE_SERVER_PORT` inside their own container.
- The shared runtime container owns the published host port and browser URL for the workspace.
- Project containers keep project sessions private: they do not publish host ports, run their own local server, and attach to `http://$OPENCODE_ATTACH_HOST:$OPENCODE_SERVER_PORT` inside the container.
- `scripts/shared/opencode/opencode-shell` connects to an existing workspace/project container and opens `nu` by default.
- `tests/shared/opencode/*` verify behaviour and layout.

## Upstream Boundary

- The official upstream container is the runtime source.
- The official upstream container is the base image, not the final runtime image used by the wrapper.
- This wrapper's mount paths, `/root` home mapping, project picker, and shared-runtime-plus-project-container lifecycle are wrapper convention, not upstream-required behaviour.
- The `Containerfile` pins the upstream image tag directly and does not enforce a separate platform flag by itself.
- The local `Containerfile` stays thin and adds `git`, `bash`, and `nushell`.
- Local images and containers use wrapper-owned names derived from the pinned version, a build timestamp, and the 12-character image ID prefix.
- `opencode-build` and `opencode-run` share a best-effort pinned-version freshness check before expensive or interactive container work.
- OpenCode release lookup failures never fail build or run.
- Freshness warning colour and pause behaviour are TTY-gated so non-interactive tests and automation keep plain, non-blocking stderr.
- Release lookup URL and timeout values are repo-owned config in `configs/shared/opencode/opencode-settings-shared.conf`.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The wrapper mounts the workspace home at `/root` to stay aligned with the upstream root user.
- The host workspace dirname is `opencode-general`.
- The container workspace path is `/workspace/general`.
- The shared runtime mounts the development root at `/workspace/projects`.
- Project containers mount the development root at `/workspace/development`.
- The selected project mount is `/workspace/project`.
- Project-facing commands should run from `/workspace/project`.
- The in-container serve hostname comes from `OPENCODE_SERVER_HOSTNAME`.
- The in-container attach host comes from `OPENCODE_ATTACH_HOST`.
