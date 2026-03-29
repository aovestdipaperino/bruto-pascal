# Bruto Pascal

A TUI-based Mini-Pascal IDE built with [bruto-ide](https://github.com/aovestdipaperino/bruto-ide) and [bruto-pascal-lang](https://github.com/aovestdipaperino/bruto-pascal-lang).

This is the binary that wires the pluggable IDE framework to the Mini-Pascal language implementation. The entire `main.rs` is three lines:

```rust
fn main() -> turbo_vision::core::error::Result<()> {
    bruto_ide::ide::run(Box::new(bruto_pascal_lang::MiniPascal))
}
```

## Features

- Syntax-highlighted editor for Mini-Pascal
- Breakpoint gutter (click to toggle red square markers)
- LLVM code generation with DWARF debug info
- Integrated lldb debugger: step over (F8), step into (F7), continue (F5)
- Variable watch panel
- Build (F9), Run (Ctrl+F9), Debug (F5) workflow
- Output panel for build messages and program console output

## Prerequisites

```bash
brew install llvm@18
```

## Build & Run

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo run
```

## Architecture

| Crate | Purpose |
|-------|---------|
| [bruto-ide](https://github.com/aovestdipaperino/bruto-ide) | Pluggable TUI IDE framework with `Language` trait |
| [bruto-pascal-lang](https://github.com/aovestdipaperino/bruto-pascal-lang) | Mini-Pascal parser, LLVM codegen, syntax highlighter |
| **bruto-pascal** (this repo) | Binary combining the two |

## License

MIT
