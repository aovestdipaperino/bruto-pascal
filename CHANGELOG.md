# Changelog

## 0.1.0 (2026-03-29)

Initial release of Bruto Pascal IDE.

### Features

- TUI-based IDE built with Turbo Vision for Rust
- Syntax-highlighted editor for a Mini-Pascal subset (program/var/begin/end, if/then/else, while/do, writeln/readln, arithmetic, comparisons, boolean operators)
- Single-column breakpoint gutter with red square markers, toggled by mouse click
- LLVM code generation via inkwell with full DWARF debug metadata (source locations on every statement, variable debug info)
- dsymutil integration on macOS for proper debug symbol generation
- Integrated lldb-based debugger: start/continue (F5), step over (F8), step into (F7), stop (Shift+F5)
- Execution line highlighting (green background) during debugging
- Variable watch window displaying local variable values from lldb's `frame variable` output
- Program console output captured to a file via compiled-in fprintf (independent of lldb's stdout)
- Output panel in a modeless Dialog with black background
- Build (F9) and Run (Ctrl+F9) workflow with error reporting
- Menu bar (File, Build, Debug, Help) with keyboard shortcuts
- About dialog
- Breakpoints supported on `end` keywords (all blocks, including the final `end.`)
- Debugger automatically stops when the program exits
