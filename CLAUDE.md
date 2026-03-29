# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **Prerequisite**: LLVM 18 must be installed (`brew install llvm@18`)
- Build: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo build`
- Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo run`
- Test: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test`
- Run a single test: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test <test_name>`

## Overview

A TUI-based Mini-Pascal IDE built with the `turbo-vision` crate and LLVM (via `inkwell`). The IDE provides:
- A syntax-highlighted editor for a Pascal subset
- A breakpoint gutter (click to toggle red square markers)
- LLVM code generation with DWARF debug info
- An lldb-based integrated debugger with variable watch
- A build output terminal panel

## Architecture

The application follows turbo-vision's Application/Desktop/View hierarchy with a custom event loop in `main.rs`. Key data flow:

1. **Editor** (turbo-vision `EditWindow`) holds Pascal source text
2. **F9 Build**: source -> `Parser` -> AST -> `CodeGen` (inkwell/LLVM IR + DWARF) -> object file -> `cc` linker -> executable
3. **F5 Debug**: spawns `lldb` subprocess, communicates via stdin/stdout pipes with a reader thread

### Window Layout

The desktop contains three windows:
1. **Editor window** (`IdeEditorWindow`) — a custom `Window` containing the breakpoint gutter and editor as interior children, with scrollbars/indicator as frame children. The gutter scroll is synced from the editor's vertical scrollbar on every draw.
2. **Watch window** — a standard `Window` containing a `WatchPanel` view that shows debugger variable values.
3. **Output window** — a standard `Window` containing a `TerminalWidget` for build/run output.

### Module Responsibilities

- `main.rs` — Application setup, menu/status bar, event loop, command dispatch. Contains `Rc<RefCell<...>>` View wrappers (WatchView, OutputView) to share state between Window children and the event loop.
- `ide_editor.rs` — `IdeEditorWindow`: a custom Window that embeds a `BreakpointGutter` and `Editor` side-by-side as interior children, with scrollbars/indicator as frame children. Uses the same SharedEditor/SharedScrollBar/SharedIndicator wrapper pattern as turbo-vision's EditWindow. Syncs gutter scroll from the editor's vertical scrollbar on every draw.
- `commands.rs` — Custom command ID constants (CM_BUILD, CM_DEBUG_*, etc.)
- `pascal_syntax.rs` — `SyntaxHighlighter` trait impl for Pascal; supports `//`, `{ }`, `(* *)` comments and multiline state
- `ast.rs` — AST node types; every node carries a `Span { line, column }` for error messages and DWARF metadata
- `parser.rs` — Lexer + recursive descent parser for Mini-Pascal. Grammar supports: program/var/begin-end, if/then/else, while/do, writeln/readln, assignment, arithmetic, comparisons, boolean ops
- `codegen.rs` — Translates AST to LLVM IR via inkwell. Emits runtime helpers (printf/scanf wrappers) as IR. Attaches `DICompileUnit`/`DISubprogram`/`DILocalVariable` debug metadata so lldb can set breakpoints and inspect variables. Outputs `.o` file and links with `cc`.
- `debugger.rs` — Manages an lldb child process. A reader thread drains stdout into an `mpsc::channel`; `poll()` parses stop locations, variable values, and exit status into `DebugEvent` variants.
- `gutter.rs` — `BreakpointGutter` custom View. 3 chars wide, draws red `■` for breakpoints and `►` for the current execution line. MouseDown toggles breakpoints.
- `watch_window.rs` — `WatchPanel` View displaying `name = value` pairs from the debugger.

### turbo-vision API patterns used

- `Window::add()` for interior children (relative coords, auto-converted to absolute)
- `Window::add_frame_child()` for scrollbars/indicator on the frame edge
- `Editor::with_scrollbars()` + `Rc<RefCell<ScrollBar>>` for shared scrollbar access
- `Editor::set_highlighter()` for syntax coloring
- `MenuBar::new(bounds)` + `add_submenu()` with `MenuItem::with_shortcut(text, cmd, key_code, shortcut_label, help_ctx)`
- `StatusItem::new(text, key_code, command)`
- `TerminalWidget::append_line()` / `append_line_colored()` for build output
- View trait requires: `bounds`, `set_bounds`, `draw`, `handle_event`, `get_palette` (return `None` for custom views)
