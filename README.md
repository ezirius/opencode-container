# OpenCode Wrapper Repo

This repository builds and runs a thin local image derived from the official upstream container with repository-owned configuration, wrapper scripts, shell helpers, and shell tests.

The wrapper keeps a stable mount contract, project selection, and a two-container runtime per workspace: one shared published runtime plus private project containers.

## Layout

The repository uses a normalized path shape:

```text
[repo base]/category/os/app-or-shared/file
```

Current layout:

```text
configs/shared/opencode/opencode-settings-shared.conf
configs/shared/opencode/Containerfile
docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md
docs/shared/opencode/usage.md
docs/shared/opencode/architecture.md
libs/shared/opencode/common.sh
scripts/shared/opencode/opencode-build
scripts/shared/opencode/opencode-run
scripts/shared/opencode/opencode-shell
tests/shared/shared/test-asserts.sh
tests/shared/opencode/test-opencode-build.sh
tests/shared/opencode/test-all.sh
tests/shared/opencode/test-opencode-layout.sh
tests/shared/opencode/test-opencode-run.sh
tests/shared/opencode/test-opencode-shell.sh
```

## Commands

- Build the image: `scripts/shared/opencode/opencode-build`
- Start a configured workspace: `scripts/shared/opencode/opencode-run`
- Open a shell or run a command in a running project container: `scripts/shared/opencode/opencode-shell <workspace> <project> [command...]`

`opencode-shell` prompts for workspace and project, then opens `nu` by default.

`opencode-shell <workspace>` prompts for project, then opens `nu` by default.

`opencode-shell <workspace> <project>` opens `nu` by default.

`opencode-shell <workspace> <project> [command...]` runs the command directly inside the project container.

`scripts/shared/opencode/opencode-build` only runs from a clean committed checkout. It requires an attached branch HEAD. On `main`, it also requires `main` to track `origin/main` and `main` to be pushed and in sync with `origin/main`. A clean committed local branch without an upstream remains allowed.

## Configuration

Repo-owned runtime and build settings live in:

```text
configs/shared/opencode/opencode-settings-shared.conf
```

The thin local `Containerfile` lives in:

```text
configs/shared/opencode/Containerfile
```

The wrapper pins the official upstream container base to version `1.14.25`.

The config records `OPENCODE_SERVER_PORT` as the internal server port, and the local `Containerfile` pins the upstream image tag directly.

The shared defaults set `OPENCODE_BASE_PATH` to `$HOME/Documents/Ezirius/.applications-data/.containers-artificial-intelligence`, `OPENCODE_DEVELOPMENT_ROOT` to `$HOME/Documents/Ezirius/Development/OpenCode`, and `OPENCODE_WORKSPACES` to `ezirius:10000 nala:20000`.

## Runtime Contract

- Container user: `root`
- Container home: `/root`
- General workspace mount: `/workspace/general`
- Development root mount: `/workspace/development`
- Shared runtime projects mount: `/workspace/projects`
- Selected project mount: `/workspace/project`
- Default in-container working directory: `/workspace/project`
- Default interactive shell: `nu`
- Internal upstream server port: `OPENCODE_SERVER_PORT` from config, currently `4096`
- In-container serve hostname: `OPENCODE_SERVER_HOSTNAME` from config, currently `0.0.0.0`
- In-container attach host: `OPENCODE_ATTACH_HOST` from config, currently `127.0.0.1`
- Published host port mapping: shared runtime container only, using `OPENCODE_SERVER_PORT + workspace offset`
- Shared runtime role: published browser server for the workspace.
- Project container role: private project session that serves locally and attaches to its own local server.
- Interactive attach flow: project containers run `opencode attach http://$OPENCODE_ATTACH_HOST:$OPENCODE_SERVER_PORT` inside their own container
- Image naming: `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`
- Shared runtime naming: `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-infrastructure`
- Project container naming: `opencode-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>-<workspace>-<project>`
- New container creation: created directly with the final canonical container name
- Shared runtime container: always ports-on, reused or started before project-container handling
- Existing project container: reused unchanged when already running, or started unchanged when stopped

## Tests

Run the shell suite sequentially because tests temporarily rewrite the shared config file:

```text
bash tests/shared/opencode/test-all.sh
bash tests/shared/opencode/test-opencode-layout.sh
bash tests/shared/opencode/test-opencode-build.sh
bash tests/shared/opencode/test-opencode-run.sh
bash tests/shared/opencode/test-opencode-shell.sh
```
