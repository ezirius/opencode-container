# OpenCode Container Usage

## Current Model

This wrapper now uses:

- immutable image tags
- deterministic container names
- picker-based workspace commands
- latest-stable-release-first builds into a wrapper-owned Ubuntu runtime
- a minimal runtime image with OpenCode plus a small apt-installed base
- source builds for upstream `main`
- no mutable shared-image upgrade flow

## Build

Use:

- `./scripts/shared/opencode-build <production|test> <upstream>`
- `./scripts/shared/opencode-build <production|test>`
- `./scripts/shared/opencode-build`

Where:

- `lane` is the configured production or test lane name from `config/shared/opencode.conf`
- `upstream` is the configured main selector, the configured default selector, or an exact release tag such as `1.4.3`

If `lane` is omitted, the script prompts for the configured production or test lane.

If `upstream` is omitted, the script prompts for an upstream version. The upstream picker shows the configured main selector plus exact stable releases newest to oldest.

Rules:

- `main` builds from upstream source
- exact stable releases install the official OpenCode release into the wrapper-owned Ubuntu runtime
- `latest` resolves to an exact stable release before naming
- prerelease, beta, preview, rc, nightly, and other non-stable releases are not selected by default
- wrapper-owned defaults such as the Ubuntu LTS base version are pinned in config, checked for newer suitable versions during build, and only changed deliberately

Production builds:

- must run from the canonical main checkout
- must be clean
- must have no unpushed commits

Test builds:

- may run from the canonical main checkout or a worktree
- must be clean

## Workspace Commands

The workspace-facing commands are:

- `./scripts/shared/opencode-bootstrap [<workspace>] [opencode args...]`
- `./scripts/shared/opencode-start [<workspace>]`
- `./scripts/shared/opencode-start [<workspace>] -- [opencode args...]`
- `./scripts/shared/opencode-start [<workspace>] <lane> <upstream> [opencode args...]`
- `./scripts/shared/opencode-start [<workspace>] <lane> <upstream> -- [opencode args...]`
- `./scripts/shared/opencode-open [<workspace>] [opencode args...]`
- `./scripts/shared/opencode-open [<workspace>] -- [opencode args...]`
- `./scripts/shared/opencode-open [<workspace>] <lane> <upstream> [opencode args...]`
- `./scripts/shared/opencode-open [<workspace>] <lane> <upstream> -- [opencode args...]`
- `./scripts/shared/opencode-shell [<workspace>] [command args...]`
- `./scripts/shared/opencode-shell [<workspace>] -- [command args...]`
- `./scripts/shared/opencode-shell [<workspace>] <lane> <upstream> [command args...]`
- `./scripts/shared/opencode-shell [<workspace>] <lane> <upstream> -- [command args...]`
- `./scripts/shared/opencode-logs [<workspace>] [podman logs args...]`
- `./scripts/shared/opencode-status [<workspace>]`
- `./scripts/shared/opencode-stop [<workspace>]`

If `<workspace>` is omitted, these commands prompt with workspace names from `OPENCODE_BASE_ROOT` in alphabetical order.
Use a leading `--` when you want the workspace picker first and the remaining arguments begin with wrapper selectors or option flags.

Behavior:

- `opencode-bootstrap` picks a target once, starts or reuses it, then opens OpenCode in that same container
- `opencode-start` may select image-only targets or existing containers for the workspace
- `opencode-open`, `opencode-shell`, `opencode-logs`, `opencode-status`, and `opencode-stop` operate on existing containers only
- `opencode-open` forwards trailing args into `opencode`
- `opencode-shell` runs commands in `/workspace/opencode-workspace`
- use `--` when the first application or shell argument would otherwise look like a configured wrapper lane selector

## Remove

Use:

- `./scripts/shared/opencode-remove`
- `./scripts/shared/opencode-remove containers`
- `./scripts/shared/opencode-remove images`

The menu supports:

1. `All, but newest`
2. `All`
3. individual targets

With no argument, the mixed picker shows containers first and then images.

`All, but newest` means:

- for containers: keep the preferred container per workspace, where the configured production lane wins over the configured test lane and commit timestamp breaks ties within the same lane
- for images: keep the image serving each kept newest container
- in mixed mode: keep the preferred container per workspace and the image serving it

`All` in mixed mode removes all containers first and then all images.

## Workspace State

Each workspace uses:

- `<workspace-root>/<OPENCODE_WORKSPACE_HOME_DIRNAME>`
- `<workspace-root>/<OPENCODE_WORKSPACE_DIRNAME>`
- `<workspace-root>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>`

