# Changelog

All notable changes to **bruto-pascal** are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Strings are freed.** AnsiStrings and UnicodeStrings are reference
  counted: storing one counts it, the one it replaces is released,
  routines release their string locals and value parameters, and the
  strings a statement makes but never stores are freed when it ends
  (loop conditions on each test). Free Vision's Unicode demo now stays at
  about 220 KB while idle (FPC's: 188 KB), where it grew by megabytes a
  second. `BRUTO_NO_ARC=1` at compile time turns it off.
- **AnsiStrings are length-prefixed**, laid out as FPC's: a header with a
  marker, a reference count and the length before NUL-terminated
  characters. Strings can hold #0 (and `write` writes it), `Length` is
  immediate, and a short string's #0 characters survive conversion. C
  strings from elsewhere still work. The string runtime is written in
  Pascal (`rtl/brutostrings.pp`) and is part of every program, even
  one compiled through `CodeGen` directly; the profiler leaves it out.
  With this, Free Vision's one-row radio-button box draws as FPC's does:
  all 26 compared scenarios now match.
- **Checked against real FPC**: FPC's Free Vision examples, built from
  trunk sources with both FPC trunk and Bruto, now draw the same screens
  in 25 of the 26 scenarios compared (menus, dialogs, the file dialog,
  the editor, the ASCII chart, keytest, listdemo, the Unicode demo). The
  exception, a one-row radio-button box, comes from a Free Vision bug
  (it measures UnicodeStrings through `PString`) that FPC hits with
  garbage lengths and Bruto with NUL-terminated ones.
- `{$codepage cp437}`: a string literal's characters 128..255 are code
  page 437's when it becomes a UnicodeString (Free Vision's history
  button `#222'v'#221` is `▐v▌`); as an AnsiString it keeps its bytes.
  String literals become UnicodeStrings at compile time.
- `GetFPCHeapStatus` reports the malloc zone's figures on macOS.
- **Free Vision's Unicode build (`FV_UNICODE`) runs**, so FPC's examples
  compile unmodified, `testuapp` included: menus, status line, dialogs,
  list boxes and the editor show CJK (two cells wide), Cyrillic, Greek
  and combining characters, and typed UTF-8 text (emoji too) reaches
  input lines and the editor. New for it:
  - `UnicodeString` and `WideChar` as FPC has them (UTF-16, converted to
    and from UTF-8 AnsiStrings), with `Length`, `Copy`, `Pos`, `Delete`,
    `Insert`, `SetLength`, `UpCase`, indexing, concatenation and
    comparison; `#$2502` character codes; `array of WideChar` constants.
  - `for X in ...` loops over strings, arrays and enumerator objects.
  - Video's enhanced mode (`InitEnhancedVideo`, `TEnhancedVideoCell`,
    `EnhancedVideoBuf`, display widths), a `GraphemeBreakProperty` unit
    with the grapheme cluster enumerator, an `fpwidestring` unit, and
    `UnicodeChar` in enhanced key events.
  - `Utf8ToUnicode`, `UnicodeToUtf8`, `UTF8ToString`, `UTF8Decode`,
    `UTF8Encode`, `CompareByte`, `IndexByte`, `SetCodePage`,
    `StringCodePage`.
  - `BRUTO_DUMP_IR=file` writes a build's LLVM IR, for debugging.
- **All of Free Vision's example programs run** (without `FV_UNICODE`):
  `keytest`, `listdemo` (mouse double-click included), `filedlg` (the
  file open dialog reading the directory), `demoedit`, `colorselonly`
  and `demostatuses`. New for them: a `SysUtils` unit (`Format`,
  `IntToStr`, `IntToHex`, `UpperCase`, `Trim`, `StrToInt`,
  `FileExists`, `Sleep`...), a `cwstring` unit, a bare `inherited;`,
  `New(PType, Init)` without parentheses, and `sizeof` of built-in types
  in `{$IF}`.
- **FPC's Free Vision demo, `testapp.pas`, runs** (built without
  `FV_UNICODE`): menus, the editor window, dialogs with radio buttons
  and check boxes, the ASCII chart, the timed message box and the
  status-line clock all work. New for it: `HexStr`, and a System
  prelude written in Pascal (`rtl/system.pp`, with `GetFPCHeapStatus`)
  for programs that use units.
