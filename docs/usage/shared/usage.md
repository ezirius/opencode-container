# OpenCode Wrapper Usage

This repo builds and runs a local OpenCode container with all repo-owned settings kept in `config/agent/shared/opencode-settings-shared.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

## Commands

- Build the image: `scripts/agent/shared/opencode-build`
- Start a configured workspace: `scripts/agent/shared/opencode-run`
- Open a shell in a running workspace container: `scripts/agent/shared/opencode-shell`

## Host To Container Mappings

For a selected workspace named `WORKSPACE` and project `PROJECT`, the run script creates these host paths under `OPENCODE_BASE_PATH`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-home`
- Host workspace path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-general`

The container mappings are:

- Host home path -> `/home/opencode`
- Host workspace path -> `/workspace/general`
- `OPENCODE_DEVELOPMENT_ROOT` -> `/workspace/development`
- Selected project root -> `/workspace/project`

The default in-container working directory is `/workspace/project`.

## Workspace Safety

When `opencode-run` starts a replacement container for a workspace, it does not remove existing workspace containers until the replacement container has started successfully.

If the selected workspace already has a matching container for the newest image and mounted project, the wrapper reuses it. If the exact matching container is stopped, the wrapper starts it before attaching to OpenCode.
