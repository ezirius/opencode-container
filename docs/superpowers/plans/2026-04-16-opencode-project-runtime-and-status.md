# OpenCode Project Runtime and Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split OpenCode global versus project config correctly, require project selection from the development base, add the `/workspace/opencode-project` mount, make selected project part of container identity, and keep status/reporting and pinned-version handling aligned with the repo rules.

**Architecture:** Keep wrapper-wide defaults in `config/shared/opencode.conf`, keep workspace-scoped wrapper env in `config.env` and `secrets.env`, keep OpenCode global config in `~/.config/opencode`, and treat the selected direct child project under `OPENCODE_DEVELOPMENT_ROOT` as the upstream-native project root at `/workspace/opencode-project`. Make the selected project part of container identity so multiple projects in one workspace can run concurrently without sharing a container name, keep OpenCode project-scoped session state under `~/.local/share/opencode/project/<project-slug>/storage/`, and filter wrapper env so it cannot redirect OpenCode's own config discovery.

**Tech Stack:** Bash, Podman, shell test suite in `tests/shared/*.sh`, Markdown docs.

---

### Task 1: Introduce Selected Project Runtime Helpers

**Files:**
- Modify: `lib/shell/common.sh`
- Modify: `config/shared/opencode.conf`
- Test: `tests/shared/test-runtime.sh`
- Test: `tests/shared/test-layout.sh`

- [ ] **Step 1: Write the failing tests**
Add tests that assert:
- direct child directories under `OPENCODE_DEVELOPMENT_ROOT` are listed alphabetically
- no nested path outside the immediate-child set is accepted
- the selected project host path mounts to `/workspace/opencode-project`
- `/workspace/opencode-development` still mounts the full development root
- all four mounts are required for runtime compatibility

- [ ] **Step 2: Run the targeted tests to verify failure**
Run: `./tests/shared/test-runtime.sh`
Expected: FAIL because project-selection helpers and the `/workspace/opencode-project` contract do not exist yet.

- [ ] **Step 3: Write minimal runtime helpers**
In `lib/shell/common.sh`, add helpers along these lines:
- `project_names_from_development_root`
- `select_project_name`
- `resolve_selected_project_name`
- `project_root_dir`
- `container_project_dir`
- `project_mount_spec`
- `container_project_mount_matches_workspace_config`
- extend `container_mounts_match_workspace_config`

Use the existing `select_menu_option` UX and keep the selectable set to immediate subdirectories only.

- [ ] **Step 4: Update the shared config constant**
In `config/shared/opencode.conf`, make `OPENCODE_CONTAINER_DEVELOPMENT_DIR` continue to mean the full development-root mount and add a new wrapper-owned constant for `/workspace/opencode-project` if needed. Do not move wrapper-owned defaults into project config.

- [ ] **Step 5: Run the targeted tests to verify pass**
Run: `./tests/shared/test-runtime.sh && ./tests/shared/test-layout.sh`
Expected: PASS for the new mount helper and validation coverage.

- [ ] **Step 6: Commit**

```bash
git add tests/shared/test-runtime.sh tests/shared/test-layout.sh lib/shell/common.sh config/shared/opencode.conf
git commit -S -m "fix: Add Mandatory Selected Project Runtime Mount

- Add direct-child project selection and runtime mount helpers so workspace containers always expose both the full development root and one selected project at stable container paths.
- Extend runtime compatibility checks and layout coverage so invalid or stale mount combinations are recreated instead of being reused silently."
```

### Task 2: Thread Mandatory Project Selection Through Workspace Commands

**Files:**
- Modify: `scripts/shared/opencode-start`
- Modify: `scripts/shared/opencode-open`
- Modify: `scripts/shared/opencode-shell`
- Modify: `lib/shell/common.sh`
- Test: `tests/shared/test-runtime.sh`
- Test: `tests/shared/test-args.sh`

- [ ] **Step 1: Write the failing tests**
Add tests that assert:
- `start` resolves workspace, then target/container, then project
- `open` and `shell` require a selected project before execution
- changing the selected project forces recreation
- `open` and `shell` use `/workspace/opencode-project` as the default workdir

- [ ] **Step 2: Run the targeted tests to verify failure**
Run: `./tests/shared/test-runtime.sh && ./tests/shared/test-args.sh`
Expected: FAIL because the command flow currently stops after workspace/target selection and still defaults to `/workspace/opencode-workspace`.

