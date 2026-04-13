# OpenCode Container Usage

## Current Model

This wrapper now uses:

- immutable image tags
- deterministic container names
- picker-based workspace commands
- latest-stable-release-first builds into a wrapper-owned Ubuntu runtime
- source builds for upstream `main`
- no mutable shared-image upgrade flow

## Build

Use:

- `./scripts/shared/opencode-build <production|test> <upstream>`
- `./scripts/shared/opencode-build <production|test>`

Where:

- `lane` is `production` or `test`
- `upstream` is `main`, `latest`, or an exact release tag such as `1.4.3`

If `upstream` is omitted, the script builds the latest stable official OpenCode release.

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

- `./scripts/shared/opencode-bootstrap <workspace> [opencode args...]`
- `./scripts/shared/opencode-start <workspace>`
- `./scripts/shared/opencode-start <workspace> -- [opencode args...]`
- `./scripts/shared/opencode-start <workspace> <lane> <upstream> [opencode args...]`
- `./scripts/shared/opencode-start <workspace> <lane> <upstream> -- [opencode args...]`
- `./scripts/shared/opencode-open <workspace> [opencode args...]`
- `./scripts/shared/opencode-open <workspace> -- [opencode args...]`
- `./scripts/shared/opencode-open <workspace> <lane> <upstream> [opencode args...]`
- `./scripts/shared/opencode-open <workspace> <lane> <upstream> -- [opencode args...]`
- `./scripts/shared/opencode-shell <workspace> [command args...]`
- `./scripts/shared/opencode-shell <workspace> -- [command args...]`
- `./scripts/shared/opencode-shell <workspace> <lane> <upstream> [command args...]`
- `./scripts/shared/opencode-shell <workspace> <lane> <upstream> -- [command args...]`
- `./scripts/shared/opencode-logs <workspace> [podman logs args...]`
- `./scripts/shared/opencode-status <workspace>`
- `./scripts/shared/opencode-stop <workspace>`

Behavior:

- `opencode-bootstrap` picks a target once, starts or reuses it, then opens OpenCode in that same container
- `opencode-start` may select image-only targets or existing containers for the workspace
- `opencode-open`, `opencode-shell`, `opencode-logs`, `opencode-status`, and `opencode-stop` operate on existing containers only
- `opencode-open` forwards trailing args into `opencode`
- `opencode-shell` runs commands in `/workspace/opencode-workspace`
- use `--` when the first application or shell argument would otherwise look like a wrapper lane selector such as `test` or `production`

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

- for containers: keep the preferred container per workspace, where `production` wins over `test` and commit timestamp breaks ties within the same lane
- for images: keep the image serving each kept newest container
- in mixed mode: keep the preferred container per workspace and the image serving it

`All` in mixed mode removes all containers first and then all images.

## Workspace State

Each workspace uses:

- `<workspace-root>/opencode-home`
- `<workspace-root>/opencode-workspace`
- `<workspace-root>/opencode-workspace/.config/opencode`

Directory mappings are:

- `OPENCODE_BASE_ROOT/<workspace>/opencode-home` -> `/home/opencode`
- `OPENCODE_BASE_ROOT/<workspace>/opencode-workspace` -> `/workspace/opencode-workspace`
- `OPENCODE_BASE_ROOT/<workspace>/opencode-workspace/.config/opencode` -> `/workspace/opencode-workspace/.config/opencode`
- `OPENCODE_DEVELOPMENT_ROOT` -> `/workspace/opencode-development` when that host path exists

OpenCode remains responsible for its own home/state layout under that runtime home.

## Wrapper Runtime Config

Wrapper defaults are defined in `config/shared/opencode.conf`.
Pinned shared-tool versions are defined in `config/shared/tool-versions.conf`.

Workspace runtime files are:

- `config/shared/opencode.conf`
- `config/shared/tool-versions.conf`
- `config.env`
- `secrets.env`

File roles are:

- `config/shared/opencode.conf` for wrapper-wide defaults
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

- `config.env`: non-secret values such as `OPENCODE_HOST_SERVER_PORT=4096`
- `secrets.env`: API keys, tokens, passwords, and other secrets only

If `OPENCODE_HOST_SERVER_PORT` is set for a workspace, the wrapper starts `opencode serve --hostname 0.0.0.0 --port 4096` inside the container and publishes that internal port to host `127.0.0.1`.

- `OPENCODE_HOST_SERVER_PORT=<port>` uses a fixed host port
- if `OPENCODE_HOST_SERVER_PORT` is unset, the wrapper does not start a managed server and `opencode-status` does not show a server URL
- the wrapper-managed server contract is always host `<configured-port>` to container `4096`

## Environment Overrides

- `OPENCODE_BASE_ROOT`
- `OPENCODE_IMAGE_NAME`
- `OPENCODE_PROJECT_PREFIX`
- `OPENCODE_REPO_URL`
- `OPENCODE_GITHUB_API_BASE`
- `OPENCODE_NPM_REGISTRY_BASE`
- `OPENCODE_UBUNTU_LTS_VERSION`
- `OPENCODE_DEVELOPMENT_ROOT`

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

## Shared Toolbox

The owned Ubuntu runtime includes a standard shared toolbox:

- `git`
- `ripgrep`
- `fd`
- `python`
- `jq`
- `direnv`
- `just`
- `yq`
- `uv`
- `delta`
- `watchexec`
- `shellcheck`
- `podman`
- `eza`
- `bat`
- `zoxide`
- `xh`
- `gh`
- `jj`
- `wt`
- `worktrunk` symlink
- `basedpyright`
- `pytest`
- `ruff`
- `skopeo`
- `dive`
- `buildah`
- `age`
- `sops`
- `doggo`
- `grpcurl`
- `websocat`
- `podman-compose`
- `hyperfine`
- `duf`
- `lnav`
- `shfmt`
- `strace`
- `miller`
- `csvlens`
- `caddy`
- `tlrc`
