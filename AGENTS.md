# AGENTS

This file defines the repository structure, naming rules, and safe-editing rules for agents creating or reorganizing content in this repo.

## Core Shape

- Repo-owned non-root files use exactly three directories below the repository base:
  `[repo base]/category/subcategory/scope/file`.
- `category` is the top-level bucket.
- `subcategory` is the functional family inside that category.
- `scope` describes OS applicability, shared applicability, or the dedicated superpowers plan area.
- Example: `[repo base]/scripts/agent/shared/opencode-run`.

## Allowed Scope Values

- `shared`
- `macos`
- `linux`
- `plans`

## Categories

- `config`
- `scripts`
- `tests`
- `docs`
- `lib`

## Canonical Subcategories For This Repo

- `config/agent/...`
- `config/containers/...`
- `scripts/agent/...`
- `tests/agent/...`
- `docs/usage/...`
- `docs/superpowers/...`
- `lib/shell/...`

## Config Filename Rule

The special filename convention applies only to files under `config/agent`.

Format:

```text
<subcategory>-<filejob>-<host>.<ext>
```

Examples:

- `config/agent/shared/opencode-settings-shared.conf`

`config/containers/shared/Containerfile` is the explicit exception because container tooling expects that filename.

## Script Naming Rule

- `opencode-build`
- `opencode-run`
- `opencode-shell`

## Required Comment Rules

- Shell-facing files under `scripts`, `lib`, and `tests` must explain themselves with comments.
- Each file must have a short header comment near the top.
- Each function must have a short comment directly above it.
- Each non-trivial block must have a short comment directly above it.

## Current Canonical Paths

- `config/agent/shared/opencode-settings-shared.conf`
- `config/containers/shared/Containerfile`
- `docs/superpowers/plans/2026-04-16-opencode-project-runtime-and-status.md`
- `docs/usage/shared/usage.md`
- `docs/usage/shared/architecture.md`
- `lib/shell/shared/common.sh`
- `scripts/agent/shared/opencode-build`
- `scripts/agent/shared/opencode-run`
- `scripts/agent/shared/opencode-shell`
- `tests/agent/shared/test-asserts.sh`
- `tests/agent/shared/test-all.sh`
- `tests/agent/shared/test-opencode-build.sh`
- `tests/agent/shared/test-opencode-layout.sh`
- `tests/agent/shared/test-opencode-run.sh`
- `tests/agent/shared/test-opencode-shell.sh`

## Root Files

- Keep `README.md` at the repository root.
- Keep `AGENTS.md` at the repository root.
- Keep `.dockerignore` at the repository root.

## Repository Ownership Rules

- Repo-owned runtime and build settings live in `config/agent/shared/opencode-settings-shared.conf`.
- The thin upstream-wrapper `Containerfile` lives in `config/containers/shared/Containerfile`.
- Shared shell helpers live in `lib/shell/shared/common.sh`.
- User-facing documentation lives in `docs/usage/shared/`.
- Shell tests live in `tests/agent/shared/`.
- `scripts/agent/shared/opencode-run` uses one shared published runtime per workspace plus private project containers.
- Shared interactive Podman exec behavior lives in `lib/shell/shared/common.sh`.
- Config belongs in config files, not in scripts or shell libraries.

## Build Behavior Rules

- `scripts/agent/shared/opencode-build` must only build from a clean, committed checkout.

## Build Context Rules

- Keep `.dockerignore` at the repository root.
- `.dockerignore` must exclude `.git`, `.git/`, `.worktrees/`, build/dist/temp/cache output, editor junk, and language cache files.
- `.dockerignore` must not exclude repo-owned source, config, scripts, docs, tests, or `config/containers/shared/Containerfile`.

## Development Workflow Rules

- Use TDD for behavior changes: write the failing test first, verify it fails for the expected reason, implement the minimal change, then verify it passes.
- Run `bash tests/agent/shared/test-all.sh` before claiming completion or committing.
- Shell tests mutate the shared config file, so run shell tests sequentially and never in parallel.
- Do not commit unless explicitly requested.
- Do not push unless explicitly requested.

## Agent Workflow Lessons

- Where documentation and implementation differ, correct documentation unless the implementation is clearly wrong.
- Use TDD for behavior and contract changes, including shell behavior and layout/docs assertions.
- For shell scripts, test the exact CLI contract with behavior tests and enforce documentation/static contracts with `test-opencode-layout.sh`.
- Negated `grep` checks under `set -e` must use explicit `if grep ...; then exit 1; fi` blocks.
- To prove a static layout assertion catches regressions, temporarily mutate the protected file, verify the test fails for that mutation, then remove the mutation before continuing.
- When a full verification command times out, rerun the same command with a longer timeout before reporting status.
- Request review after meaningful cleanup batches and address review findings with tests first.

## CLI Behavior Rules

- `scripts/agent/shared/opencode-run` accepts zero, one, or two arguments: `[workspace] [project]`.
- `scripts/agent/shared/opencode-run` must reject more than two arguments before workspace validation with `This script takes zero, one, or two arguments: [workspace] [project].`.
- `scripts/agent/shared/opencode-shell` accepts zero, one, two, or more arguments.
- For `opencode-shell`, the first argument is the workspace, the second argument is the project, and remaining arguments are run directly inside the project container.
- `opencode-shell` opens `OPENCODE_SHELL_COMMAND` only when no command arguments remain after workspace and project parsing.
- `opencode-shell <workspace> -- <command...>` treats `--` as the project token and must reject it as an unsafe project name.
- `opencode-shell` prompts for workspace and project when no args are supplied.
- `opencode-shell <workspace>` prompts for project.
- `opencode-shell <workspace> <project> [command...]` runs the command inside the project container when command arguments are supplied.
- `opencode-shell <workspace> <project> opencode -c` must run `opencode -c` directly in the project container, not open Nushell.
- Explicit shell project attachment should still work when the host project directory no longer exists, if a matching running container exists.

## Version Pin Rules

- The pinned OpenCode version lives in `config/agent/shared/opencode-settings-shared.conf`.
- Version bumps must update the config file, `config/containers/shared/Containerfile`, user docs, architecture docs, and all affected test fixtures.
- When bumping the pinned version, update stale-version warning fixtures so the `newer` fixture remains newer than the pin.
- `opencode-build` and `opencode-run` check the latest upstream OpenCode release; `opencode-shell` does not.
- OpenCode release lookup failures must not fail build or run.
- Version comparisons must compare numeric semver triplets, not strings.
- Newer-version warning color and pause behavior must be TTY-gated so non-interactive tests and automation keep plain, non-blocking stderr.

## Runtime Behavior Rules

- The wrapper uses a two-container runtime model: one shared published runtime per workspace plus private project containers.
- Shared runtime containers own published host ports.
- Project containers must not publish host ports.
- Shared runtime containers are created or started before project-container handling.
- Browser opening is limited to shared runtime creation or start.
- Containers must be created directly with canonical names; do not use staged names or `podman rename`.
- Existing project containers are reused unchanged when already running, or started unchanged when stopped.
- Container matching must verify mount paths to avoid workspace/project token collisions.