- [ ] **Step 3: Implement the command flow changes**
Update:
- `opencode-start` to require project selection before ensuring the final container
- `opencode-open` to resolve or recreate a compatible running container for the selected project
- `opencode-shell` to do the same
- `exec_opencode_in_container` and `exec_shell_in_container` to default to `/workspace/opencode-project`

- [ ] **Step 4: Make project selection part of runtime compatibility**
Ensure `ensure_running_container_matches_image_and_runtime` recreates when the selected project mount differs even if image, lane, and upstream are unchanged.

- [ ] **Step 5: Run the targeted tests to verify pass**
Run: `./tests/shared/test-runtime.sh && ./tests/shared/test-args.sh`
Expected: PASS for picker sequencing, recreation, and workdir behaviour.

- [ ] **Step 6: Commit**

```bash
git add tests/shared/test-runtime.sh tests/shared/test-args.sh scripts/shared/opencode-start scripts/shared/opencode-open scripts/shared/opencode-shell lib/shell/common.sh
git commit -S -m "fix: Require Selected Project Context for Workspace Commands

- Make start, open, and shell require a direct-child project selection so OpenCode always runs against a real project root mounted at `/workspace/opencode-project`.
- Recreate containers when the selected project changes and switch default execution workdirs to the selected project so runtime behaviour matches upstream config discovery."
```

### Task 3: Fix Pinned-Version Choice Handling

**Files:**
- Modify: `lib/shell/common.sh`
- Modify: `scripts/shared/opencode-build`
- Test: `tests/shared/test-runtime.sh`
- Test: `tests/shared/test-args.sh`

- [ ] **Step 1: Write the failing tests**
Replace the current notification-only expectations with tests that assert:
- when a newer suitable Ubuntu LTS exists, the user is prompted every time
- the choices are exactly keep current pin, update config pin, or cancel
- keeping the current pin still builds with the pinned value
- updating changes `config/shared/opencode.conf` first, then builds with the new pin
- cancelling stops without building
- `OPENCODE_VERSION` is not treated as a wrapper-owned pin

- [ ] **Step 2: Run the targeted tests to verify failure**
Run: `./tests/shared/test-runtime.sh`
Expected: FAIL because current behaviour only prints a notice and continues.

- [ ] **Step 3: Implement the pin-choice flow**
In `lib/shell/common.sh`, replace `notify_if_newer_ubuntu_lts_exists` with a choice-driven flow using the existing numbered selector UX. Keep the pin in `config/shared/opencode.conf`. Ensure no temporary floating version is used.

- [ ] **Step 4: Keep the scope narrow**
Apply this only to true wrapper-owned defaults such as `OPENCODE_UBUNTU_LTS_VERSION`. Do not reintroduce `OPENCODE_VERSION` as a pinned wrapper default.

- [ ] **Step 5: Run the targeted tests to verify pass**
Run: `./tests/shared/test-runtime.sh`
Expected: PASS for keep, update, and cancel flows.

- [ ] **Step 6: Commit**

```bash
git add tests/shared/test-runtime.sh scripts/shared/opencode-build lib/shell/common.sh config/shared/opencode.conf
git commit -S -m "fix: Enforce Explicit Choices for Pinned Ubuntu LTS Updates

- Replace the passive newer-version notice with an explicit keep, update, or cancel decision so wrapper-owned pins never float silently.
- Keep the Ubuntu LTS pin in shared config and verify the build path continues to honour the chosen pinned value on every run."
```

### Task 4: Rebuild Status Output as a Readable Diagnostic Summary

**Files:**
- Modify: `lib/shell/common.sh`
- Modify: `scripts/shared/opencode-status`
- Test: `tests/shared/test-runtime.sh`
- Test: `tests/shared/test-args.sh`

- [ ] **Step 1: Write the failing tests**
Add tests that assert:
- status output is grouped and human-readable
- colour is applied only as an enhancement
- it prints all relevant configurable items even when unset or missing
- it shows:
  - container state
  - lane, upstream, wrapper, commit stamp
  - container port
  - host mapping
  - configured host port
  - development root mount
  - selected project mount
  - config/secrets presence
- it reports actual live mounts, not only expected paths
- it does not print secret values
- help text matches the real picker behaviour and side effects

- [ ] **Step 2: Run the targeted tests to verify failure**
Run: `./tests/shared/test-runtime.sh && ./tests/shared/test-args.sh`
Expected: FAIL because summary output is flat, incomplete, and still calls managed-server recovery from inside `print_container_summary`.