Directory mappings are:

- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_HOME_DIRNAME>` -> `OPENCODE_CONTAINER_RUNTIME_HOME`
- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_DIRNAME>` -> `OPENCODE_CONTAINER_WORKSPACE_DIR`
- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>` -> `OPENCODE_CONTAINER_WORKSPACE_DIR/OPENCODE_WORKSPACE_CONFIG_SUBDIR`
- `OPENCODE_DEVELOPMENT_ROOT` -> `OPENCODE_CONTAINER_DEVELOPMENT_DIR` when that host path exists

OpenCode remains responsible for its own home/state layout under that runtime home.

## Wrapper Runtime Config

Wrapper defaults are defined in `config/shared/opencode.conf`.

Workspace runtime files are:

- `config/shared/opencode.conf`
- `config.env`
- `secrets.env`

File roles are:

- `config/shared/opencode.conf` for wrapper-wide defaults, host roots, canonical in-container path layout, label keys, lane names, upstream selector defaults, and managed-server settings
- `config.env` for workspace-scoped non-secret wrapper settings
- `secrets.env` for workspace-scoped secret wrapper settings

Wrapper files used at runtime are:

- `config/shared/opencode.conf`
- `config/containers/entrypoint.sh`
- `<workspace-root>/opencode-workspace/.config/opencode/config.env`
- `<workspace-root>/opencode-workspace/.config/opencode/secrets.env`

Rules:

- `config/shared/opencode.conf` is wrapper-only and not OpenCode-native config
- `config/shared/opencode.conf` is for wrapper-wide defaults, not workspace runtime overrides
- wrapper-owned defaults such as the Ubuntu LTS base version are pinned in config and only changed deliberately
- the build currently checks the Ubuntu LTS pin for newer suitable versions and reports when it is behind
- `config.env` is seeded automatically as a commented starter file
- `secrets.env` is optional
- `config.env` and `secrets.env` are parsed as environment assignments and are not executed as shell scripts
- `secrets.env` overrides matching keys from `config.env`
- changes to wrapper config or secrets require stop/start only
- changes to wrapper config or secrets must not require rebuild

Example intent:

- `config.env`: non-secret values such as `OPENCODE_HOST_SERVER_PORT=<host-port>`
- `secrets.env`: API keys, tokens, passwords, and other secrets only

If `OPENCODE_HOST_SERVER_PORT` is set for a workspace, the wrapper starts `opencode serve --hostname "$OPENCODE_MANAGED_SERVER_HOSTNAME" --port "$OPENCODE_MANAGED_SERVER_CONTAINER_PORT"` inside the container and publishes that internal port to host `127.0.0.1`.

- `OPENCODE_HOST_SERVER_PORT=<port>` uses a fixed host port
- if `OPENCODE_HOST_SERVER_PORT` is unset, the wrapper does not start a managed server and `opencode-status` does not show a server URL
- the wrapper-managed server contract is always host `<configured-port>` to container `OPENCODE_MANAGED_SERVER_CONTAINER_PORT`

## Environment Overrides

- `OPENCODE_BASE_ROOT`
- `OPENCODE_IMAGE_NAME`
- `OPENCODE_PROJECT_PREFIX`
- `OPENCODE_REPO_URL`
- `OPENCODE_GITHUB_API_BASE`
- `OPENCODE_NPM_REGISTRY_BASE`
- `OPENCODE_UBUNTU_LTS_VERSION`
- `OPENCODE_DEVELOPMENT_ROOT`
- representative operational constants from `config/shared/opencode.conf`, such as lane names or upstream selector defaults

`OPENCODE_HOST_SERVER_PORT` is configured per workspace in `config.env` or `secrets.env`, not as a wrapper-global environment override.

For tests and automation, the wrapper also honors:

- `OPENCODE_SELECT_INDEX`
- `OPENCODE_COMMITSTAMP_OVERRIDE`
- `OPENCODE_SOURCE_OVERRIDE_DIR`
- `OPENCODE_SKIP_BUILD_CONTEXT_CHECK`

## Verification

Run:

- `./tests/shared/test-all.sh`

Optional real-build smoke checks can be enabled with:

- `OPENCODE_ENABLE_SMOKE_BUILDS=1 ./tests/shared/test-build-smoke.sh`

This requires a working `podman` environment and intentionally performs a real Ubuntu runtime build.

## Runtime Image

The owned Ubuntu runtime is intentionally minimal.

It includes OpenCode plus the small apt-installed base needed for the wrapper image to run cleanly:

- `bash`
- `ca-certificates`
- `curl`
- `tar`
- `tini`
