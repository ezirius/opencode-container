# OpenCode container

This repository builds and manages a workspace-scoped OpenCode container for ARM64 hosts, including Apple Silicon systems, using Podman.

## Layout

- `config/containers/Dockerfile` defines the shared ARM64 image
- `docs/shared/usage.md` documents the shared container workflow and environment overrides
- `lib/shell/common.sh` contains shared shell helpers and defaults
- `scripts/shared/` contains the shared `bootstrap`, build, upgrade, start, open, shell, logs, stop, and remove commands
- `tests/shared/` contains layout, helper, runtime-behaviour, and aggregate test runners

## Quickstart

Recommended:

1. `./scripts/shared/bootstrap <workspace-name-or-path>`

`bootstrap` ensures the image exists, upgrades it if newer configured versions are available, starts the workspace container if needed, recreates it if the local image changed, and then opens OpenCode.
Any extra arguments after the workspace are forwarded to `opencode`.

Example:

`./scripts/shared/bootstrap general --help`

Manual flow:

1. `./scripts/shared/opencode-build`
2. `./scripts/shared/opencode-upgrade`
3. `./scripts/shared/opencode-start <workspace-name-or-path>`
4. `./scripts/shared/opencode-open <workspace-name-or-path>`

`opencode-start` only starts or reuses a container from the existing local image.
If the container is already running on that same image, it exits cleanly.
If a stopped container already exists on that same image, it starts it again.
If the local image has changed since the container was started, it recreates the container from the current local image.
If the image does not exist, `opencode-start` fails and tells you to run `opencode-build` first.

`opencode-upgrade` checks the current image metadata against the requested Ubuntu and OpenCode versions.
If they already match, it makes no changes and exits cleanly.
If they differ, it removes the shared image and rebuilds it with the current requested versions.

Useful follow-up commands:

- `./scripts/shared/opencode-shell <workspace-name-or-path>`
- `./scripts/shared/opencode-logs <workspace-name-or-path>`
- `./scripts/shared/opencode-stop <workspace-name-or-path>`
- `./scripts/shared/opencode-remove <workspace-name-or-path>`

`opencode-stop` is also idempotent: if the container is already stopped, it reports that and exits cleanly.

## Container rules

- ARM64 host -> ARM64 container only
- No AMD64 fallback
- Shared image, separate container per workspace
- Workspace is mounted to `/workspace`
- Workspace `configurations/` is mounted to `/configurations`
- Workspace `data/` is mounted to `/data`

## Versioning

- By default, the first build resolves the latest supported Ubuntu LTS Docker tag series and the latest `opencode-ai` release at build time.
- `opencode-build` uses `--pull=always` when a build is needed, so the latest matching Ubuntu base image is pulled before building.
- `opencode-build` requires network access only when the image is missing and a build is needed.
- `opencode-build` labels the image with the resolved Ubuntu and OpenCode versions so `opencode-upgrade` can detect changes later.
- `opencode-upgrade` compares the current image labels with the currently requested Ubuntu and OpenCode versions.
- If the versions already match, `opencode-upgrade` exits without making changes.
- If the versions differ, `opencode-upgrade` removes the shared image and rebuilds it.
- `opencode-start` does not rebuild the image.
- If the image already exists, `opencode-build` reports that and exits without rebuilding.
- `bootstrap` performs the `build -> upgrade -> start -> open` flow.
- The Dockerfile keeps fallback defaults for `UBUNTU_VERSION=24.04` and `OPENCODE_VERSION=latest`, but the scripts resolve current values dynamically.
- You can still pin versions manually by setting `UBUNTU_VERSION` or `OPENCODE_VERSION` in the environment before running the scripts.
- `opencode-build` requires an ARM64 host only when an actual build is needed.
- `opencode-upgrade` requires an ARM64 host only when an actual rebuild is needed.

Example pinned build:

```bash
UBUNTU_VERSION=24.04 OPENCODE_VERSION=1.2.27 ./scripts/shared/bootstrap general
```

`opencode-start` always fails fast on non-ARM64 hosts.

## Portability

The scripts accept either a workspace name or an absolute workspace path.

- If you pass an absolute path, that path is used directly
- Workspace paths are normalized before naming the container, so trailing slashes and lexical segments like `.` and `..` do not create duplicates
- If you pass a workspace name, it is resolved under `OPENCODE_BASE_ROOT` and must be a single directory name, not a relative path
- Container names are derived from the resolved workspace path, so the same workspace name under different base roots does not collide
- If you use different absolute paths that share the same basename, they still get distinct container names
- If you start a container with an absolute path, follow-up commands can use equivalent normalized aliases for that same path and still target the same container
- Default overrides are documented in `docs/shared/usage.md`

The default workspace base root is `~/Documents/Ezirius/.applications-data/OpenCode`.

For a portable setup, prefer setting `OPENCODE_BASE_ROOT` explicitly in your shell profile rather than relying on the default path.

The default OpenCode package version policy is controlled by `OPENCODE_VERSION` in `lib/shell/common.sh` and can be overridden at runtime.

The default Ubuntu release policy is controlled by `UBUNTU_VERSION` in `lib/shell/common.sh` and can also be overridden at runtime.
