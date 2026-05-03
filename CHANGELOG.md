# Changelog

All notable changes to **bruto-pascal** are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.1] — 2026-05-03

### Added
- **Units / `uses` clause.** Programs can `uses Foo, Bar;` to import
  declarations from sibling `.pas` units containing
  `unit Name; interface ... implementation ... end.`. Units are
  resolved against the source file's directory and the working
  directory, with cycle detection. Both the IDE (`build_job_at`) and
  the CLI (`brutop file.pas`) honour the search path. Unit init
  blocks (`begin ... end.` or `initialization ... end.`) are
  prepended to the program's main block.
- **Enum names in the watch window.** Codegen now emits proper
  `DW_TAG_enumeration_type` DWARF metadata, so lldb (and therefore
  the watch panel) prints `(Color) c = Green` instead of the raw
  ordinal `2`.
- **Variant record fields in the watch window.** Records now produce
  real DWARF struct types with one member per fixed field, the tag,
  and every variant's fields overlapping at the union offset. The
  IDE post-filters the lldb dump using the `.bruto-meta` variant
  table so the watch row only shows fields belonging to the active
  variant for the current tag value.
- New `Language::build_job_at(source, source_path)` so the host can
  pass the source file's on-disk path; languages that resolve
  imports use it to root the search path.
- Cooperative `BuildJob` trait in `bruto-lang` (`BuildPhase` /
  `BuildJob::poll`) so builds can be driven a step at a time by the
  IDE event loop instead of blocking it.
- Modal "Build" progress dialog that shows the current phase
  ("Compiling…", "Linking…", "Generating debug info…" on macOS) and
  has a Cancel button. Clicking Cancel drops the job, which kills the
  spawned linker / dsymutil child via `Drop`.
- `long-demo.pas` — 1,295-line feature demo exercising arrays,
  records, sets, enums, pointers, sorts, searches, recursion, trig
  Taylor series, and bulk table output.
- `docs/BRUTO-PASCAL-LANGUAGE.md` — full reference for the supported
  Pascal dialect (types, statements, builtins, directives) including
  the known gaps versus Standard Pascal / FPC.

### Changed
- `bruto-pascal-lang::codegen::CodeGen::emit_executable` is now a
  thin synchronous wrapper around three pollable building blocks:
  `emit_object`, `spawn_linker`, and `spawn_dsymutil`.
- IDE's `handle_build` routes through the new modal dialog instead of
  calling `language.build()` directly.

## [1.0.0] — 2026-05-03

First production release with full tri-platform support.

### Added
- **Linux** native builds (`x86_64-unknown-linux-gnu` and
  `aarch64-unknown-linux-gnu`).
- **Windows** native builds (`x86_64-pc-windows-msvc`) using the
  c3lang prebuilt LLVM 18 (which ships `llvm-config.exe`, missing
  from the official LLVM Windows installer).
- `bruto_lang::target` module: cfg-gated stdio symbol resolution
  (`__stdinp`/`__stdoutp`/`__stderrp` on Apple, `stdin`/`stdout`/
  `stderr` on glibc, `__acrt_iob_func(int)` calls on MSVC) plus a
  `console_capture_path()` helper rooted in `std::env::temp_dir()`.
- Scoop manifest auto-published to `aovestdipaperino/scoop-tokensave/
  bucket/brutop.json` on release.
- `release.yml` accepts a `tag` workflow_dispatch input so artifacts
  can be re-published into an existing GitHub release without
  cutting a new tag.

### Changed
- Codegen routes all paths through `std::env::temp_dir()` instead of
  hardcoded `/tmp/...` so source / object / capture files live under
  `%TEMP%` on Windows.
- Linker selection is platform-aware: `cc` on macOS/Linux, `clang`
  on Windows; `-no-pie` only on Linux; `-lm` skipped on Windows; on
  Windows-MSVC adds `-fuse-ld=lld -lmsvcrt -llegacy_stdio_definitions`
  to resolve UCRT references against LLVM's bundled lld-link.
- macOS-only debugger integration tests (`compile_and_run_simple_program`,
  `lldb_stops_at_breakpoint`) are cfg-gated to `target_os = "macos"`
  since they depend on Apple's `.dSYM` bundle layout.

### Fixed
- `R_X86_64_32` relocations in PIE link errors on Linux (codegen now
  passes `-no-pie` to `cc`).
