# OpenCode container usage

## Workflow

Run these in order:

1. Build the shared image:
   `./scripts/opencode-build`
2. Start a workspace container:
   `./scripts/opencode-start <workspace-name-or-path>`
3. Open OpenCode interactively:
   `./scripts/opencode-open <workspace-name-or-path>`

`opencode-start` automatically builds the image first when it is missing.

## Other commands

- Open a shell in the running container:
  `./scripts/opencode-shell <workspace-name-or-path>`
- Show container logs:
  `./scripts/opencode-logs <workspace-name-or-path>`
- Stop the container:
  `./scripts/opencode-stop <workspace-name-or-path>`
- Remove the container:
  `./scripts/opencode-remove <workspace-name-or-path>`

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
  - default: `~/Documents/OpenCode`
- `OPENCODE_IMAGE_NAME`
  - image name used for build and run commands
- `OPENCODE_PLATFORM`
  - container platform, defaulting to `linux/arm64`
- `OPENCODE_VERSION`
  - version passed to the Docker build for `opencode-ai`
  - default: `1.2.27`

Example portable setup:

```bash
export OPENCODE_BASE_ROOT="$HOME/Documents/OpenCode"
./scripts/opencode-start general
```

Example using an absolute workspace path:

```bash
./scripts/opencode-start "$HOME/work/projects/general"
```
