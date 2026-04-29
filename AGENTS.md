# AGENTS

This file defines the repository structure, naming rules, and safe-editing rules for agents creating or reorganizing content in this repo.

## Standing Reminders

- Always use British English.
- Always be concise.
- Always keep all code as simple as possible.
- Use tables where appropriate.
- Keep external values in config files for all scripts and shared libraries.
- Do not embed external values directly in scripts or shared libraries.
- Test files are the exception and may keep test-specific values inline.
- Always keep scripts, code, libraries, tests, configs, and docs well documented.

## Core Shape

- Repo-owned non-root files use exactly three directories below the repository base:
  `[repo base]/category/os/app-or-shared/file`.
- `category` is the top-level bucket.
- `os` describes host applicability.
- `app-or-shared` is the app name or `shared` when a file is reusable across apps.
- Example: `[repo base]/scripts/shared/opencode/opencode-run`.

## Allowed Category Values

- `configs`
- `scripts`
- `tests`
- `docs`
- `libs`

## Allowed Os Values

- `shared`
- `macos`
- `linux`

## App Values

- `opencode`
- `shared`

## Config Filename Rule

The special filename convention applies only to files under `configs/*/opencode`.

Format:

```text
<app>-<filejob>-<host>.<ext>
```

Examples:

- `configs/shared/opencode/opencode-settings-shared.conf`

`configs/shared/opencode/Containerfile` is the explicit exception because container tooling expects that filename.

## Script Naming Rule

- `opencode-build`
- `opencode-run`
- `opencode-shell`

## Required Comment Rules

- Shell-facing files under `scripts`, `libs`, and `tests` must explain themselves with comments.
- Each file must have a short header comment near the top.
- Each function must have a short comment directly above it.
- Each non-trivial block must have a short comment directly above it.

## Current Canonical Paths

- `configs/shared/opencode/opencode-settings-shared.conf`
- `configs/shared/opencode/Containerfile`
- `docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md`
- `docs/shared/opencode/usage.md`
- `docs/shared/opencode/architecture.md`
- `libs/shared/opencode/common.sh`
- `scripts/shared/opencode/opencode-build`
- `scripts/shared/opencode/opencode-run`
- `scripts/shared/opencode/opencode-shell`
- `tests/shared/shared/test-asserts.sh`
- `tests/shared/opencode/test-all.sh`
- `tests/shared/opencode/test-opencode-build.sh`
- `tests/shared/opencode/test-opencode-layout.sh`
- `tests/shared/opencode/test-opencode-run.sh`
- `tests/shared/opencode/test-opencode-shell.sh`

## Root Files

- Keep `README.md` at the repository root.
- Keep `AGENTS.md` at the repository root.
- Keep `.dockerignore` at the repository root.

## Repository Ownership Rules

- Repo-owned runtime and build settings live in `configs/shared/opencode/opencode-settings-shared.conf`.
- The thin upstream-wrapper `Containerfile` lives in `configs/shared/opencode/Containerfile`.
- Shared shell helpers live in `libs/shared/opencode/common.sh`.
- User-facing documentation lives in `docs/shared/opencode/`.
- Shell tests live in `tests/shared/opencode/`, with generic shared test helpers allowed in `tests/shared/shared/`.
- `scripts/shared/opencode/opencode-run` uses one shared published runtime per workspace plus private project containers.
- Shared interactive Podman exec behavior lives in `libs/shared/opencode/common.sh`.
- Config belongs in config files, not in scripts or shell libraries.

## Shared Code Rules

- Put reusable shell helpers in `libs/`.
- Keep script-specific orchestration in `scripts/<os>/<application>/`.
- If code is shared by both macOS and Linux, prefer `libs/shared/opencode/common.sh` first unless there is already a better-focused shared file.
- Do not move OpenCode-specific runtime or container business rules into shared libraries unless they are clearly reused across entrypoints.

## Build Behavior Rules

- `scripts/shared/opencode/opencode-build` must only build from a clean, committed checkout.

