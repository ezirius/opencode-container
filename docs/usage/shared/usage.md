# OpenCode Wrapper Usage

This repo builds and runs a local OpenCode container with all repo-owned settings kept in `config/agent/shared/opencode-settings-shared.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

The official upstream image is a minimal CLI container. The paths and lifecycle documented here are this wrapper repo's convention.

For local builds, this wrapper consumes pinned public upstream musl CLI assets and stages them into local build-context paths for the Alpine `Containerfile`.

## Commands

- Build the image: `scripts/agent/shared/opencode-build`
- Start a configured workspace: `scripts/agent/shared/opencode-run`
- Open a shell in a running workspace container: `scripts/agent/shared/opencode-shell`

## Host To Container Mappings

For a selected workspace named `WORKSPACE` and project `PROJECT`, the run script creates these host paths under `OPENCODE_BASE_PATH`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-home`
- Host workspace path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/opencode-general`

The container mappings are:

- Host home path -> `/root`
- Host workspace path -> `/workspace/general`
- `OPENCODE_DEVELOPMENT_ROOT` -> `/workspace/development`
- Selected project root -> `/workspace/project`

The default in-container working directory is `/workspace/project`.

## Shell And Server Defaults

- `opencode-shell` opens `nu` by default.
- `opencode-run` starts `serve --hostname 0.0.0.0 --port 4096` inside the long-lived workspace container.
- `opencode-run` then opens `opencode attach http://127.0.0.1:4096` inside that same container so the interactive session uses the long-lived server.
- When passed `--publish`, `opencode-run` publishes host port `4096 + workspace offset`, so workspace `ezirius:10000` maps to host port `14096`.
- When passed `--publish`, `opencode-run` also opens the published server URL in the default browser on macOS and Linux.

## Build Inputs

Pinned public upstream musl CLI assets come from shared config, for example:

- `opencode-linux-x64-baseline-musl.tar.gz`
- `opencode-linux-arm64-musl.tar.gz`

Those public asset names are staged into local build-context paths:

- `dist/opencode-linux-x64-baseline-musl/bin/opencode`
- `dist/opencode-linux-arm64-musl/bin/opencode`

## Workspace Safety

When `opencode-run` starts a replacement container for a workspace, it does not remove existing workspace containers until the replacement container has started successfully.

If the selected workspace already has a matching container for the newest image and mounted project, the wrapper reuses it. If the exact matching container is stopped, the wrapper starts it before attaching to OpenCode.

When the selected project changes, the wrapper stages a staged `-next-<pid>` replacement container, waits for it to stay healthy, then renames it back to the canonical workspace container name.