- Windows `text`-mode IO byte-count assertion (`writeln(f, 'ABC')`
  emits 5 bytes on Windows due to `\r\n` translation, vs 4 on Unix).

## [0.9.10] — 2026-05-03

### Added
- `IdeOptions::on_desktop_ready` hook fired once after the desktop
  draws, used by the host application to run startup-time prompts
  (e.g. self-update check).
- Self-update flow (`bruto-pascal/src/update.rs`): polls GitHub
  `releases/latest` with a 2-second timeout, semver-compares against
  `CARGO_PKG_VERSION`, prompts a Y/N modal, downloads the platform
  tar.gz, replaces the binary via `self_replace`, then re-execs.
  Handles Homebrew Cellar layout (renames the version dir, updates
  the `<prefix>/bin/<binary>` symlink, patches `INSTALL_RECEIPT.json`)
  and the equivalent Scoop apps layout on Windows.

### Changed
- Binary renamed to `brutop` (the package and Homebrew formula stay
  `bruto-pascal`).
- All four first-party crates aligned at 0.9.10 in lockstep.
- `cargo fmt` applied across the workspace; CI fmt job scoped to the
  four first-party crates so turbo-vision's example files don't
  block it.

### Fixed
- Closing the editor that's currently being debugged now prompts
  "Closing this window will stop debugging. Do you want to close
  it?" before tearing down the lldb session.
- "Current statement" green bar now updates on the editor that's
  being debugged regardless of focus, and is cleared on
  `DebugEvent::Exited` even if focus has moved to the watch / output
  panel.
- F8 (step over) on the last statement of `main` no longer parks the
  user in dyld's bootstrap assembly — the debugger detects a stop
  with no user-source frame and auto-`continue`s so the process
  exits cleanly.
- Breakpoints on the last user statement and on `end.` both fire
  again (the `_end_bp` synthetic alloca was reinstated for the
  outermost block).

## [0.9.9] — 2026-05-03

First public release on Homebrew, macOS-only.

### Added
- About dialog with host-supplied body via `IdeOptions::about_text`.
- First-run config in `~/.config/bruto-pascal/config.toml` —
  `show_about_dialog_on_start` defaults to `true` and flips to
  `false` after the dialog is dismissed.
- Type-aware value editor on double-click of a watch row (`integer`,
  `real`, `boolean`, `char`); validates input before sending the
  `expr` to lldb.
- Window menu to re-open Watches / Output panels.
- Homebrew bottle distribution (`arm64_sonoma`, `x86_64_linux`) via
  `aovestdipaperino/homebrew-tap`.
- CI / Release GitHub Actions workflows mirroring the tokensave
  pipeline.
- `IdeOptions` plumbing in `bruto-ide` so the host application can
  influence first-run behaviour without the framework knowing about
  any specific config format.

### Changed
- Watches frame palette switched to gray (matches the panel interior).
- Watches and Output panels no longer auto-mount at startup; the
  user opens them via the Window menu.
- IdeOptions includes `on_about_shown` callback so the host can
  persist the "first-run-done" flag the moment the dialog dismisses.

### Fixed
- IDE no longer crashes after the first build/debug iteration with
  `RefCell already borrowed` (the watch double-click handler's
  borrow lifetime was extended too far).

## [0.1.0] — 2026-03-29

Initial public preview.

### Added
- TUI-based IDE built with Turbo Vision for Rust.
- Syntax-highlighted editor for a Mini-Pascal subset
  (program/var/begin/end, if/then/else, while/do, writeln/readln,
  arithmetic, comparisons, boolean operators).
- Single-column breakpoint gutter with red square markers, toggled
  by mouse click.
- LLVM code generation via inkwell with full DWARF debug metadata
  (source locations on every statement, variable debug info).
- `dsymutil` integration on macOS for proper debug symbol generation.
- Integrated lldb-based debugger: start/continue (F5), step over
  (F8), step into (F7), stop (Shift+F5).
- Execution line highlighting (green background) during debugging.
- Variable watch window displaying local variable values from
  lldb's `frame variable` output.
- Program console output captured to a file via compiled-in fprintf
  (independent of lldb's stdout).
- Output panel in a modeless Dialog with black background.
- Build (F9) and Run (Ctrl+F9) workflow with error reporting.
- Menu bar (File, Build, Debug, Help) with keyboard shortcuts.
- About dialog.
- Breakpoints supported on `end` keywords (all blocks, including
  the final `end.`).
- Debugger automatically stops when the program exits.
