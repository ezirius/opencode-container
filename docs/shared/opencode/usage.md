# OpenCode Wrapper Usage

This repo builds and runs a thin local image derived from the official upstream container with repo-owned runtime settings in `configs/shared/opencode/opencode-settings-shared.conf` and the thin wrapper image contract in `configs/shared/opencode/Containerfile`.

The shared scripts are intended to work on both macOS and Linux hosts.

The official upstream container is the base image. The paths and lifecycle documented here are this wrapper repo's convention.

## Commands

- Build the image: `scripts/shared/opencode/opencode-build`
- Start a configured workspace: `scripts/shared/opencode/opencode-run`
- Open a shell or run a command in a running project container: `scripts/shared/opencode/opencode-shell <workspace> <project> [command...]`

`opencode-shell <workspace> <project>` opens `nu` by default.

`opencode-shell <workspace> <project> [command...]` runs the command directly inside the project container.

`scripts/shared/opencode/opencode-build` only runs from a clean committed checkout. It requires an attached branch HEAD. On `main`, it also requires `main` to track `origin/main` and `main` to be pushed and in sync with `origin/main`. A clean committed local branch without an upstream remains allowed.

## Host To Container Mappings

For a selected workspace named `WORKSPACE` and project `PROJECT`, the run script creates these host paths under `OPENCODE_BASE_PATH`, which defaults to `$HOME/Documents/Ezirius/.applications-data/.containers-artificial-intelligence`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-home`
- Host workspace path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-general`

The shared runtime container mappings are:

- Host home path -> `/root`
- Host workspace path -> `/workspace/general`
- `$HOME/Documents/Ezirius/Development/OpenCode` -> `/workspace/projects`

The project container mappings are:

- Host home path -> `/root`
- Host workspace path -> `/workspace/general`
- `$HOME/Documents/Ezirius/Development/OpenCode` -> `/workspace/development`
- Selected project root -> `/workspace/project`

The default in-container working directory is `/workspace/project`.

## Shell And Server Defaults

- `opencode-shell` prompts for workspace and project, then opens `nu` by default.
- `opencode-shell <workspace>` prompts for project, then opens `nu` by default.
- `opencode-shell <workspace> <project>` opens `nu` by default.
- `opencode-shell <workspace> <project> [command...]` runs the command directly inside the project container.
- `opencode-shell` can still attach to an explicitly selected running project container even when the matching host project directory no longer exists.
- `opencode-run` first ensures a shared per-workspace runtime container is running `serve --hostname $OPENCODE_SERVER_HOSTNAME --port $OPENCODE_SERVER_PORT`.
- The shared runtime container is the published browser server for the workspace.
- That shared runtime container mounts the host development root at `/workspace/projects` and owns the published host port `OPENCODE_SERVER_PORT + workspace offset`.
- Each project container runs a private local OpenCode server for its selected project and attaches to that server at `http://$OPENCODE_ATTACH_HOST:$OPENCODE_SERVER_PORT`.
- Project containers do not publish host ports; they run their own `serve --hostname $OPENCODE_SERVER_HOSTNAME --port $OPENCODE_SERVER_PORT` process and attach to `http://$OPENCODE_ATTACH_HOST:$OPENCODE_SERVER_PORT` inside the project container.
- `opencode-run` opens the published server URL in the default browser on macOS and Linux only when it creates or starts the shared runtime container.

## Naming

- Built images are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`.
- Shared runtime containers are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-infrastructure`.
- Project containers are named `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<project>`.
- New shared and project containers are created directly with their final canonical names.

## Runtime Pin

- Upstream base image: `ghcr.io/anomalyco/opencode:1.14.25`
- Configured internal server port: `OPENCODE_SERVER_PORT`, currently `4096`
- Configured in-container serve hostname: `OPENCODE_SERVER_HOSTNAME`, currently `0.0.0.0`
- Configured in-container attach host: `OPENCODE_ATTACH_HOST`, currently `127.0.0.1`
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
