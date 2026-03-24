# OpenCode container usage

## Workflow

Recommended one-step workflow:

1. Start or reuse the workspace container and open OpenCode:
   `./scripts/shared/bootstrap <workspace-name-or-path>`

`bootstrap` runs `opencode-build`, then `opencode-start`, then `opencode-open`, so it will:

- refresh the image to the latest configured versions
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
2. Start a workspace container:
   `./scripts/shared/opencode-start <workspace-name-or-path>`
3. Open OpenCode interactively:
   `./scripts/shared/opencode-open <workspace-name-or-path>`

`opencode-start` does not build the image.
If the image is missing, it fails and tells you to run `./scripts/shared/opencode-build` first.
If the container is already running on the current local image, it leaves it alone.
If the current local image differs from the running container image, it recreates the container from the local image.

`opencode-build` and `opencode-start` require an ARM64 host.

## Other commands

- Open a shell in the running container:
  `./scripts/shared/opencode-shell <workspace-name-or-path>`
- Show container logs:
  `./scripts/shared/opencode-logs <workspace-name-or-path>`
- Stop the container:
  `./scripts/shared/opencode-stop <workspace-name-or-path>`
- Remove the container:
  `./scripts/shared/opencode-remove <workspace-name-or-path>`

`opencode-open` and `opencode-shell` keep TTY mode when run interactively and fall back to stdin-only mode when run from a non-interactive shell.

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
  - base directory used when you pass a workspace name instead of an absolute path
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
- `opencode-build` resolves the current Ubuntu LTS version at build time and resolves the latest `opencode-ai` release from npm.
- `opencode-build` uses `--pull=always`, so the latest matching Ubuntu base image is pulled before building.
- `opencode-build` requires network access to resolve the latest Ubuntu LTS release and the latest `opencode-ai` release.
- `opencode-start` uses the current local image only and does not rebuild it.
- `bootstrap` performs the full `build -> start -> open` flow.
- You can pin versions explicitly by setting `UBUNTU_VERSION` or `OPENCODE_VERSION` in your shell before running the scripts.

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

Example using an absolute workspace path:

```bash
./scripts/shared/bootstrap "$HOME/work/projects/general"
```

Container names are derived from the resolved workspace path. Equivalent absolute paths such as `/tmp/workspace`, `/tmp/./workspace`, and `/tmp/dir/../workspace` resolve to the same container.

Absolute workspace paths with the same basename still get different container names, so `/path/one/general` and `/path/two/general` do not collide.

Trailing slashes on workspace paths are normalized, so `/path/one/general` and `/path/one/general/` resolve to the same workspace and container name.

Named workspaces under different `OPENCODE_BASE_ROOT` values also get different container names because the resolved workspace path is part of the container identity.
