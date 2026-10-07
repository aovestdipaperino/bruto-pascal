# Changelog

All notable changes to **bruto-pascal** are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.3] — 2026-10-07

### Added
- **Build options.** `Build > Options...` opens a dialog to choose
  **Debug** (DWARF debug info, unoptimized) or **Retail** (no debug info,
  optimized), and for Retail whether to optimize for **Size**, **Both**
  (balanced, default) or **Speed** (LLVM `Os` / `O2` / `O3`). The choice
  is saved under `[build]` in `config.toml` and used by Build and Run;
  Debug sessions always build in Debug mode so lldb has symbols. The
  command line gains matching `--debug`, `--retail` and
  `--optimize size|both|speed` flags.
- **Disassembly window.** `Windows > Disassembly` (only enabled once the
  current source has been built successfully) shows the build's
  assembly listing in a grey window (like Watches / Call Stack). Debug
  builds carry DWARF `.loc` mappings back to Pascal source lines: clicking
  an instruction scrolls the source editor there, and clicking its left
  margin toggles a breakpoint on that line — the same breakpoint state as
  the editor's own gutter, so it takes effect immediately in a running
  debug session. Retail builds show the listing with a notice that there's
  no source mapping (debug info is stripped before assembly is emitted),
  so neither click does anything.
  The listing is laid out for reading rather than shown raw: assembler
  bookkeeping (CFI, alignment, visibility directives, debug-only labels
  and the DWARF sections) is hidden, each function starts after a blank
  row with its name flush left, branch targets are indented, and
  instructions line up in mnemonic / operands / comment columns with
  syntax colours. Whenever the mapped Pascal line changes, that line's
  source text is shown above the instructions it produced, Turbo Debugger
  style; those rows are clickable like instructions.
- **Source-to-assembly correlation.** Double-clicking a line in the source
  editor highlights it in cyan and scrolls the Disassembly window to the
  matching instructions, also highlighted in cyan. Independent of the
  debugger's green "current statement" highlight and the breakpoint
  margin, so all three can be visible at once without being confused for
  each other. Cleared at the start of the next build.
  Clicking a row in the Profile window gives its line the same cyan
  highlight in the editor (scrolled into view, focus stays on Profile)
  and in the Disassembly window.
- **Line profiler.** `Build > Profile` (Shift-F9) compiles the program with
  timing hooks on every routine and statement, links a small C runtime,
  runs it, and shows the results two ways: a percentage column with heat
  tinting beside the gutter, and a Profile window with a collapsible
  routine > line call tree (Enter or double-click jumps to the line). The
  column appears only after a profile run and clears on the next build or
  edit. Normal builds are unaffected.
- **Tool windows resize their content.** Watches, Call Stack, Profile and
  Disassembly now stretch their contents when the window is zoomed or
  resized, instead of leaving the extra area blank.

- **Hidden files in file dialogs.** Open and Save As no longer list
  dot-folders and dot-files (`.git`, `.env`, ...); a "Show hidden"
  checkbox beside the Files label brings them back while browsing. The
  checkbox is embedded (drawn on the dialog background, not a cyan box).
- **Code obfuscation.** `Build > Options...` gains an "Obfuscate code"
  checkbox. When on, the build renames every user-defined identifier to a
  meaningless name (consistently, so the program still runs) and inserts
  opaque, always-true predicates with dead bogus blocks to obscure the
  control-flow graph. The bogus instructions carry a line-0 debug
  location, so a Debug build's disassembly stays aligned to the real
  Pascal lines. Applies to any build profile.

### Changed
- **turbo-vision 4.0.3.** Migrated the IDE from the 3.x line to
  turbo-vision 4.x (consumed from crates.io; the submodule tracks `main`).
  The 4.x line dropped `views::terminal_widget`, so the build/run output
  pane is now vendored in `bruto-ide`. 4.0.3 adds the hidden-file toggle
  and embedded checkboxes the file dialogs use.
- **Upgraded to turbo-vision 3.0.0.** The IDE now consumes the crates.io
  release directly (the `turbo-vision-4-rust` submodule is kept at the
  `v3.0.0` tag for reference and excluded from the workspace, since 3.0
  turned that repo into its own Cargo workspace). Every custom view
  (`BreakpointGutter`, `WatchPanel`, `CallStackPanel`, the build progress
  label) moved its base fields into a `ViewCore` and draws in
  owner-relative coordinates; `IdeEditorWindow` and `OutputPanel` are now
  `WindowLike` types generated through `impl_view_for_window!`, and the
  hand-written `SharedX` newtypes were replaced by the library's
  `Shared<T>`. Typed flags (`State::SHADOW`, `MsgBox::YES_BUTTON`),
  `MenuItemBuilder` / `StatusItemBuilder`, `Handle<InputLine>` for the
  value editor, and `Application::execute_modal` for the build progress
  dialog replace the removed 2.x APIs. Layout and behaviour are unchanged.

