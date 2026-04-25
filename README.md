# OpenCode Wrapper Repo

This repository builds and runs a thin local image derived from the official upstream container with repository-owned configuration, wrapper scripts, shell helpers, and shell tests.

The wrapper keeps a stable mount contract, project selection, and a two-container runtime per workspace: one shared published runtime plus private project containers.

## Layout

The repository uses a normalized path shape:

```text
category/subcategory/scope
```

Current layout:

```text
config/agent/shared/opencode-settings-shared.conf
config/containers/shared/Containerfile
docs/superpowers/plans/2026-04-16-opencode-project-runtime-and-status.md
docs/usage/shared/usage.md
docs/usage/shared/architecture.md
lib/shell/shared/common.sh
scripts/agent/shared/opencode-build
scripts/agent/shared/opencode-run
scripts/agent/shared/opencode-shell
tests/agent/shared/test-opencode-build.sh
tests/agent/shared/test-asserts.sh
tests/agent/shared/test-all.sh
tests/agent/shared/test-opencode-layout.sh
tests/agent/shared/test-opencode-run.sh
tests/agent/shared/test-opencode-shell.sh
```

## Commands

- Build the image: `scripts/agent/shared/opencode-build`
- Start a configured workspace: `scripts/agent/shared/opencode-run`
- Open a shell or run a command in a running project container: `scripts/agent/shared/opencode-shell <workspace> <project> [command...]`

`opencode-shell <workspace> <project>` opens `nu` by default.

`opencode-shell <workspace> <project> [command...]` runs the command directly inside the project container.

## Configuration

Repo-owned runtime and build settings live in:

```text
config/agent/shared/opencode-settings-shared.conf
```

The thin local `Containerfile` lives in:

```text
config/containers/shared/Containerfile
```

The wrapper pins the official upstream container base to version `1.14.25`.

The config records `arm64` as the target architecture; the local `Containerfile` pins the upstream image tag, not a platform flag.

## Runtime Contract

- Container user: `root`
- Container home: `/root`
- General workspace mount: `/workspace/general`
- Development root mount: `/workspace/development`
- Shared runtime projects mount: `/workspace/projects`
- Selected project mount: `/workspace/project`
- Default in-container working directory: `/workspace/project`
- Default interactive shell: `nu`
- Internal upstream server port: `4096`
- Published host port mapping: shared runtime container only, using `4096 + workspace offset`
- Shared runtime role: published browser server for the workspace.
- Project container role: private project session that serves locally and attaches to its own local server.
- Interactive attach flow: project containers run `opencode attach http://127.0.0.1:4096` inside their own container
- Image naming: `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`
- Shared runtime naming: `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<development-root-basename>`
- Project container naming: `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<project>`
- New container creation: created directly with the final canonical container name
- Shared runtime container: always ports-on, reused or started before project-container handling
- Existing project container: reused unchanged when already running, or started unchanged when stopped

## Tests

Run the shell suite sequentially because tests temporarily rewrite the shared config file:

```text
bash tests/agent/shared/test-all.sh
bash tests/agent/shared/test-opencode-layout.sh
bash tests/agent/shared/test-opencode-build.sh
bash tests/agent/shared/test-opencode-run.sh
bash tests/agent/shared/test-opencode-shell.sh
```
