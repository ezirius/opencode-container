# OpenCode Container Implementation Plan

## Goal

Rebuild `opencode-container` so it follows the same wrapper model as `hindsight-container` wherever that model fits OpenCode cleanly.

The target wrapper should:

- own a stable Ubuntu LTS runtime instead of wrapping the upstream OpenCode container image directly
- use immutable local wrapper images
- use deterministic human-readable container names
- keep shared logic in `lib/shell/common.sh`
- use picker-driven workspace commands
- preserve OpenCode home and storage behaviour inside the wrapper-owned runtime
- keep wrapper-owned files separate from OpenCode-owned files

The wrapper should document this as a tooling-driven decision: the runtime is now wrapper-owned so official-release builds and `main` source builds can share one stable operating-system and tooling surface.

`shared` means the files are intended to work on both macOS and Linux. `macos` means macOS-only.

The directory structure should be:

- `config/shared/`
- `config/macos/`
- `config/containers/`
- `config/patches/`
- `docs/shared/`
- `docs/macos/`
- `lib/shell/`
- `scripts/shared/`
- `scripts/macos/`
- `tests/shared/`
- `tests/macos/`

`config/patches/` should exist for future use but remain empty unless a narrow upstream compatibility problem requires a patch.

## Scope

This plan applies to the OpenCode container wrapper itself, not to upstream OpenCode behavior.

The wrapper must:

- preserve OpenCode state under the wrapper-owned runtime home `/home/opencode`
- keep wrapper-owned config and metadata out of upstream-owned state
- use Hindsight-style immutable image and container identity
- use Hindsight-style workspace target selection and removal flows
- avoid inventing Hindsight service semantics that OpenCode does not naturally have

The wrapper must not:

- reshape OpenCode state into wrapper-owned `/configurations` and `/data` mounts
- require non-empty wrapper env files for startup unless future testing proves OpenCode needs that
- add a default localhost port publishing model just for symmetry with Hindsight
- add browser-open or HTTP readiness behavior unless OpenCode is intentionally being run in `serve` or `web` mode

## Core Model

There are two distinct identity dimensions:

1. Upstream app version
- `main`
- `latest`
- an exact upstream release tag, for example `1.4.3`

2. Wrapper context
- `main` when run from the canonical main checkout
- the worktree name when run from a worktree

These dimensions must stay separate in naming, labels, selection, and status output.

## Source Rules

### Production

Production builds:

- must run from the canonical main checkout
- must not run from a linked worktree, even if that worktree is checked out on branch `main`
- require a clean working tree
- require no unpushed commits
- require the canonical main checkout to be in sync with GitHub

Primary detection:

- use Git primary-vs-linked-worktree detection

Fallback detection:

- use directory convention detection such as `*-worktrees/`

### Test

Test builds:

- may run from the canonical main checkout or from a worktree
- require a clean working tree
- do not require pushes to GitHub

The wrapper context is always inferred from where the command is run.

## Upstream Version Rules

The upstream argument always selects the upstream OpenCode version. It does not select the local wrapper source.

Accepted upstream values:

- `main`
- `latest`
- an exact release tag such as `1.4.3`

Resolution:

- `main` stays `main`
- an exact release stays exactly as given
- `latest` resolves live from upstream releases to an exact release tag before naming

Rules:

- the default build target is the latest stable official release available at build time
- the picker should show `main` plus exact stable release tags newest to oldest
- the picker should not show a floating `latest` choice
- `latest` remains accepted as a command argument and resolves before naming
- beta, prerelease, preview, rc, nightly, and other non-stable releases must not be selected or offered by default
- floating upstream tags must not appear in immutable wrapper image tags or deterministic container names

## Build Strategy

The wrapper always produces a local immutable Ubuntu-based image for local container use.

Build source rules:

- `main` must build from upstream source
- an exact stable release should install the official OpenCode release into the wrapper-owned Ubuntu runtime
- `latest` should resolve to the newest exact stable release and then use the same exact-release logic

This means the wrapper is latest-stable-release-first, while still able to build `main` from source when the user explicitly chooses it.

## Image Model

### Image Naming

Each built image gets exactly one immutable tag.

Image reference shape:

- `<image-name>:<lane>-<upstream>-<wrapper>-<commitstamp>`

Where:

- `<lane>` is `production` or `test`
- `<upstream>` is the resolved upstream value
- `<wrapper>` is `main` or the worktree name
- `<commitstamp>` is the wrapper commit identity in the format `YYYYMMDD-HHMMSS-<commitid>`
- the date/time component is the wrapper commit timestamp, not build time

Examples:

