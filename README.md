# OpenCode Container

This repository runs OpenCode in a wrapper-owned Ubuntu LTS container using the same local-container model used by `hindsight-container`:

- immutable local wrapper images
- deterministic workspace container names
- picker-based workspace commands
- persistent OpenCode runtime home at the configured `OPENCODE_CONTAINER_RUNTIME_HOME`
- wrapper-owned workspace config under the configured `OPENCODE_WORKSPACE_CONFIG_SUBDIR`

## Layout

- `config/shared/opencode.conf` contains wrapper defaults
- `config/containers/Containerfile.wrapper` builds the owned Ubuntu runtime for stable OpenCode releases
- `config/containers/entrypoint.sh` snapshots wrapper runtime env on container start
- `docs/shared/usage.md` documents the command surface and workspace model
- `docs/shared/implementation-plan.md` records the original implementation design and migration intent
- `lib/shell/common.sh` contains shared wrapper helpers
- `scripts/shared/` contains the shared commands
- `tests/shared/` contains the shell test suite

## Commands

Build immutable images:

1. `./scripts/shared/opencode-build <production|test> [upstream]`

If the lane is omitted, the wrapper prompts for the configured production or test lane. If `upstream` is omitted, the wrapper prompts for an upstream version.

Workspace commands:

1. `./scripts/shared/opencode-bootstrap [<workspace>] [opencode args...]`
2. `./scripts/shared/opencode-start [<workspace>]`
3. `./scripts/shared/opencode-start [<workspace>] -- [opencode args...]`
4. `./scripts/shared/opencode-start [<workspace>] <production|test> <upstream> [opencode args...]`
5. `./scripts/shared/opencode-start [<workspace>] <production|test> <upstream> -- [opencode args...]`
6. `./scripts/shared/opencode-open [<workspace>] [opencode args...]`
7. `./scripts/shared/opencode-open [<workspace>] -- [opencode args...]`
8. `./scripts/shared/opencode-open [<workspace>] <production|test> <upstream> [opencode args...]`
9. `./scripts/shared/opencode-open [<workspace>] <production|test> <upstream> -- [opencode args...]`
10. `./scripts/shared/opencode-shell [<workspace>] [command args...]`
11. `./scripts/shared/opencode-shell [<workspace>] -- [command args...]`
12. `./scripts/shared/opencode-shell [<workspace>] <production|test> <upstream> [command args...]`
13. `./scripts/shared/opencode-shell [<workspace>] <production|test> <upstream> -- [command args...]`
14. `./scripts/shared/opencode-logs [<workspace>] [podman logs args...]`
15. `./scripts/shared/opencode-status [<workspace>]`
16. `./scripts/shared/opencode-stop [<workspace>]`
17. `./scripts/shared/opencode-remove`
18. `./scripts/shared/opencode-remove containers`
19. `./scripts/shared/opencode-remove images`

If `<workspace>` is omitted, the wrapper lists workspace names from `OPENCODE_BASE_ROOT` in alphabetical order and prompts you to choose one. Use a leading `--` when you want the picker first and the remaining arguments begin with wrapper selectors or option flags.

## Version Model

Accepted upstream selectors:

- `main`
- `latest`
- exact release tags such as `1.4.3`

Rules:

- `main` builds from upstream source
- exact stable releases install the official OpenCode release into the wrapper-owned Ubuntu runtime
- `latest` resolves to the newest stable official release before naming
- prerelease, beta, preview, rc, nightly, and other non-stable releases are not selected by default

Wrapper-owned defaults such as the Ubuntu LTS base version are pinned in `config/shared/opencode.conf`.
Builds currently notify when a newer Ubuntu LTS exists, but they continue using the pinned value until it is deliberately updated.

Image identity:

- `opencode-local:<lane>-<upstream>-<wrapper>-<commitstamp>`

Container identity:

- `opencode-<workspace>-<lane>-<upstream>-<wrapper>`

## Workspace Layout

Each workspace lives under:

- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_HOME_DIRNAME>`
- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_DIRNAME>`
- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>`

Directory mappings:

- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_HOME_DIRNAME>` -> `OPENCODE_CONTAINER_RUNTIME_HOME`
- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_DIRNAME>` -> `OPENCODE_CONTAINER_WORKSPACE_DIR`
- `OPENCODE_BASE_ROOT/<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>` -> `OPENCODE_CONTAINER_WORKSPACE_DIR/OPENCODE_WORKSPACE_CONFIG_SUBDIR`
- `OPENCODE_DEVELOPMENT_ROOT` -> `OPENCODE_CONTAINER_DEVELOPMENT_DIR` when that host path exists

OpenCode-native state remains app-owned inside that runtime home, including locations such as:

- `~/.config/opencode`
- `~/.local/share/opencode`
- `~/.local/state/opencode`
- `~/.cache/opencode`

## Wrapper Config

Wrapper defaults live in `config/shared/opencode.conf`.

Wrapper runtime files live in:

- `config/shared/opencode.conf`
- `<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>/config.env`
- `<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>/secrets.env`

File roles:

- `config/shared/opencode.conf` stores wrapper-wide defaults and operational constants for all workspaces on that machine
- `config.env` stores workspace-scoped non-secret wrapper settings
- `secrets.env` stores workspace-scoped secret wrapper settings

Wrapper files used at runtime:

- `config/containers/entrypoint.sh` reads `config.env` first and then `secrets.env`
- `config/shared/opencode.conf` provides wrapper defaults such as path layout, lane names, label keys, upstream selector defaults, and managed-server settings
- `<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>/config.env` provides workspace-scoped non-secret wrapper environment assignments
- `<workspace>/<OPENCODE_WORKSPACE_DIRNAME>/<OPENCODE_WORKSPACE_CONFIG_SUBDIR>/secrets.env` optionally overrides matching values from `config.env`

Rules:

- `opencode.conf` is wrapper-only, not OpenCode app config
- `opencode.conf` is for wrapper-wide defaults, not workspace runtime overrides
- host directory roots and canonical in-container path layout are defined once in `config/shared/opencode.conf`
- `config.env` is seeded automatically as an optional starter file
- `secrets.env` is optional
- `config.env` and `secrets.env` are parsed as environment assignments and are not executed as shell scripts
- `secrets.env` overrides matching keys from `config.env`
- changing wrapper config or secrets requires stop/start only
- changing wrapper config or secrets must not require rebuild

Example intent:

- `config.env`: `OPENCODE_HOST_SERVER_PORT=<host-port>`, `OPENCODE_MODEL=...`
- `secrets.env`: API keys, tokens, passwords, and other secrets only

If `OPENCODE_HOST_SERVER_PORT` is set for a workspace, the wrapper starts `opencode serve --hostname "$OPENCODE_MANAGED_SERVER_HOSTNAME" --port "$OPENCODE_MANAGED_SERVER_CONTAINER_PORT"` inside the container and publishes that internal port to `127.0.0.1` on the host.

- if `OPENCODE_HOST_SERVER_PORT` is set, that exact host port is used
- if `OPENCODE_HOST_SERVER_PORT` is unset, the wrapper does not start a managed server and does not publish a server URL
- the wrapper-managed server contract is always host `<configured-port>` to container `OPENCODE_MANAGED_SERVER_CONTAINER_PORT`

`opencode-open` forwards trailing args into the in-container `opencode` command.

Use `--` when the first application or shell argument would otherwise look like a wrapper lane selector such as the configured lane names.

If you omit `<workspace>` for a workspace-facing command, the wrapper lists workspace names from `OPENCODE_BASE_ROOT` in alphabetical order and prompts you to choose one.

## Defaults

Default base root:

- `~/.local/share/opencode-container`

Default development root:

- `~/Development/OpenCode`

Environment variables override `config/shared/opencode.conf` at runtime.

## Runtime Image

The owned Ubuntu runtime is intentionally minimal.

It includes OpenCode plus the small apt-installed base needed for the wrapper image to run cleanly:

- `bash`
- `ca-certificates`
- `curl`
- `tar`
- `tini`

`OPENCODE_HOST_SERVER_PORT` is configured per workspace in `config.env` or `secrets.env`, not as a wrapper-global environment override.

Most operational constants now live in `config/shared/opencode.conf`, including path layout, label keys, lane names, upstream selector defaults, restart policy, and managed-server settings.

## Verification

Run:

- `tests/shared/test-all.sh`

Optional real-build smoke validation requires:

- `OPENCODE_ENABLE_SMOKE_BUILDS=1 tests/shared/test-build-smoke.sh`

## GitHub Setup On Maldoria

This repo uses the repo-specific SSH alias:

- `github-maldoria-opencode-container`

If `git push` says it cannot resolve that hostname, run:

- `/workspace/Development/OpenCode/installations-configurations/scripts/macos/git-configure`

Then verify with:

- `ssh -T git@github-maldoria-opencode-container`
