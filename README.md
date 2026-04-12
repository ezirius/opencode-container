# OpenCode Container

This repository wraps upstream OpenCode in the same local-container model used by `hindsight-container`:

- immutable local wrapper images
- deterministic workspace container names
- picker-based workspace commands
- persistent upstream-owned runtime home such as `/root` or `/home/opencode`
- wrapper-owned workspace config under `/workspace/opencode-workspace/.config/opencode`

## Layout

- `config/shared/opencode.conf` contains wrapper defaults
- `config/containers/Containerfile.wrapper` wraps upstream OpenCode images or source-built base images
- `config/containers/entrypoint.sh` snapshots wrapper runtime env on container start
- `docs/shared/usage.md` documents the command surface and workspace model
- `docs/shared/implementation-plan.md` is the source of truth for the architecture
- `lib/shell/common.sh` contains shared wrapper helpers
- `scripts/shared/` contains the shared commands
- `tests/shared/` contains the shell test suite

## Commands

Build immutable images:

1. `./scripts/shared/opencode-build <production|test> [upstream]`

Workspace commands:

1. `./scripts/shared/opencode-bootstrap <workspace> [opencode args...]`
2. `./scripts/shared/opencode-start <workspace>`
3. `./scripts/shared/opencode-start <workspace> -- [opencode args...]`
4. `./scripts/shared/opencode-start <workspace> <production|test> <upstream> [opencode args...]`
5. `./scripts/shared/opencode-start <workspace> <production|test> <upstream> -- [opencode args...]`
6. `./scripts/shared/opencode-open <workspace> [opencode args...]`
7. `./scripts/shared/opencode-open <workspace> -- [opencode args...]`
8. `./scripts/shared/opencode-open <workspace> <production|test> <upstream> [opencode args...]`
9. `./scripts/shared/opencode-open <workspace> <production|test> <upstream> -- [opencode args...]`
10. `./scripts/shared/opencode-shell <workspace> [command args...]`
11. `./scripts/shared/opencode-shell <workspace> -- [command args...]`
12. `./scripts/shared/opencode-shell <workspace> <production|test> <upstream> [command args...]`
13. `./scripts/shared/opencode-shell <workspace> <production|test> <upstream> -- [command args...]`
14. `./scripts/shared/opencode-logs <workspace> [podman logs args...]`
15. `./scripts/shared/opencode-status <workspace>`
16. `./scripts/shared/opencode-stop <workspace>`
17. `./scripts/shared/opencode-remove`
18. `./scripts/shared/opencode-remove containers`
19. `./scripts/shared/opencode-remove images`

## Version Model

Accepted upstream selectors:

- `main`
- `latest`
- exact release tags such as `1.4.3`

Rules:

- `main` builds from upstream source
- exact releases prefer `ghcr.io/anomalyco/opencode:<exact-tag>`
- if an exact release image is unavailable, the wrapper falls back to a source build
- `latest` resolves to the newest exact release before naming

Image identity:

- `opencode-local:<lane>-<upstream>-<wrapper>-<commitstamp>`

Container identity:

- `opencode-<workspace>-<lane>-<upstream>-<wrapper>`

## Workspace Layout

Each workspace lives under:

- `OPENCODE_BASE_ROOT/<workspace>/opencode-home`
- `OPENCODE_BASE_ROOT/<workspace>/opencode-workspace`
- `OPENCODE_BASE_ROOT/<workspace>/opencode-workspace/.config/opencode`

Directory mappings:

- `OPENCODE_BASE_ROOT/<workspace>/opencode-home` -> the upstream image runtime home, such as `/root` or `/home/opencode`
- `OPENCODE_BASE_ROOT/<workspace>/opencode-workspace` -> `/workspace/opencode-workspace`
- `OPENCODE_BASE_ROOT/<workspace>/opencode-workspace/.config/opencode` -> `/workspace/opencode-workspace/.config/opencode`
- `OPENCODE_DEVELOPMENT_ROOT` -> `/workspace/opencode-development`

OpenCode-native state remains upstream-owned inside that runtime home, including locations such as:

- `~/.config/opencode`
- `~/.local/share/opencode`
- `~/.local/state/opencode`
- `~/.cache/opencode`

## Wrapper Config

Wrapper defaults live in `config/shared/opencode.conf`.

Wrapper runtime files live in:

- `config/shared/opencode.conf`
- `opencode-workspace/.config/opencode/config.env`
- `opencode-workspace/.config/opencode/secrets.env`

File roles:

- `config/shared/opencode.conf` stores wrapper-wide defaults for all workspaces on that machine
- `config.env` stores workspace-scoped non-secret wrapper settings
- `secrets.env` stores workspace-scoped secret wrapper settings

Wrapper files used at runtime:

- `config/containers/entrypoint.sh` reads `config.env` first and then `secrets.env`
- `config/shared/opencode.conf` provides wrapper defaults such as `OPENCODE_BASE_ROOT` and `OPENCODE_DEVELOPMENT_ROOT`
- `opencode-workspace/.config/opencode/config.env` provides workspace-scoped non-secret wrapper environment assignments
- `opencode-workspace/.config/opencode/secrets.env` optionally overrides matching values from `config.env`

Rules:

- `opencode.conf` is wrapper-only, not OpenCode app config
- `opencode.conf` is for wrapper-wide defaults, not workspace runtime overrides
- `config.env` is seeded automatically as an optional starter file
- `secrets.env` is optional
- `config.env` and `secrets.env` are parsed as environment assignments and are not executed as shell scripts
- `secrets.env` overrides matching keys from `config.env`
- changing wrapper config or secrets requires stop/start only
- changing wrapper config or secrets must not require rebuild

Example intent:

- `config.env`: `OPENCODE_HOST_SERVER_PORT=4096`, `OPENCODE_MODEL=...`
- `secrets.env`: API keys, tokens, passwords, and other secrets only

If `OPENCODE_HOST_SERVER_PORT` is set for a workspace, the wrapper starts `opencode serve --hostname 0.0.0.0 --port 4096` inside the container and publishes that internal port to `127.0.0.1` on the host.

- if `OPENCODE_HOST_SERVER_PORT` is set, that exact host port is used
- if `OPENCODE_HOST_SERVER_PORT` is unset, the wrapper does not start a managed server and does not publish a server URL
- the wrapper-managed server contract is always host `<configured-port>` to container `4096`

`opencode-open` forwards trailing args into the in-container `opencode` command.

Use `--` when the first application or shell argument would otherwise look like a wrapper lane selector such as `test` or `production`.

## Defaults

Default base root:

- `~/.local/share/opencode-container`

Default development root:

- `~/Development/OpenCode`

Environment variables override `config/shared/opencode.conf` at runtime.

`OPENCODE_HOST_SERVER_PORT` is configured per workspace in `config.env` or `secrets.env`, not as a wrapper-global environment override.

## Verification

Run:

- `tests/shared/test-all.sh`

## GitHub Setup On Maldoria

This repo uses the repo-specific SSH alias:

- `github-maldoria-opencode-container`

If `git push` says it cannot resolve that hostname, run:

- `/workspace/Development/OpenCode/installations-configurations/scripts/macos/git-configure`

Then verify with:

- `ssh -T git@github-maldoria-opencode-container`
