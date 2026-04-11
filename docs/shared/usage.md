# OpenCode Container Usage

## Current Model

This wrapper now uses:

- immutable image tags
- deterministic container names
- picker-based workspace commands
- official-image-first release builds with source fallback
- source builds for upstream `main`
- no mutable shared-image upgrade flow

## Build

Use:

- `./scripts/shared/opencode-build <production|test> <upstream>`
- `./scripts/shared/opencode-build <production|test>`

Where:

- `lane` is `production` or `test`
- `upstream` is `main`, `latest`, or an exact release tag such as `1.4.3`

If `upstream` is omitted, the script prompts with:

- `main`
- available upstream release tags, newest to oldest

Rules:

- `main` builds from upstream source
- exact releases prefer `ghcr.io/anomalyco/opencode:<exact-tag>`
- if an exact release image is unavailable, the wrapper falls back to source
- `latest` resolves to an exact release before naming
- the picker does not show floating `latest`

Production builds:

- must run from the canonical main checkout
- must be clean
- must have no unpushed commits

Test builds:

- may run from the canonical main checkout or a worktree
- must be clean

## Workspace Commands

The workspace-facing commands are:

- `./scripts/shared/opencode-bootstrap <workspace> [opencode args...]`
- `./scripts/shared/opencode-start <workspace>`
- `./scripts/shared/opencode-start <workspace> <lane> <upstream> [opencode args...]`
- `./scripts/shared/opencode-open <workspace> [opencode args...]`
- `./scripts/shared/opencode-open <workspace> <lane> <upstream> [opencode args...]`
- `./scripts/shared/opencode-shell <workspace> [command args...]`
- `./scripts/shared/opencode-shell <workspace> <lane> <upstream> [command args...]`
- `./scripts/shared/opencode-logs <workspace> [podman logs args...]`
- `./scripts/shared/opencode-status <workspace>`
- `./scripts/shared/opencode-stop <workspace>`

Behavior:

- `opencode-bootstrap` picks a target once, starts or reuses it, then opens OpenCode in that same container
- `opencode-start` may select image-only targets or existing containers for the workspace
- `opencode-open`, `opencode-shell`, `opencode-logs`, `opencode-status`, and `opencode-stop` operate on existing containers only
- `opencode-open` forwards trailing args into `opencode`
- `opencode-shell` runs commands in `/workspace/opencode-workspace`

## Remove

Use:

- `./scripts/shared/opencode-remove container`
- `./scripts/shared/opencode-remove image`

The menu supports:

1. `All, but newest`
2. `All`
3. individual targets

`All, but newest` means:

- for containers: keep the newest container per workspace
- for images: keep the newest image per workspace association inferred from current containers, or keep the newest image overall if no workspace association exists

## Workspace State

Each workspace uses:

- `<workspace-root>/opencode-home`
- `<workspace-root>/opencode-workspace`
- `<workspace-root>/opencode-workspace/.config/opencode`

Container mounts are:

- `opencode-home` -> the upstream image runtime home, such as `/root` or `/home/opencode`
- `opencode-workspace` -> `/workspace/opencode-workspace`
- `$HOME/Documents/Ezirius/Development/OpenCode` -> `/workspace/opencode-development`

OpenCode remains responsible for its own home/state layout under that runtime home.

## Wrapper Runtime Config

Wrapper defaults are defined in `config/shared/opencode.conf`.

Workspace runtime files are:

- `config.env`
- `secrets.env`

Rules:

- `config/shared/opencode.conf` is wrapper-only and not OpenCode-native config
- `config.env` is seeded automatically as a commented starter file
- `secrets.env` is optional
- changes to wrapper config or secrets require stop/start only
- changes to wrapper config or secrets must not require rebuild

If you run `opencode serve` or `opencode web` inside the container, the wrapper publishes container port `4096` to host `127.0.0.1`.

- `OPENCODE_HOST_SERVER_PORT=<port>` uses a fixed host port
- if `OPENCODE_HOST_SERVER_PORT` is unset, Podman assigns a random available host port
- `opencode-status` shows the mapped server URL

## Environment Overrides

- `OPENCODE_BASE_ROOT`
- `OPENCODE_IMAGE_NAME`
- `OPENCODE_PROJECT_PREFIX`
- `OPENCODE_REPO_URL`
- `OPENCODE_GHCR_IMAGE`
- `OPENCODE_GITHUB_API_BASE`
- `OPENCODE_HOST_SERVER_PORT`

For tests and automation, the wrapper also honors:

- `OPENCODE_SELECT_INDEX`
- `OPENCODE_COMMITSTAMP_OVERRIDE`
- `OPENCODE_SOURCE_OVERRIDE_DIR`
- `OPENCODE_SKIP_BUILD_CONTEXT_CHECK`

## Verification

Run:

- `./tests/shared/test-all.sh`
