# OpenCode Wrapper Usage

This repo builds and runs a thin local image derived from the official upstream container with all repo-owned settings kept in `config/agent/shared/opencode-settings-shared.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

The official upstream container is the base image. The paths and lifecycle documented here are this wrapper repo's convention.

## Commands

- Build the image: `scripts/agent/shared/opencode-build`
- Start a configured workspace: `scripts/agent/shared/opencode-run`
- Open a shell in a running project container: `scripts/agent/shared/opencode-shell <workspace> <project> [command...]`

## Host To Container Mappings

For a selected workspace named `WORKSPACE` and project `PROJECT`, the run script creates these host paths under `OPENCODE_BASE_PATH`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-home`
- Host workspace path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-general`

The container mappings are:

- Host home path -> `/root`
- Host workspace path -> `/workspace/general`
- `OPENCODE_DEVELOPMENT_ROOT` -> `/workspace/development`
- Shared runtime host development root -> `/workspace/projects`
- Selected project root -> `/workspace/project`

The default in-container working directory is `/workspace/project`.

## Shell And Server Defaults

- `opencode-shell <workspace> <project>` opens `nu` by default.
- `opencode-shell <workspace> -- <command...>` keeps the legacy workspace-plus-command shortcut when exactly one project container is running for that workspace.
- `opencode-run` first ensures a shared per-workspace runtime container is running `serve --hostname 0.0.0.0 --port 4096`.
- That shared runtime container mounts the host development root at `/workspace/projects` and owns the published host port `4096 + workspace offset`.
- Project containers do not publish host ports; they run `opencode attach http://host.containers.internal:<published-port>` against the shared runtime.
- `opencode-run` always opens the published server URL in the default browser on macOS and Linux after the shared runtime is ready.

## Naming

- Built images are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`.
- Shared runtime containers are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>`.
- Project containers are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<project>`.
- New shared or project containers are first created as `<canonical>-next-<pid>` and renamed only after they stay healthy.

## Runtime Pin

- Upstream base image: `ghcr.io/anomalyco/opencode:1.14.21`
- Architecture: `arm64`
- Local `Containerfile`: thin wrapper over the official upstream container
- Added packages: `git`, `bash`, `nushell`

## Workspace Safety

If the selected workspace already has a shared runtime container, `opencode-run` reuses or starts it before handling the requested project container.

If the selected workspace/project already has a canonical project container, `opencode-run` keeps using that same container instead of replacing it for image drift, project drift, or port drift.

If no shared runtime or project container exists yet, the wrapper stages a `-next-<pid>` container, waits for it to stay healthy, then renames it to the canonical container name.

## Selection UX

- Workspace and project pickers retry on invalid or out-of-range input.
- Enter `q` to cancel selection.
- EOF aborts selection cleanly.
