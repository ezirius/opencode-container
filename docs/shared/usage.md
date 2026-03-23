# OpenCode container usage

## Workflow

Run these in order:

1. Build the shared image:
   `./scripts/shared/opencode-build`
2. Start a workspace container:
   `./scripts/shared/opencode-start <workspace-name-or-path>`
3. Open OpenCode interactively:
   `./scripts/shared/opencode-open <workspace-name-or-path>`

`opencode-start` automatically builds the image first when it is missing.

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
- `OPENCODE_PLATFORM`
  - container platform, defaulting to `linux/arm64`
- `OPENCODE_VERSION`
  - version passed to the Docker build for `opencode-ai`
  - default: `1.2.27`

Example portable setup with a custom base root:

```bash
export OPENCODE_BASE_ROOT="$HOME/workspaces/opencode"
./scripts/shared/opencode-start general
```

Example matching the built-in default:

```bash
export OPENCODE_BASE_ROOT="$HOME/Documents/Ezirius/.applications-data/OpenCode"
./scripts/shared/opencode-start general
```

Example using an absolute workspace path:

```bash
./scripts/shared/opencode-start "$HOME/work/projects/general"
./scripts/shared/opencode-open "$HOME/work/projects/general"
```

When you start a container with an absolute workspace path, reuse that same absolute path for `opencode-open`, `opencode-shell`, `opencode-logs`, `opencode-stop`, and `opencode-remove`.

Absolute workspace paths with the same basename still get different container names, so `/path/one/general` and `/path/two/general` do not collide.

Trailing slashes on workspace paths are normalized, so `/path/one/general` and `/path/one/general/` resolve to the same workspace and container name.
