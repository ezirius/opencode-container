# OpenCode Container

This repository wraps upstream OpenCode in the same local-container model used by `hindsight-container`:

- immutable local wrapper images
- deterministic workspace container names
- picker-based workspace commands
- persistent upstream-owned home under `/home/opencode`
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
3. `./scripts/shared/opencode-open <workspace> [opencode args...]`
4. `./scripts/shared/opencode-shell <workspace> [command args...]`
5. `./scripts/shared/opencode-logs <workspace> [podman logs args...]`
6. `./scripts/shared/opencode-status <workspace>`
7. `./scripts/shared/opencode-stop <workspace>`
8. `./scripts/shared/opencode-remove <container|image>`

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

Container mounts:

- `opencode-home` -> the upstream image runtime home, such as `/root` or `/home/opencode`
- `opencode-workspace` -> `/workspace/opencode-workspace`
- `$HOME/Documents/Ezirius/Development/OpenCode` -> `/workspace/opencode-development`

OpenCode-native state remains upstream-owned inside that runtime home, including locations such as:

- `~/.config/opencode`
- `~/.local/share/opencode`
- `~/.local/state/opencode`
- `~/.cache/opencode`

## Wrapper Config

Wrapper defaults live in `config/shared/opencode.conf`.

Wrapper runtime files live in:

- `opencode-workspace/.config/opencode/config.env`
- `opencode-workspace/.config/opencode/secrets.env`

Rules:

- `opencode.conf` is wrapper-only, not OpenCode app config
- `config.env` is seeded automatically as an optional starter file
- `secrets.env` is optional
- changing wrapper config or secrets requires stop/start only
- changing wrapper config or secrets must not require rebuild

If you run `opencode serve` or `opencode web` inside the container, the wrapper publishes container port `4096` to `127.0.0.1` on the host.

- if `OPENCODE_HOST_SERVER_PORT` is set, that exact host port is used
- if `OPENCODE_HOST_SERVER_PORT` is unset, Podman assigns a random available host port

`opencode-open` forwards trailing args into the in-container `opencode` command.

## Defaults

Default base root:

- `~/Documents/Ezirius/.applications-data/.containers-artificial-intelligence`

Environment variables override `config/shared/opencode.conf` at runtime.

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