## Build Context Rules

- Keep `.dockerignore` at the repository root.
- `.dockerignore` must exclude `.git`, `.git/`, `.worktrees/`, build/dist/temp/cache output, editor junk, and language cache files.
- `.dockerignore` must not exclude repo-owned source, configs, scripts, docs, tests, libs, or `configs/shared/opencode/Containerfile`.

## Development Workflow Rules

- Prefer the smallest practical change.
- Use TDD for behavior changes: write the failing test first, verify it fails for the expected reason, implement the minimal change, then verify it passes.
- Update or add tests before changing behavior.
- Run `bash tests/shared/opencode/test-all.sh` before claiming completion or committing.
- Run shell syntax checks on changed scripts and libraries.
- Shell tests mutate the shared config file, so run shell tests sequentially and never in parallel.
- Prefer simple portable shell patterns over newer Bash-only features when a compatible alternative exists.
- Do not commit unless explicitly requested.
- Do not push unless explicitly requested.

## Agent Workflow Lessons

- Where documentation and implementation differ, correct documentation unless the implementation is clearly wrong.
- Use TDD for behavior and contract changes, including shell behavior and layout/docs assertions.
- For shell scripts, test the exact CLI contract with behavior tests and enforce documentation/static contracts with `tests/shared/opencode/test-opencode-layout.sh`.
- Prefer fake repo tests with stubbed system commands for shared script behavior.
- Cover interactive selection behavior, invalid input retries, EOF handling, and final command construction where relevant.
- Negated `grep` checks under `set -e` must use explicit `if grep ...; then exit 1; fi` blocks.
- To prove a static layout assertion catches regressions, temporarily mutate the protected file, verify the test fails for that mutation, then remove the mutation before continuing.
- When a full verification command times out, rerun the same command with a longer timeout before reporting status.
- Request review after meaningful cleanup batches and address review findings with tests first.

## Output Rules

- Use green for success and active selections.
- Use amber for warnings and skips.
- Use red for errors.
- Keep non-interactive output plain text.

## CLI Behavior Rules

- Shared entrypoint scripts should accept only the documented arguments.
- Unsupported argument patterns should fail clearly and direct the user to `--help`.
- `scripts/shared/opencode/opencode-run` accepts zero, one, or two arguments: `[workspace] [project]`.
- `scripts/shared/opencode/opencode-run` must reject more than two arguments before workspace validation with `This script takes zero, one, or two arguments: [workspace] [project]. See --help.`.
- `scripts/shared/opencode/opencode-shell` accepts zero, one, two, or more arguments.
- For `opencode-shell`, the first argument is the workspace, the second argument is the project, and remaining arguments are run directly inside the project container.
- `opencode-shell` opens `OPENCODE_SHELL_COMMAND` only when no command arguments remain after workspace and project parsing.
- `opencode-shell <workspace> -- <command...>` treats `--` as the project token and must reject it as an unsafe project name.
- `opencode-shell` prompts for workspace and project when no args are supplied.
- `opencode-shell <workspace>` prompts for project.
- `opencode-shell <workspace> <project> [command...]` runs the command inside the project container when command arguments are supplied.
- `opencode-shell <workspace> <project> opencode -c` must run `opencode -c` directly in the project container, not open Nushell.
- Explicit shell project attachment should still work when the host project directory no longer exists, if a matching running container exists.

## Version Pin Rules

- The pinned OpenCode version lives in `configs/shared/opencode/opencode-settings-shared.conf`.
- Version bumps must update the config file, `configs/shared/opencode/Containerfile`, user docs, architecture docs, and all affected test fixtures.
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

## Documentation Rules

- Every active script, config, shared library, test file, and doc must be well documented.
- Add short header comments to active scripts and config files when the contract is not obvious from the filename alone.
- Add a short header comment to each active test file describing covered behaviors and the isolation approach when it is not obvious from the filename.
- Keep active docs precise and aligned with the current file layout and behavior.