- [ ] **Step 3: Implement readable status rendering**
Refactor `print_container_summary` into smaller summary helpers in `lib/shell/common.sh`. Keep output human-oriented with clear sections such as `Container`, `Identity`, `Server`, `Mounts`, and `Config`.

- [ ] **Step 4: Add colour carefully**
Use ANSI colour only when writing to a TTY. Keep explicit words alongside colour:
- normal: default
- issue: red
- warning: amber/yellow
- good: green

- [ ] **Step 5: Resolve the read-only expectation**
Move any managed-server repair behaviour out of the summary path, or make it explicit and documented if the repo still intends `status` to heal. The planned direction is read-only diagnostics.

- [ ] **Step 6: Run the targeted tests to verify pass**
Run: `./tests/shared/test-runtime.sh && ./tests/shared/test-args.sh`
Expected: PASS for formatting, mount visibility, and safer diagnostics.

- [ ] **Step 7: Commit**

```bash
git add tests/shared/test-runtime.sh tests/shared/test-args.sh scripts/shared/opencode-status lib/shell/common.sh
git commit -S -m "fix: Rework Status Output Around Runtime Diagnostics

- Reformat status output into readable sections with explicit port, mount, and config reporting so users can see the real runtime contract at a glance.
- Add terminal-safe colour cues and stop relying on implicit recovery behaviour so status acts as a clearer diagnostic command."
```

### Task 5: Update Documentation for Global Versus Project Config and Project Selection

**Files:**
- Modify: `README.md`
- Modify: `docs/shared/usage.md`
- Test: `tests/shared/test-args.sh`

- [ ] **Step 1: Write the failing doc-oriented assertions**
Add or adjust tests that check help and usage text for:
- mandatory project selection
- `/workspace/opencode-development` and `/workspace/opencode-project`
- global versus project config split
- four mandatory mounts
- pinned Ubuntu LTS choice flow

- [ ] **Step 2: Run the targeted tests to verify failure**
Run: `./tests/shared/test-args.sh`
Expected: FAIL because the docs and help still describe the old runtime and pin-notice flow.

- [ ] **Step 3: Update `README.md`**
Document:
- wrapper-global config in `config/shared/opencode.conf`
- workspace-scoped wrapper config in `config.env` and `secrets.env`
- OpenCode global config in `~/.config/opencode/opencode.json`
- OpenCode project config in the selected project root as `opencode.json` and `.opencode/`
- mandatory direct-child project picker from `OPENCODE_DEVELOPMENT_ROOT`
- all four required mounts

- [ ] **Step 4: Update `docs/shared/usage.md`**
Document:
- picker order: workspace, then target/container, then project
- default workdir at `/workspace/opencode-project`
- status output expectations
- pinned Ubuntu LTS keep/update/cancel flow

- [ ] **Step 5: Run the targeted tests to verify pass**
Run: `./tests/shared/test-args.sh`
Expected: PASS for updated usage/help coverage.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/shared/usage.md tests/shared/test-args.sh
git commit -S -m "docs: Document Project-Scoped OpenCode Runtime Behaviour

- Explain the split between wrapper config, OpenCode global config, and OpenCode project config so the runtime model matches upstream terminology and wrapper behaviour.
- Document the mandatory project picker, four-mount contract, and explicit Ubuntu pin update flow so users can predict container recreation and build choices."
```

### Task 6: Full Verification Pass

**Files:**
- Verify only: `tests/shared/test-all.sh`
- Optional verify: `tests/shared/test-build-smoke.sh`

- [ ] **Step 1: Run the full test suite**
Run: `./tests/shared/test-all.sh`
Expected: PASS

- [ ] **Step 2: Run optional smoke validation if environment allows**
Run: `OPENCODE_ENABLE_SMOKE_BUILDS=1 ./tests/shared/test-build-smoke.sh`
Expected: PASS with real build validation, or document clearly if not run.

- [ ] **Step 3: Review for spec coverage**
Check that the final implementation covers:
- OpenCode global versus project config split
- mandatory direct-child project selection
- all four required mounts
- `/workspace/opencode-project` default workdir
- readable status output with colour
- explicit pinned-version choice handling

- [ ] **Step 4: Final commit or split commits if clearer**
Keep commits aligned to the task boundaries above. Do not combine unrelated changes if the history becomes harder to scan.
