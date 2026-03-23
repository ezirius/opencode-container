# OpenCode container

This repository builds and manages a workspace-scoped OpenCode container for Apple Silicon hosts using Podman.

## Layout

- `config/container/Dockerfile` defines the shared ARM64 image
- `docs/usage.md` documents the container workflow and environment overrides
- `lib/opencode/common.sh` contains shared shell helpers and defaults
- `scripts/` contains build, start, open, shell, logs, stop, and remove commands
- `tests/test-layout.sh` contains lightweight repository checks

## Quickstart

Run these in order:

1. `./scripts/opencode-build`
2. `./scripts/opencode-start <workspace-name-or-path>`
3. `./scripts/opencode-open <workspace-name-or-path>`

`opencode-start` also builds the image automatically if it does not exist yet.

Useful follow-up commands:

- `./scripts/opencode-shell <workspace-name-or-path>`
- `./scripts/opencode-logs <workspace-name-or-path>`
- `./scripts/opencode-stop <workspace-name-or-path>`
- `./scripts/opencode-remove <workspace-name-or-path>`

## Container rules

- Apple Silicon host -> ARM64 container only
- No AMD64 fallback
- Shared image, separate container per workspace
- Workspace is mounted to `/workspace`
- Workspace `configurations/` is mounted to `/configurations`
- Workspace `data/` is mounted to `/data`

## Portability

The scripts accept either a workspace name or an absolute workspace path.

- If you pass an absolute path, that path is used directly
- If you pass a workspace name, it is resolved under `OPENCODE_BASE_ROOT`
- Default overrides are documented in `docs/usage.md`

The default workspace base root is `~/Documents/OpenCode`.

For a portable setup, prefer setting `OPENCODE_BASE_ROOT` explicitly in your shell profile rather than relying on the default path.

The default OpenCode package version is controlled by `OPENCODE_VERSION` in `lib/opencode/common.sh` and can be overridden at runtime.
