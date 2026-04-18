# AGENTS

This file defines the repository structure, naming rules, and safe-editing rules for agents creating or reorganizing content in this repo.

## Core Shape

- Canonical directory shape is `category/subcategory/scope`.
- `category` is the top-level bucket.
- `subcategory` is the functional family inside that category.
- `scope` describes OS applicability only.

## Allowed Scope Values

- `shared`
- `macos`
- `linux`

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
- `lib/shell/...`

## Config Filename Rule

The special filename convention applies only to files under `config`.

Format:

```text
<subcategory>-<filejob>-<host>.<ext>
```

Examples:

- `config/agent/shared/opencode-settings-shared.conf`

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
- `docs/usage/shared/usage.md`
- `docs/usage/shared/architecture.md`
- `lib/shell/shared/common.sh`
- `scripts/agent/shared/opencode-build`
- `scripts/agent/shared/opencode-run`
- `scripts/agent/shared/opencode-shell`
- `tests/agent/shared/test-asserts.sh`
- `tests/agent/shared/test-opencode-build.sh`
- `tests/agent/shared/test-opencode-layout.sh`
- `tests/agent/shared/test-opencode-run.sh`
- `tests/agent/shared/test-opencode-shell.sh`

## Root Files

- Keep `README.md` at the repository root.
- Keep `AGENTS.md` at the repository root.

## Current Behavioral Rules

- Repo-owned runtime and build settings live in `config/agent/shared/opencode-settings-shared.conf`.
- Container build configuration lives in `config/containers/shared/Containerfile`.
- Shared shell helpers live in `lib/shell/shared/common.sh`.
- User-facing documentation lives in `docs/usage/shared/`.
- Shell tests live in `tests/agent/shared/`.
- The shell tests mutate the shared config file during execution, so they must be run sequentially.
- `scripts/agent/shared/opencode-build` must only build from a clean, committed checkout.
- `scripts/agent/shared/opencode-run` keeps one container per workspace and recreates it when the selected project changes.
- Shared interactive Podman exec behavior lives in `lib/shell/shared/common.sh`.