- `opencode-local:production-1.4.3-main-20260410-163440-ab12cd3`
- `opencode-local:production-main-main-20260410-163440-ab12cd3`
- `opencode-local:test-1.4.3-add-status-20260410-163440-ab12cd3`
- `opencode-local:test-main-main-20260410-163440-ab12cd3`

Rationale:

- one unique image tag identifies one wrapped build exactly
- there are no mutable lane aliases like `:production` or `:test`
- there is no shared mutable image that later commands silently reuse or mutate

## Container Model

Containers should be human-readable and deterministic.

Container name shape:

- `<project>-<workspace>-<lane>-<upstream>-<wrapper>`

Examples:

- `opencode-general-production-1.4.3-main`
- `opencode-general-production-main-main`
- `opencode-general-test-1.4.3-add-status`
- `opencode-general-test-main-main`

Containers are persistent and long-lived.

The wrapper should reuse and `exec` into running containers rather than creating transient secondary containers against the same state.

## Persistent Layout

Use the same base-root philosophy as Hindsight.

Recommended default base root:

- `$HOME/.local/share/opencode-container`

Each workspace is a first-level child directory, for example:

- `general`
- `ezirius`

For each workspace `<workspace>`, use:

- `<base-root>/<workspace>/opencode-home`
- `<base-root>/<workspace>/opencode-workspace`
- `<base-root>/<workspace>/opencode-workspace/.config/opencode`

Ownership model:

- `opencode-home` contains OpenCode-owned files and runtime state
- `opencode-workspace` contains wrapper-owned and user-owned workspace files
- `.config/opencode` inside `opencode-workspace` contains wrapper-only env/config files

The wrapper must never treat `opencode-home` as wrapper-owned storage.

## Container Mounts

Each workspace container mounts exactly:

- `"$BASE/<workspace>/opencode-home:/home/opencode"`
- `"$BASE/<workspace>/opencode-workspace:/workspace/opencode-workspace"`
- `"$OPENCODE_DEVELOPMENT_ROOT:/workspace/opencode-development"` when that host path exists

In-container meaning:

- `/home/opencode` = the wrapper-owned OpenCode runtime home
- `/workspace/opencode-workspace` = wrapper-owned workspace mount
- `/workspace/opencode-workspace/.config/opencode` = wrapper env/config area
- `/workspace/opencode-development` = optional extra host development mount when a local development tree is available

Wrapper exec operations should use:

- `/workspace/opencode-workspace`

## Upstream Home Behavior

OpenCode is expected to populate `opencode-home` substantially over time.

Verified and documented upstream-owned locations include:

- `/home/opencode/.config/opencode/`
- `/home/opencode/.local/share/opencode/`
- `/home/opencode/.local/state/opencode/`
- `/home/opencode/.cache/opencode/`

Documented examples include:

- `~/.config/opencode/opencode.json`
- `~/.config/opencode/tui.json`
- `~/.local/share/opencode/auth.json`
- `~/.local/share/opencode/log/`
- `~/.local/share/opencode/project/`

The wrapper should preserve this upstream behavior rather than redirecting it elsewhere.

## Wrapper Config Model

To stay like Hindsight, there must be a strict split between wrapper defaults and OpenCode-native config.

Wrapper-owned config should consist of:

- `config/shared/opencode.conf`
- `config/shared/tool-versions.conf`
- `opencode-workspace/.config/opencode/config.env`
- optionally `opencode-workspace/.config/opencode/secrets.env`
- `config/containers/entrypoint.sh` as the runtime loader for those env files

`config/shared/opencode.conf` is only for wrapper defaults and wrapper metadata. It is not an OpenCode application config file.

It should contain only wrapper-level settings such as:

- default base root
- local image name
- project prefix
- upstream repo URL
- GitHub API base URL
- npm registry base URL for official release packages
- pinned Ubuntu LTS version
- development root mount source

`config/shared/tool-versions.conf` should pin wrapper-owned shared-tool versions separately from the main runtime defaults.

It must not contain OpenCode-native settings such as:

- model selection
- provider configuration
- permissions
- tools
- TUI settings
- agents, commands, plugins, or themes

Those OpenCode-native settings stay upstream-native under `/home/opencode/.config/opencode` or in project-local OpenCode config.

Rules:

- `.env` files are wrapper runtime inputs
- OpenCode-native config stays in upstream-native JSON or JSONC files under `/home/opencode/.config/opencode`
- wrapper-owned defaults such as the Ubuntu LTS base version must be pinned in config, checked for newer suitable versions during build, and never changed silently
- the current implementation performs that newer-version notification for the pinned Ubuntu LTS base
- wrapper config or secrets changes must be applied by container restart only
- wrapper config or secrets changes must not require image rebuild
- wrapper config or secrets changes must not require container recreate unless a mount, published server port, or image identity itself changed
- `secrets.env` must override matching keys from `config.env`
- env files must be parsed as assignments only and must never be executed as shell code