### Fixed
- **Cursor flicker.** After the first build the terminal's hardware cursor
  was left visible on top of the editor's own caret, and every redraw
  dragged it across the screen, so it flickered whenever the mouse moved.
  It now stays hidden outside dialogs.

## [1.0.2] — 2026-05-04

### Fixed
- **StatusLine hint now actually shows when the message is long.**
  Rendering was gated on `x + hint.len() + 2 < width`, so on a typical
  80-column terminal — where the existing items already use ~56
  columns — anything longer than ~22 characters was silently
  suppressed (this is why the compile-error message wasn't appearing
  in the status bar). Now renders as many characters as fit and
  appends an ellipsis when truncated.
- **Undo / Redo menu enablement now follows the actual stack state.**
  Previously both entries were enabled whenever an editor had focus;
  they're now greyed out at the ends of the history (clean buffer →
  Undo greys; mid-history with no recent edit → Redo greys; any fresh
  edit clears the redo stack and greys Redo immediately). Added
  `can_undo()` / `can_redo()` methods to the `Editor` trait so any
  implementation can opt in.
- **Alt+X now actually quits the IDE.** The File → Exit menu entry and
  the Alt-X status item were both registered with `0x012D` — a stale
  Borland-era scancode — while turbo-vision's crossterm bridge emits
  `KB_ALT_X = 0x2D00` for the real key event, so the status-line
  shortcut comparison never matched. Switched both registrations to
  the actual `KB_ALT_X` constant.
- **Paste over a selection now undoes / redoes in a single step.** The
  underlying `EditorWindow::clip_paste` used to push two separate undo
  entries — `delete_selection()` then `insert_text()` — so a single
  Ctrl+Z only un-inserted the new text and left the original selection
  still gone. Introduced an `EditAction::Compound(Vec<EditAction>)`
  variant; `clip_paste` now bypasses the helper push paths and emits
  one compound entry covering both the delete and the insert. Cut was
  already atomic (single `DeleteText`); copy doesn't touch the buffer.

### Added
- **Compile-error feedback.** When a build fails the IDE now (a) pops
  a modal error dialog with the full message at the end of
  compilation, (b) paints a red bar across the offending editor row,
  and (c) surfaces a compact `<line>:<col>: <message>` in the status
  bar whenever the caret sits on that line. The status hint strips
  the noisy `Parse error: line ` prefix and no longer renders a
  leading `- ` separator, so the row reads cleanly. The gutter stays
  exclusively for breakpoints. Cleared at the start of every new
  build; linker / dsymutil errors that don't carry a line number
  still get the dialog but no bar.
- **Edit menu.** New `Edit` submenu with Undo (Ctrl+Z), Redo (Ctrl+Y),
  Cut (Ctrl+X), Copy (Ctrl+C), Paste (Ctrl+V), and Select All (Ctrl+A).
  The keyboard shortcuts already worked because the underlying editor
  view captures them directly; the menu adds a visible affordance and
  routes its commands through the same trait. Cut/Copy grey out when
  there's no selection. The clipboard / undo / select-all operations
  now live on the `Editor` trait in `turbo-vision` so any editor
  implementation must support them; default impls are no-ops for
  non-text editors.
- **Call Stack window.** New `Windows → Call Stack` entry that opens a
  panel listing the current `bt` frames during debugging. Hidden by
  default; survives close/re-open like the Watches and Output panels.
  The debugger now sends `bt` after every stop and parses
  `frame #N: ...` lines into a new `DebugEvent::Frames` variant.
  Clicking a frame focuses the editor showing that source file (matched
  by basename), scrolls to the frame's line, and moves the green
  "current statement" bar to that line. The bar follows a new
  `exec_editor` override so it can land in a unit file when the picked
  frame isn't in the main program; the next stop / step / continue
  resets it back to the actual debug target. The currently selected
  frame is also highlighted in the panel with the same green
  background as the editor's current-line bar. Frames without a
  parseable `at file:line` (e.g. `dyld\`start + 1234`) are filtered at
  the parser so the panel only ever shows actionable rows.

### Fixed
- Green "current statement" bar showing on the caller line when a
  breakpoint hit inside a procedure / function. After every stop the
  IDE now requests `bt`, whose response echoes another
  `* thread #1 ... stop reason = ...` header plus every frame in the
  stack; the buggy `parse_stop_location` heuristic walked accumulated
  lldb output and grabbed the most recent `at file:line` it saw —
  which after `bt` was `frame #1` (the caller in `main`). Stop
  detection now only fires when the debugger was Running at poll
  entry, and only inspects the current line for an inline location
  instead of mining history. Step-over / step-into now also flip the
  state back to Running so the next stop is recognised as fresh.

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
