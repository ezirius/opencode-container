# OpenCode container usage

## Workflow

Recommended one-step workflow:

1. Start or reuse the workspace container and open OpenCode:
   `./scripts/shared/bootstrap <workspace-name>`

`bootstrap` runs `opencode-build`, then `opencode-upgrade`, then `opencode-start`, then `opencode-open`, so it will:

- build the image only if it does not already exist
- upgrade the image only if the requested Ubuntu or OpenCode version has changed
- start the container if it is not running yet
- leave the container alone if it is already running on the current image
- recreate the container if the local image changed since the current container was created
- then open OpenCode in that running container

Any extra arguments after the workspace are forwarded to `opencode`.

Example:

```bash
./scripts/shared/bootstrap general --help
```

Manual workflow:

1. Build the shared image:
   `./scripts/shared/opencode-build`
2. Upgrade the shared image if newer configured versions are available:
   `./scripts/shared/opencode-upgrade`
3. Start a workspace container:
   `./scripts/shared/opencode-start <workspace-name>`
4. Open OpenCode interactively:
   `./scripts/shared/opencode-open <workspace-name>`

`opencode-start` does not build the image.
If the image is missing, it fails and tells you to run `./scripts/shared/opencode-build` first.
If the container is already running on the current local image, it leaves it alone.
If a stopped container already exists on the current local image, it starts that container again.
If the current local image differs from the running container image, it recreates the container from the local image.

`opencode-upgrade` compares the current image metadata with the requested Ubuntu and OpenCode versions.
If they already match, it exits without making changes.
If they differ, it removes the shared image and rebuilds it.

`opencode-start` requires an ARM64 host.
`opencode-build` and `opencode-upgrade` require an ARM64 host only when a build or rebuild is actually needed.

## Other commands

- Open a shell in the running container:
  `./scripts/shared/opencode-shell <workspace-name>`
- Show container logs:
  `./scripts/shared/opencode-logs <workspace-name>`
- Stop the container:
  `./scripts/shared/opencode-stop <workspace-name>`
- Remove the container:
  `./scripts/shared/opencode-remove <workspace-name>`

`opencode-stop` exits cleanly if the container is already stopped, and `opencode-remove` exits cleanly if the container does not exist.

`opencode-open` and `opencode-shell` keep TTY mode when run interactively and fall back to stdin-only mode when run from a non-interactive shell.

The repository test entry point is `./tests/shared/test-all.sh`.

## Workspace layout

Each workspace is expected to have this host layout:

- workspace root
- `configurations/`
- `data/`

The container mounts them as:

- workspace root -> `/workspace`
- `configurations/` -> `/configurations`
- `data/` -> `/data`

## Environment overrides

- `OPENCODE_BASE_ROOT`
  - base directory used when you pass a workspace name
  - default: `~/Documents/Ezirius/.applications-data/OpenCode`
  - named workspaces must be a single directory name such as `general`, not a relative path like `team/general`
- `OPENCODE_IMAGE_NAME`
  - image name used for build and run commands
- `OPENCODE_VERSION`
  - version passed to the Docker build for `opencode-ai`
  - default: `latest`
- `UBUNTU_VERSION`
  - Ubuntu release passed to the Docker build
  - default: `latest-lts`

## Version behaviour

- By default, `UBUNTU_VERSION=latest-lts` and `OPENCODE_VERSION=latest` in `lib/shell/common.sh`.
- `opencode-build` resolves the current Ubuntu LTS Docker tag series at build time and resolves the latest `opencode-ai` release from npm when the image is missing.
- `opencode-build` uses `--pull=always` when a build is needed, so the latest matching Ubuntu base image is pulled before building.
- `opencode-build` requires network access only when the image is missing and a build is needed.
- `opencode-build` labels the image with the resolved Ubuntu and OpenCode versions.
- `opencode-upgrade` compares those labels to the currently requested versions and rebuilds only when they differ.
- `opencode-start` uses the current local image only and does not rebuild it.
- If the image already exists, `opencode-build` reports that and exits without rebuilding.
- `bootstrap` performs the `build -> upgrade -> start -> open` flow.
- You can pin versions explicitly by setting `UBUNTU_VERSION` or `OPENCODE_VERSION` in your shell before running the scripts.
- `opencode-build` only enforces the ARM64 host requirement when it is about to build.
- `opencode-upgrade` only enforces the ARM64 host requirement when it is about to rebuild.

Example pinned build:

```bash
UBUNTU_VERSION=24.04 OPENCODE_VERSION=1.2.27 ./scripts/shared/bootstrap general
```

Example portable setup with a custom base root:

```bash
export OPENCODE_BASE_ROOT="$HOME/workspaces/opencode"
./scripts/shared/bootstrap general
```

Example matching the built-in default:

```bash
export OPENCODE_BASE_ROOT="$HOME/Documents/Ezirius/.applications-data/OpenCode"
./scripts/shared/bootstrap general
```

Named workspaces under different `OPENCODE_BASE_ROOT` values also get different container names because the resolved workspace path is part of the container identity.
