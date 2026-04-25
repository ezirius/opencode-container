# OpenCode Wrapper Usage

This repo builds and runs a thin local image derived from the official upstream container with all repo-owned settings kept in `config/agent/shared/opencode-settings-shared.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

The official upstream container is the base image. The paths and lifecycle documented here are this wrapper repo's convention.

## Commands

- Build the image: `scripts/agent/shared/opencode-build`
- Start a configured workspace: `scripts/agent/shared/opencode-run`
- Open a shell or run a command in a running project container: `scripts/agent/shared/opencode-shell <workspace> <project> [command...]`

`opencode-shell <workspace> <project>` opens `nu` by default.

`opencode-shell <workspace> <project> [command...]` runs the command directly inside the project container.

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

- `opencode-shell` prompts for workspace and project, then opens `nu` by default.
- `opencode-shell <workspace>` prompts for project, then opens `nu` by default.
- `opencode-shell <workspace> <project>` opens `nu` by default.
- `opencode-shell <workspace> <project> [command...]` runs the command directly inside the project container.
- `opencode-run` first ensures a shared per-workspace runtime container is running `serve --hostname 0.0.0.0 --port 4096`.
- The shared runtime container is the published browser server for the workspace.
- That shared runtime container mounts the host development root at `/workspace/projects` and owns the published host port `4096 + workspace offset`.
- Each project container runs a private local OpenCode server for its selected project and attaches to that server at `http://127.0.0.1:4096`.
- Project containers do not publish host ports; they run their own `serve --hostname 0.0.0.0 --port 4096` process and attach to `http://127.0.0.1:4096` inside the project container.
- `opencode-run` opens the published server URL in the default browser on macOS and Linux only when it creates or starts the shared runtime container.

## Naming

- Built images are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`.
- Shared runtime containers are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<development-root-basename>`.
- Project containers are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<project>`.
- New shared and project containers are created directly with their final canonical names.

## Runtime Pin

- Upstream base image: `ghcr.io/anomalyco/opencode:1.14.25`
- Configured target architecture: `arm64`; the build uses the local `Containerfile` image tag without passing a separate platform flag.
- Local `Containerfile`: thin wrapper over the official upstream container
- Added packages: `git`, `bash`, `nushell`
- `opencode-build` and `opencode-run` check the latest upstream OpenCode release before container build or run work starts.
- If a newer release exists, they warn on stderr and continue with the pinned version.
- The warning label is amber/yellow only when stderr is a terminal and `NO_COLOR` is unset; otherwise it stays plain text.
- They pause with `Press any key to continue...` only when both stdin and stderr are real terminals.

## Workspace Safety

If the selected workspace already has a shared runtime container, `opencode-run` reuses or starts it before handling the requested project container.

If the selected workspace/project already has a canonical project container, `opencode-run` keeps using that same container instead of replacing it for image drift, project drift, or port drift.

If no shared runtime or project container exists yet, the wrapper creates it directly with its canonical container name and waits for it to stay healthy before attaching.

## Selection UX

- Workspace and project pickers retry on invalid or out-of-range input.
- Enter `q` to cancel selection.
- EOF aborts selection cleanly.
