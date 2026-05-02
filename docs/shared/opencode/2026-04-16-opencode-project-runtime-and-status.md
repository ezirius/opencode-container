# OpenCode Project Runtime And Status Notes

This document is a retained project note for the current OpenCode wrapper layout.

## Current Canonical Paths

- `configs/shared/opencode/opencode-settings.conf`
- `configs/shared/opencode/Containerfile`
- `docs/shared/opencode/2026-04-16-opencode-project-runtime-and-status.md`
- `docs/shared/opencode/usage.md`
- `docs/shared/opencode/architecture.md`
- `libs/shared/opencode/common.sh`
- `scripts/shared/opencode/opencode-build`
- `scripts/shared/opencode/opencode-run`
- `scripts/shared/opencode/opencode-shell`
- `tests/shared/opencode/test-all.sh`
- `tests/shared/opencode/test-opencode-build.sh`
- `tests/shared/opencode/test-opencode-layout.sh`
- `tests/shared/opencode/test-opencode-run.sh`
- `tests/shared/opencode/test-opencode-shell.sh`
- `tests/shared/shared/test-asserts.sh`

## Current Runtime Summary

- The wrapper uses one shared published runtime container per workspace plus private project containers.
- Shared runtime containers publish the host browser port.
- Project containers do not publish host ports.
- Shared runtime containers are created or started before project-container handling.
- Project containers attach to `http://$OPENCODE_ATTACH_HOST:$OPENCODE_SERVER_PORT` inside the container.
- The pinned OpenCode version lives in `configs/shared/opencode/opencode-settings.conf`.

## Maintenance Notes

- Keep all repo-owned non-root files in the `[repo base]/category/os/app-or-shared/file` shape.
- Keep path references aligned with the canonical `configs`, `docs`, `libs`, `scripts`, and `tests` directories.
- Update this note when the documented runtime contract changes.
