# OpenCode container

This repository builds and manages a workspace-scoped OpenCode container for ARM64 hosts, including Apple Silicon systems, using Podman.

## Layout

- `config/containers/Dockerfile` defines the shared ARM64 image
- `docs/shared/usage.md` documents the shared container workflow and environment overrides
- `lib/shell/common.sh` contains shared shell helpers and defaults
- `scripts/shared/` contains the shared build, start, open, shell, logs, stop, and remove commands
- `tests/shared/test-layout.sh` contains lightweight repository checks

## Quickstart

Run these in order:

1. `./scripts/shared/opencode-build`
2. `./scripts/shared/opencode-start <workspace-name-or-path>`
3. `./scripts/shared/opencode-open <workspace-name-or-path>`

`opencode-start` also builds the image automatically if it does not exist yet.

Useful follow-up commands:

- `./scripts/shared/opencode-shell <workspace-name-or-path>`
- `./scripts/shared/opencode-logs <workspace-name-or-path>`
- `./scripts/shared/opencode-stop <workspace-name-or-path>`
- `./scripts/shared/opencode-remove <workspace-name-or-path>`

## Container rules

- ARM64 host -> ARM64 container only
- No AMD64 fallback
- Shared image, separate container per workspace
- Workspace is mounted to `/workspace`
- Workspace `configurations/` is mounted to `/configurations`
- Workspace `data/` is mounted to `/data`

`opencode-build` and `opencode-start` now fail fast on non-ARM64 hosts.

## Portability

The scripts accept either a workspace name or an absolute workspace path.

- If you pass an absolute path, that path is used directly
- Trailing slashes on workspace paths are normalized away
- If you pass a workspace name, it is resolved under `OPENCODE_BASE_ROOT`
- If you use different absolute paths that share the same basename, they still get distinct container names
- If you start a container with an absolute path, use that same absolute path for follow-up commands so they target the same container
- Default overrides are documented in `docs/shared/usage.md`

The default workspace base root is `~/Documents/Ezirius/.applications-data/OpenCode`.

For a portable setup, prefer setting `OPENCODE_BASE_ROOT` explicitly in your shell profile rather than relying on the default path.

The default OpenCode package version is controlled by `OPENCODE_VERSION` in `lib/shell/common.sh` and can be overridden at runtime.