The wrapper should seed a starter `config.env` comment file, but it should remain optional and startup must not depend on it being populated.

The wrapper should not automatically seed `opencode.json` or other OpenCode-native config by default.

## Runtime Model

This is the only unavoidable OpenCode-specific adaptation.

OpenCode remains CLI-first, so the wrapper must still provide a persistent keepalive container runtime that `podman exec` can reuse.

Target runtime behavior:

- the container is long-lived
- the container starts with a thin wrapper entrypoint or command that loads wrapper env files if present
- the container then runs a simple keepalive process
- if `OPENCODE_HOST_SERVER_PORT` is configured for the workspace, the wrapper starts and verifies a managed `opencode serve --hostname 0.0.0.0 --port 4096` process
- the wrapper-managed server contract is always host `<configured-port>` to container `4096`
- `opencode-open` uses `podman exec`
- `opencode-shell` uses `podman exec`

The keepalive process should be minimal and boring. The wrapper should not invent a larger service model just to imitate Hindsight.

Runtime config loading must behave like Hindsight in the operational sense:

- update `config.env` or `secrets.env`
- stop the container
- start the container
- new config takes effect

That flow must not require rebuild. It may require container recreate when the effective runtime config changes the published server port or mount layout.

## Command Model

Provide these scripts:

- `scripts/shared/opencode-build`
- `scripts/shared/opencode-bootstrap`
- `scripts/shared/opencode-start`
- `scripts/shared/opencode-open`
- `scripts/shared/opencode-shell`
- `scripts/shared/opencode-logs`
- `scripts/shared/opencode-status`
- `scripts/shared/opencode-stop`
- `scripts/shared/opencode-remove`

Do not add `bootstrap-test`.

## Command Shapes

Match Hindsight's command shapes as closely as possible:

- `opencode-build <lane> [upstream]`
- `opencode-bootstrap <workspace> [opencode args...]`
- `opencode-start <workspace>`
- `opencode-start <workspace> -- [opencode args...]`
- `opencode-start <workspace> <lane> <upstream> [opencode args...]`
- `opencode-start <workspace> <lane> <upstream> -- [opencode args...]`
- `opencode-open <workspace> [opencode args...]`
- `opencode-open <workspace> -- [opencode args...]`
- `opencode-open <workspace> <lane> <upstream> [opencode args...]`
- `opencode-open <workspace> <lane> <upstream> -- [opencode args...]`
- `opencode-shell <workspace> [command args...]`
- `opencode-shell <workspace> -- [command args...]`
- `opencode-shell <workspace> <lane> <upstream> [command args...]`
- `opencode-shell <workspace> <lane> <upstream> -- [command args...]`
- `opencode-logs <workspace> [podman logs args...]`
- `opencode-status <workspace>`
- `opencode-stop <workspace>`
- `opencode-remove`
- `opencode-remove containers`
- `opencode-remove images`

`opencode-open` should match Hermes-style behavior and forward trailing arguments into the exec'd `opencode` command.

This means:

- no extra args: run `opencode`
- extra args: run `opencode "$@"`
- use `--` when the first forwarded argument would otherwise look like a wrapper lane selector such as `test` or `production`

If `opencode-start` receives trailing OpenCode args, it should start or reuse the selected target and then delegate to `opencode-open` against that same resolved target.

## Selection UX

Adopt Hindsight's selection model.

`opencode-build <lane>`:

- omitting `upstream` defaults to `latest`
- `latest` resolves to the newest stable official release before naming

`opencode-start <workspace>` and `opencode-bootstrap <workspace>`:

- use a mixed picker that may show existing workspace containers and image-only targets
- if a newer immutable image exists for the same logical lane/upstream/wrapper track, show that newer image-only target rather than hiding it behind an older container

`opencode-open`, `opencode-shell`, `opencode-logs`, `opencode-status`, and `opencode-stop`:

- operate on existing containers only

Picker ordering:

- production first
- newest to oldest within production
- then test
- newest to oldest within test

Picker display should show:

- lane
- upstream
- wrapper
- commit stamp
- status

Status values are:

- mixed target picker: `running`, `stopped`, `image only`
- container picker: `running`, `stopped`

## Status

Add `opencode-status`.

It should print a concise wrapper-oriented summary including:

- container name
- workspace name
- lane
- upstream
- wrapper context
- commit stamp
- running or stopped state
- backing image
- mounted host paths

It should not invent Hindsight-style service URLs unless the selected runtime target is intentionally running OpenCode in a server mode that actually exposes one.

## Remove

Use Hindsight-style project-scoped removal:

- `opencode-remove`
- `opencode-remove containers`
- `opencode-remove images`

