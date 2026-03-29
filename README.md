# Bruto Pascal

A TUI-based Mini-Pascal IDE built with [Turbo Vision for Rust](https://github.com/aovestdipaperino/turbo-vision-4-rust) and LLVM.

Bruto Pascal provides an integrated development environment for a subset of Pascal, featuring syntax-highlighted editing, LLVM-powered compilation with full DWARF debug info, and an lldb-based interactive debugger with breakpoints and variable inspection.

## Screenshot

```
 File  Build  Debug  Help
╔[■]═ Untitled.pas ═══════════════════╗┌[■]═ Watches ═══┐
║■program Hello;                      ║│x = 55          │
║ var                                 ║│i = 11          │
║   x: integer;                       ║│                 │
║   i: integer;                       ║│                 │
║ begin                               ║│                 │
║►  x := 0;          ← execution line ║│                 │
║   i := 1;                           ║│                 │
║   while i <= 10 do                  ║│                 │
╚═════════════════════════════════════╝└─────────────────┘
┌[■]═ Output ═════════════════════════════════════════════┐
│Debugger started.                                        │
│Sum of 1..10 = 55                                        │
│Correct!                                                 │
└─────────────────────────────────────────────────────────┘
 F5 Debug   F7 Step   F8 Next   F9 Build   Alt-X Exit
```

## Features

- Syntax-highlighted editor with a breakpoint gutter (click to toggle red square markers)
- Recursive descent parser for a Mini-Pascal subset
- LLVM code generation via inkwell with full DWARF debug metadata
- Integrated lldb-based debugger with step over, step into, continue, and variable watch
- Build (F9), Run (Ctrl+F9), Debug (F5) workflow
- Execution line highlighting during debugging
- Program console output captured to a separate panel

## Supported Language

The Mini-Pascal subset supports:

- `program` / `var` / `begin` / `end` structure
- Types: `integer`, `string`, `boolean`
- Statements: assignment (`:=`), `if`/`then`/`else`, `while`/`do`, `writeln`, `write`, `readln`
- Expressions: arithmetic (`+`, `-`, `*`, `div`, `mod`), comparisons (`=`, `<>`, `<`, `>`, `<=`, `>=`), boolean operators (`and`, `or`, `not`)
- Comments: `//`, `{ }`, `(* *)`
- Breakpoints on any statement line including `end`

## Prerequisites

LLVM 18 must be installed:

```bash
brew install llvm@18
```

## Build & Run

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo build
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo run
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| F5 | Start debugger / Continue |
| F7 | Step into |
| F8 | Step over |
| F9 | Build |
| Ctrl+F9 | Build and run |
| Shift+F5 | Stop debugger |
| Alt+X | Exit |

## Architecture

The application follows Turbo Vision's Application/Desktop/View hierarchy:

1. **Editor** (`IdeEditorWindow`) holds Pascal source text with a breakpoint gutter and syntax highlighting
2. **F9 Build**: source text passes through the `Parser` into an AST, then through `CodeGen` (inkwell/LLVM IR with DWARF metadata), emitting an object file linked with `cc` and finalized with `dsymutil`
3. **F5 Debug**: spawns an `lldb` subprocess, communicates via stdin/stdout pipes with a reader thread, program output captured via a separate file channel

### Modules

| Module | Purpose |
|--------|---------|
| `main.rs` | Application setup, menus, event loop, command dispatch |
| `ide_editor.rs` | Custom Window with breakpoint gutter and editor side-by-side |
| `gutter.rs` | Single-column breakpoint gutter View |
| `pascal_syntax.rs` | Syntax highlighter for Pascal |
| `ast.rs` | AST node types with source spans |
| `parser.rs` | Lexer and recursive descent parser |
| `codegen.rs` | LLVM IR generation with DWARF debug info |
| `debugger.rs` | lldb subprocess management and output parsing |
| `watch_window.rs` | Variable watch panel |
| `output_panel.rs` | Output dialog with TerminalWidget |
| `commands.rs` | Custom command ID constants |

## License

MIT