- **A Free Vision `TApplication` runs**: desktop, status line and
  Alt-X, with every FV unit compiled from FPC's sources. New for it:
  a `Dos` unit (`GetEnv`, `Exec`, `FindFirst`/`FindNext`, `FSplit`,
  `FExpand`, `GetTime`...), `GetDir`/`ChDir`/`MkDir`/`RmDir`,
  `Erase`/`Rename`, `InOutRes`, `UnicodeToUtf8`, FPC's System constants
  (`DirectorySeparator`, `LineEnding`...), `Fail`, constructors used as
  Boolean results (`if not inherited Init(...) then Fail`), and
  `OpenString` parameters.
- **Units may use each other through their implementations**; only
  interface `uses` must not form a cycle.
- **Free Vision's `Drivers` unit compiles and runs** on a Unix terminal,
  reading keys and mouse events through Bruto's own `Video`, `Keyboard`
  and `Mouse` units, which now ship with the compiler (together with
  `BaseUnix`, `Unix`, `UnixType` and `TermIO`). They draw with ANSI
  sequences and decode keys into DOS-style codes.
- **Unit scopes.** Two units can declare the same name: references find
  the unit's own declaration, then the last used unit's, and
  `Unit.Name` picks one explicitly.
- **External routines.** `cdecl; external 'c' name 'sym';` calls a C
  library function, and `varargs` allows extra arguments.
- **`ExitProc`** runs at program exit (also after `Halt`), and
  `SetLength` resizes strings.
- **Record comparison** with `=` and `<>`, field by field.
- **Named constants in type bounds.** Array and subrange bounds accept
  constant expressions, so `array[0..MaxItems - 1] of integer`,
  `1..MaxItems` and `array[Red..Blue]` now compile. Bounds can use
  literals, untyped constants, enumeration values, `+ - * div mod`, unary
  minus, and `ord` / `chr` / `succ` / `pred` / `abs`. This runs in a new
  semantic pass between parsing and code generation, the start of a
  proper name-and-type resolution phase.
- **Calling parameterless functions by name.** `writeln(Title)` calls
  `function Title: string` when no variable named `Title` is in scope.
- **`exit`, `break` and `continue`.** `break` and `continue` work in
  `for`, `while` and `repeat` loops; `exit` leaves the current procedure
  or function (or the program), and `exit(value)` sets a function's
  result first. As in Turbo Pascal they aren't reserved words, so a
  variable can still be called `exit`.
- **Fixed-width integer types.** `Byte`, `ShortInt`, `Word`,
  `SmallInt`, `LongInt`, `LongWord` / `Cardinal` / `DWord`, `QWord`,
  `Int64`, `PtrInt` / `PtrUInt` and their `IntN` / `UIntN` and
  `SizeInt` / `NativeInt` spellings. Variables take their real size, so
  records have FPC's layout; values widen to 64 bits in expressions and
  wrap when stored. `low` and `high` accept them (and type names such as
  `high(Word)`), and the watch window shows `Byte` / `ShortInt` values as
  numbers rather than characters.
- **`sizeof`** of a variable or type, including alignment padding.
- **Pointers.** `@x` takes the address of a variable, array element,
  record field or routine; the untyped `Pointer` type (and
  `CodePointer`) holds any address; `Assigned(p)` tests for `nil`; and
  `^` now works on any pointer expression, so `PRec(p)^.Id := 7` both
  reads and assigns.
- **Casts by type name.** `T(x)` converts between integers and pointers,
  between pointer types, and narrows to fixed-width integers
  (`Byte(300)` is 44), for declared types as well as built-in ones.
- **Procedural types** can be declared: `type TProc = procedure(n:
  integer);`. Their parameter lists now count `a, b: T` as two
  parameters.
- **Turbo Pascal `object` types.** Fields, methods, single inheritance,
  `virtual` and `abstract` methods dispatched through an FPC-layout VMT,
  constructors and destructors, `inherited`, `Self`, `New(p, Init(...))`,
  `p := New(PType, Init(...))`, `Dispose(p, Done)` and `TypeOf`. Inside
  a method, the object's fields and methods can be used by bare name.
  Methods may be named like built-ins (`TStream.Write`, `Read`).
- **Routines can declare local `const` and `type` sections**, and a
  routine's, program's or unit's declarations can come in any order.
