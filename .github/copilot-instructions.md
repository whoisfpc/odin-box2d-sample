# Copilot instructions — odin-box2d-sample

Purpose: Short, actionable guidance for AI coding agents to be immediately productive in this repository.

## Quick facts ✅
- Language: **Odin** (requires odin dev-2025-12 as noted in `README.md`).
- Graphics: **OpenGL + GLFW**, UI via **Dear ImGui** (bindings in `odin-imgui/`).
- Physics: **Box2D** (bindings under `vendor:box2d`).
- Tasking: **enkiTS** worker/task scheduler (binding in `odin-enkiTS/`).
- Working directory MUST be the project root (main checks `data/droid_sans.ttf` and exits otherwise).

## How to build & run 🔧
- Debug (with sanitizer): run the included script from project root:

  ```bat
  run.bat        # default: debug mode -> `odin run src -debug -sanitize:address`
  run.bat -speed # runs `odin run src -o:speed`
  ```

- VS Code tasks available (see workspace tasks):
  - `raddebugger`: `odin build src -debug -out:sample.exe` (useful for producing a debug binary)
  - `run`: runs `run.bat` (wraps common run modes)

- Note: third-party submodules (e.g. `odin-imgui`) have their own build notes in their `README.md`.

## High-level architecture & data flow 🧭
- `src/main.odin` - program entry: sets up GLFW, ImGui, registers samples, runs main loop.
- `src/sample.odin` - sample framework: `Sample_Context`, `Sample` struct, sample lifecycle helpers and persistence (`settings.json`).
- `src/*_sample.odin` files (e.g. `sample_bodies.odin`, `sample_benchmark.odin`) - specific sample implementations and `create` fns.
- `src/draw.odin` - rendering layer: builds VAOs/VBOs, loads shaders in `data/`, font baking via stb_truetype.
- ImGui backends: included via `odin-imgui` and `imgui_impl_glfw`, `imgui_impl_opengl3` imports in `main.odin`.
- Tasks: samples create an `enki` `TaskScheduler` and use worker threads (controlled by `s_ctx.worker_count`).

## Project-specific conventions & patterns 🔍
- Samples are registered using `register_sample("Category", "Name", Foo_create)` and sorted in `register_all_samples()`.
  - Example: `register_sample("Bodies", "Weeble", Weeble_create)` in `sample.odin`.
- File-scoped/private functions use `@(private = "file")` and C callbacks use `proc "c"` or `proc "contextless"` (GLFW expects C-style callbacks).
- Persistent settings are stored in `settings.json` via `sample_context_save` / `load` (see `SETTINGS_PATH` in `sample.odin`).
- Rendering shaders and assets live under `data/` and are loaded by file name (e.g. `data/line.vs`, `data/point.fs`, `data/droid_sans.ttf`).
- Generated or vendor bindings should not be edited lightly: `odin-imgui/` is generated via `dear_bindings`, `odin-enkiTS/` via `odin-c-bindgen`.

## Debugging & noise signals ⚠️
- Use the debug mode (`run.bat`) to enable `-sanitize:address`; helpful for memory issues.
- Box2D asserts are hooked: `b2.SetAssertFcn(assert_fcn)` in `main.odin` — assert output goes to stdout.
- After graphics changes verify shader compilation and check `check_opengl()` usage in `draw.odin`.
- Ensure the working dir is project root (fonts and shader files must be reachable).

## Typical small change checklist (for contributors / agents) ✅
- To add a new sample:
  1. Implement `Foo_create` following patterns in `sample_bodies.odin` / `sample_benchmark.odin`.
  2. Call `register_sample("Category", "Name", Foo_create)` in `register_all_samples()`.
  3. If you add UI/config, persist default values in `sample_context_load` and include them in `sample_context_save`.
  4. Run `run.bat` (debug) and validate behaviour and UI.

- To change rendering:
  - Modify `data/*.vs|*.fs`, update `draw.*` code (create_program_from_files usage), test shader compile path and `flush_*` functions.

## Files to inspect first 📚
- `src/main.odin` — app lifecycle and ImGui glue
- `src/sample.odin` — sample registration, lifecycle, saving
- `src/draw.odin` — renderer, shader/atlas handling
- `src/sample_*.odin` — concrete sample implementations
- `odin-imgui/README.md` — backend/build details

## What’s not here / quick notes 📝
- No test harness found — there are no explicit unit tests or CI tests in repo.
- Some TODOs exist in source (e.g. `DrawSolidCircleFcn` marked `// todo`), so prefer incremental, local validation when changing physics–render logic.

---
If any section is unclear or you'd like more examples (e.g. a skeleton to add a new sample or how to run a GPU-debugging iteration), say which part and I will expand it. 🙋‍♂️
