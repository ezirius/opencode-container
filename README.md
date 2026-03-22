# OpenCode ARM64 container

## Layout

Only this README is in the base directory.

- `config/`
- `docs/`
- `examples/`
- `lib/`
- `scripts/`
- `tests/`

## Rules

- Apple Silicon host -> ARM64 container only
- No AMD64 fallback
- Shared image, separate container per workspace
- Workspace is mounted to `/workspace`
- Workspace `configurations/` is mounted to `/configurations`
- Workspace `data/` is mounted to `/data`