- **More of FPC's syntax, enough to parse every Free Vision unit and
  `objects.pp`:** binary `%`, octal `&`, `#$hh` and `^M` character
  literals with implicit concatenation (`'text'#13#10`), byte-exact
  string literals, `{$DEFINE X := text}` macros, `Unit.Name`
  qualifiers, `resourcestring`, hint directives, typed constants with
  record and array values, `const` / `out` / `constref` and untyped
  parameters, `absolute` variables, empty statements, `otherwise` in
  `case`, `with` on any record or object expression (several at once),
  `new` / `dispose` / `inc` / `dec` on any place, assignment through a
  cast (`Pointer(P) := nil`), casts that reinterpret memory
  (`TBytes(Buf)[0]`), pointer arithmetic, calls through a cast
  procedural value (`TFunc(P)(args)`), `array[Boolean]`-style index
  types, tagless and nested variant parts with constant labels, untyped
  `file`, `String(x)`, `Str(x:width:precision, s)` and `Result`.
- **Overloaded routines.** Several routines may share a name if their
  parameter types differ; each call picks the best fit. Routines can
  also call others declared further down without `forward`.
- **Nested procedural types** (`procedure(...) is nested`): a local
  routine can be passed as a callback and still use its parent's
  variables, as Free Vision's `ForEach` / `FirstThat` need.
- **FPC's `Objects` unit compiles and runs**: collections, sorted string
  collections, `ForEach` callbacks and stream registration with
  `Put` / `Get`. Supporting this: `TAncestor.Method(...)` calls,
  `@TType.Method`, FPC's frame intrinsics, `UnusedHandle`, and `CPULLVM`
  among the predefined symbols.
- **Short strings.** `string[N]`, `ShortString`, and `string` itself
  under `{$H-}` or FPC's `objfpc` / `fpc` / `tp` modes are stored in
  place with a length byte (`s[0]`), as Turbo Pascal and FPC do. Plain
  `string` stays the dynamic string otherwise, so existing programs are
  unaffected.
- **System routines:** `Move`, `FillChar`, `GetMem`, `FreeMem`,
  `ReAllocMem`, `Halt`, `RunError`, `ParamCount`, `ParamStr`, `Hi`,
  `Lo`, `Swap`, `Ofs`, the `FileMode` and `ExitCode` variables, `P`-type
  pointers (`PChar`, `PByte`...) with array-style indexing, untyped
  `file` with `BlockRead`, `BlockWrite` and `Truncate`. `System.X` names
  these even inside a method or where the program has its own `X`.
- **Conditional compilation and include files.** `{$DEFINE}`,
  `{$UNDEF}`, `{$IFDEF}`, `{$IFNDEF}`, `{$IF}` / `{$ELSEIF}` (with
  `defined()`, `not`, `and`, `or`, comparisons and the FPC version
  symbols), `{$ELSE}`, `{$ENDIF}`, `{$I file}` and `{$ERROR}`, with FPC's
  predefined symbols for the host platform. Other FPC directives are
  accepted and ignored. Code from an included file or a unit now carries
  that file in its debug info, rather than being attributed to the main
  program's lines, and errors in it name the file.
- **Sources that aren't UTF-8** (code page 437, Latin-1) can be compiled
  and included.
- **String indexing.** `s[i]` reads the `i`-th character and `s[i] := c`
  replaces it, including through record fields (`r.Name[2] := 'X'`).
- **Bitwise operators.** `and`, `or`, `not` and the new `xor` work
  bitwise on integers and logically on booleans; `shl` and `shr` shift
  integers. They can also appear in constant bounds
  (`array[0..Mask shr 4]`).

### Changed
- **Brace comments nest**, as in FPC: `{ ... { ... } ... }` is one
  comment, so a stray `{` inside a comment now needs its own `}`. A
  string literal ends at the end of its line.
- **Identifiers are case-insensitive**, as Pascal requires: `Count`,
  `count` and `COUNT` are the same name, and `Length(s)` or `Inc(x)`
  now find the built-ins. The debugger, watch window and profiler still
  show each name as it was first written. Machine-level symbols (and so
  the Disassembly window's function headers) use the lower-case form.

### Fixed
- `New` zeroes the record it allocates, as FPC initializes its strings.
- `Str`, `Format`, `HexStr`, `GetDir` and `ReadLn` no longer leak the C
  buffers they format into.
- `SetLength` on a string fills new characters with #0 (they were
  spaces).
