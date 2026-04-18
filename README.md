# OpenCode Wrapper Repo

This repository builds and runs a local OpenCode container with repository-owned configuration, wrapper scripts, shell helpers, and shell tests.

## Layout

The repository uses a normalized path shape:

```text
category/subcategory/scope
```

Current layout:

```text
config/agent/shared/opencode-settings-shared.conf
config/containers/shared/Containerfile
docs/usage/shared/usage.md
docs/usage/shared/architecture.md
lib/shell/shared/common.sh
scripts/agent/shared/opencode-build
scripts/agent/shared/opencode-run
scripts/agent/shared/opencode-shell
tests/agent/shared/test-opencode-build.sh
tests/agent/shared/test-opencode-layout.sh
tests/agent/shared/test-opencode-run.sh
tests/agent/shared/test-opencode-shell.sh
```

## Commands

- Build the image: `scripts/agent/shared/opencode-build`
- Start a configured workspace: `scripts/agent/shared/opencode-run`
- Open a shell in a running workspace container: `scripts/agent/shared/opencode-shell`

## Configuration

Repo-owned runtime and build settings live in:

```text
config/agent/shared/opencode-settings-shared.conf
```

Container build configuration lives in:

```text
config/containers/shared/Containerfile
```

## Runtime Contract

- Container user: `opencode`
- Container home: `/home/opencode`
- General workspace mount: `/workspace/general`
- Development root mount: `/workspace/development`
- Selected project mount: `/workspace/project`
- Default in-container working directory: `/workspace/project`

## Tests

Run the shell suite sequentially because tests temporarily rewrite the shared config file:

```text
bash tests/agent/shared/test-all.sh
bash tests/agent/shared/test-opencode-layout.sh
bash tests/agent/shared/test-opencode-build.sh
bash tests/agent/shared/test-opencode-run.sh
bash tests/agent/shared/test-opencode-shell.sh
```
