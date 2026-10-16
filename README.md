# Bruto Pascal

<p align="center">
  <a href="https://ai.enzolombardi.net/"><img src="https://img.shields.io/badge/built%20with-AI-D97757?style=flat-square&labelColor=101010&logo=anthropic&logoColor=white" alt="Built with AI — part of Enzo Lombardi's AI portfolio"></a>
</p>


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

## A demo

[examples/writer](examples/writer) is Bruto Writer, a small word
processor in Free Vision: menus, an editor, dialogs and file dialogs,
with document logic that uses classes, interfaces, generics, Variants,
Currency, run-time type information and component streaming. Its
command-line twin, `writercheck.pas`, prints the same output and writes
the same files with Bruto Pascal as with FPC 3.2.2.
Free Vision comes from FPC's sources, an optional submodule: run
`git submodule update --init --checkout -- third_party/fpc` to fetch
it, and see the demo's README for the `brutop -Fu ...` command.

## Features

- Syntax-highlighted editor for Pascal
- Click-to-toggle breakpoint gutter
- LLVM IR + DWARF; on macOS we run `dsymutil` to make lldb happy
- Integrated lldb: step over (F8), step into (F7), continue (F5)
- Variable watch panel (decodes set bitmasks into Pascal literal form)
- Build (F9), Run (Ctrl+F9), Debug (F5)
- A primary file, as in Turbo Pascal (Build › Primary file…): the
  program Build, Run, Debug and Profile work on, whichever window you
  are editing. Without one, a unit's window builds a program that uses
  it (an open one, else one in the unit's folder)
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