- A cast of a UnicodeString variable to a short string type
  (`TWildStr(S)`) converted the string instead of reading its pointer
  as characters, so Free Vision's file dialog shows `../*.*` as FPC's
  does.
- Calling a method with the wrong number of arguments (`Close(F)` inside
  a method of an object with a `Close` method) is a compile error, as in
  FPC, instead of an LLVM verification failure.
- Shift-selection and the clipboard work in Free Vision's editor:
  `GetShiftState` reports the modifiers of the last key read (a terminal
  sends them only with a key), where it always said none.
- `Val` sets the error position (it was always 0), reads reals and `$`
  hex, and stores into fields and narrow integers without overwriting
  what follows them.
- Chars compare as unsigned: `#$82 < #32` was true.
- A cast of an untyped `var` parameter (`T(Rec)`) reads the memory it
  refers to; a typed pointer value can be indexed (`PCell(@Buf)[I]`).
- A set membership test of a value above 255 is false instead of
  reading past the set.
- `Copy` with an index below 1 or a count past the end returns what FPC
  does instead of reading outside the string.
- A string variable that was never assigned compares as empty.
- `Length` of a short string reads its length byte, and assigning one
  character of a short string keeps its length.
- `Str` into a short string, typed short-string constants at program
  level, and character arrays initialized from strings store the
  characters rather than a pointer.
- A character array assigned or passed to a pointer (`P := Chars`) is
  its address, as FPC allows for `PChar`.
- Nested routines with the same name in different routines, or nested
  two levels deep and using the outer routine's variables or the
  object's fields, compile correctly; so do calls between them.
- A Pascal routine named like a C library function (`GetEnv`,
  `TTYName`) no longer replaces it.
- A string constant built with `+` is a string; adding characters
  builds a string; a char passed for a string parameter is converted.
- Pointer fields may point to an object type declared later; inline
  enumerations in records and objects define their values; local
  types have bounds; a local variable can share a unit's name.
- `case` labels written as characters (`'a'..'z'`) and assignments
  through nested variant fields (`Event.Where.X := 1`) compile.
- `High` of a short string gives its capacity, a string character can
  be passed by reference (`Move(S[1], ...)`), and `T(P^)` reads memory
  through an untyped pointer.
- **`read(...)` statements** parse; they used to be rejected.
- **A routine with an empty body** (`begin end`) is compiled; it used to
  be mistaken for a `forward` declaration and left undefined.
- **Self-referencing pointer types** such as `PNode = ^TNode`, declared
  before `TNode` and used for a `Next: PNode` field inside it, no longer
  send the compiler into endless recursion.
- **A function result of a fixed-width type** is initialised at its own
  width; it used to be zeroed as a pointer, overwriting the stack.
- **Boolean `and` / `or` short-circuit.** The right operand used to be
  evaluated even when the left one decided the result, so a guard like
  `(p <> nil) and (p^ > 0)` dereferenced `nil`. The language reference
  already promised short-circuit evaluation.
- **Integers stored into `real` variables are converted.** `r := 1`,
  `a[i] := 2` and passing an integer to a `real` parameter used to copy
  the integer's raw bits, so the real read back as `0.0`.
- **`for` loops stop at their final value.** The loop used to step past
  the end and then compare, so a loop up to `maxint` overflowed, and one
  over a `Byte` up to 255 would never end. It now leaves as soon as the
  variable reaches the final value.
- **Long loops no longer overflow the stack.** Each `begin ... end`
  block's breakpoint marker, and temporaries such as set literals, took a
  new stack slot every time they ran, so a loop of a few million
  iterations crashed. Stack slots are now reserved once per call, in the
  routine's entry block.
- **One-character literals in char contexts.** `'a'` used as a set
  element, compared with a `char`, or stored into a `char` now means the
  character; set literals such as `['a', 'e']` used to fail to compile.
- **Unary minus on real expressions.** `-r` used to be rejected; it now
  negates the value.
- **Procedures can use program-level variables and constants.** They
  used to live inside `main`, so any procedure or function that touched
  one failed with `undefined variable`. They are now globals, visible in
  every routine and shadowed by locals and parameters of the same name.
  The debugger watch window lists them alongside the current routine's
  locals.

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