The remove picker should show:

1. `All, but newest`
2. `All`
3. individual targets

With no mode argument, the mixed remove picker should show containers first and then images.

Remove display columns:

- container removal: `workspace`, `lane`, `upstream`, `wrapper`, `commit`, `status`
- image removal: `image-ref`, `lane`, `upstream`, `wrapper`, `commit`

`All, but newest` means:

- for containers: leave the preferred container per workspace, where `production` wins over `test` and commit timestamp breaks ties within the same lane
- for images: leave the image serving each kept newest container
- for mixed mode: leave the preferred container per workspace and the image serving it

`All` in mixed mode means remove all containers first and then all images.

## Labels and Discovery

Images and containers should carry labels for:

- project
- workspace
- lane
- upstream
- upstream exact ref
- wrapper context
- commit stamp

Where possible, labels should be the source of truth and names should be derived, human-readable identities rather than the only place metadata lives.

## Shared Code Placement

Any code reused by more than one script must go into `lib/`.

Primary shared location:

- `lib/shell/common.sh`

Shared code should include:

- config loading
- path helpers
- Podman helpers
- Git validation helpers
- canonical-main vs linked-worktree detection
- worktree name resolution
- upstream release lookup
- upstream image-tag availability lookup
- wrapper commit timestamp and commit id resolution
- image tag generation
- container name generation
- project-scoped image/container discovery
- sorting helpers
- picker rendering and selection helpers
- runtime env loading helpers
- status formatting helpers

It should not include Hindsight-only helpers for browser launches or HTTP URL readiness unless OpenCode gains a real matching runtime mode.

## Docs Updates Required

Rewrite `README.md` and `docs/shared/usage.md` around:

- Ubuntu LTS-owned runtime model
- immutable images
- build lanes
- upstream selectors
- wrapper context
- picker-driven UX
- new workspace layout
- project-scoped remove behavior
- `opencode-status`
- exec-based `opencode-open`

## Test Updates Required

Current tests are built around the old mutable-image model and old mount layout.

Rewrite them for:

- wrapper config in `config/shared/opencode.conf`
- official-image-first build logic
- immutable image refs
- deterministic readable container names
- lane and upstream validation
- worktree context resolution
- `latest` exact-resolution behavior
- picker behavior
- Hindsight-style remove flows
- startup and reuse behavior with the keepalive runtime
- restart-only wrapper env and secrets application
- `opencode-open` argument forwarding
- preservation of upstream home behavior

Keep:

- mocked Podman runtime tests
- a gated live integration test

Do not copy Hindsight's port and HTTP-ready assertions into OpenCode tests unless OpenCode is intentionally run in a mode that exposes them.

## Implementation Sequence

1. Add `docs/shared/implementation-plan.md`.
2. Add `config/shared/opencode.conf`.
3. Rebuild `lib/shell/common.sh` around the Hindsight helper model.
4. Replace the current thin wrapper-image model with a wrapper-owned Ubuntu LTS runtime.
5. Add stable-release installation and `main` source-build support inside that owned runtime.
6. Add immutable image naming and deterministic container naming.
7. Replace the current mount layout with:
- `/home/opencode`
- `/workspace/opencode-workspace`
- `/workspace/opencode-development`
8. Add wrapper env loading via `config.env` and optional `secrets.env`.
9. Rename and remove scripts to the Hindsight-aligned set.
10. Add picker-driven target and container selection.
11. Add `opencode-status`.
12. Rework `opencode-remove` into project-scoped images and containers removal.
13. Rewrite `README.md` and `docs/shared/usage.md`.
14. Rewrite mocked tests.
15. Add a gated live test.

## Main Risks

1. Overfitting OpenCode into a fake service model.
- The wrapper should not imitate Hindsight's service behavior where OpenCode has no equivalent.

2. State ownership drift.
- Wrapper env, OpenCode JSON config, OpenCode auth, and runtime storage must remain clearly separated.

3. Breaking current container identities.
- Existing hashed workspace containers and mutable shared image assumptions will become legacy.

4. Carrying forward the old upgrade model.
- The mutable shared-image `upgrade` flow must disappear completely.

## Final Rule Set

- pinned Ubuntu LTS runtime
- latest stable official release by default
- source build for `main` when the user explicitly chooses it
- exact release resolution for `latest`
- immutable wrapper images only
- no upgrade script
- Hindsight-style naming and selection model
- preserve upstream OpenCode home behavior fully
- wrapper `.env` files stay in workspace config
- OpenCode-native JSON or JSONC config stays under `opencode-home`
- updating wrapper config or secrets requires stop/start only, never rebuild
- `opencode-open` is exec-based and forwards trailing args like Hermes
