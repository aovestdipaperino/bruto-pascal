# Bruto Pascal

A TUI-based Mini-Pascal IDE and compiler. The IDE side is built with
[bruto-ide](https://github.com/aovestdipaperino/bruto-ide); the language side
with [bruto-pascal-lang](https://github.com/aovestdipaperino/bruto-pascal-lang).
Both ride on LLVM 18 (via inkwell) for codegen with full DWARF debug info, and
embed lldb for stepping.

## What it speaks

Most of Wirth's 1973 Pascal Report plus parts of ISO 7185 (conformant array
parameters) and a useful slice of Turbo Pascal (string ops, type casts,
`{$R+}` / `{$Q+}` / `{$I+}` directives, `forward`).

See [bruto-pascal-lang/GRAMMAR.md](bruto-pascal-lang/GRAMMAR.md) for the BNF
and [bruto-pascal-lang/README.md](bruto-pascal-lang/README.md) for the feature
list. [LANGUAGE-TODO.md](LANGUAGE-TODO.md) tracks what's still missing
(units, OO, exceptions).

## Features

- Syntax-highlighted editor for Pascal
- Click-to-toggle breakpoint gutter
- LLVM IR + DWARF; on macOS we run `dsymutil` to make lldb happy
- Integrated lldb: step over (F8), step into (F7), continue (F5)
- Variable watch panel (decodes set bitmasks into Pascal literal form)
- Build (F9), Run (Ctrl+F9), Debug (F5)
- Output panel for compiler + program console output

## Prerequisites

```bash
brew install llvm@18
```

## Build & Run

IDE:

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo run
```

CLI compiler:

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo run -- -r SAMPLE.PAS
```

Tests (must run serially because they share a capture file):

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test --workspace -- --test-threads=1
```

## Architecture

| Crate | Purpose |
|-------|---------|
| [bruto-ide](https://github.com/aovestdipaperino/bruto-ide) | Pluggable TUI IDE framework with `Language` trait |
| [bruto-pascal-lang](https://github.com/aovestdipaperino/bruto-pascal-lang) | Mini-Pascal parser, LLVM codegen, syntax highlighter |
| [bruto-lang](https://github.com/aovestdipaperino/bruto-lang) | Shared LLVM runtime (printf wrappers, file I/O, capture) |
| **bruto-pascal** (this repo) | Binary combining the three |

## License

MIT
