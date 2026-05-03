# Bruto Pascal — language reference

This document describes the dialect of Pascal that bruto-pascal
currently compiles. It's a working subset of ISO 7185 (Standard Pascal)
with a few Borland-style extensions. The reference is descriptive — it
follows the parser and codegen in
[`bruto-pascal-lang/src`](../bruto-pascal-lang/src/) — and is meant to
be the first thing you read before writing a non-trivial program for
the IDE.

For an end-to-end example that exercises most of what's listed here,
see [`long-demo.pas`](../long-demo.pas) and
[`SAMPLE.PAS`](../SAMPLE.PAS).

## Program structure

```pascal
program <Name>;
[uses   <Unit> { , <Unit> } ;]
[label  <int> {, <int>} ;]
[const  <const-decl> ;  { <const-decl> ; }]
[type   <type-decl>  ;  { <type-decl>  ; }]
[var    <var-decl>   ;  { <var-decl>   ; }]
[<procedure-or-function-decl> ;]+
begin
  <statements>
end.
```

Sections may appear at most once and must come in the order shown.
Procedure/function declarations follow `var` and may be interleaved
with each other freely.

## Units (`uses` / `unit`)

A unit is a separate `.pas` file that exposes declarations to other
programs and units via a `uses` clause:

```pascal
unit MathUtils;

interface
  const Pi = 3;
  type  TStat = record count, sum: integer end;
  function Square(x: integer): integer;
  procedure StatAdd(var s: TStat; v: integer);

implementation
  function Square(x: integer): integer;
  begin Square := x * x end;
  procedure StatAdd(var s: TStat; v: integer);
  begin s.count := s.count + 1; s.sum := s.sum + v end;
end.
```

The `interface` block accepts the same `const` / `type` / `var`
sections as a program, plus header-only declarations for the
procedures and functions whose bodies appear in `implementation`.
The unit may also declare its own private `const` / `type` / `var`
in `implementation`, and may end with either a Turbo Pascal
`begin ... end.` initialization block or a Delphi-style
`initialization ... end.` form — the statements inside run before
the consuming program's main block.

A program (or unit) imports a unit by listing its name in a `uses`
clause. The build pipeline locates `<Name>.pas` (case-insensitive)
in the source file's directory and the working directory; cyclical
imports are reported as errors. Sample layout:

```text
project/
  Demo.pas        ← contains `uses MathUtils;`
  MathUtils.pas
```

Run `brutop Demo.pas` from anywhere — units beside the source file
are picked up automatically.

## Lexical elements

- **Identifiers**: ASCII letters / digits / underscore, must start
  with a letter. Case-insensitive when matched against keywords; user
  identifiers preserve case.
- **Numbers**: decimal integers (`42`), reals with explicit `.`
  (`3.14`, `1.0e3`).
- **Strings**: single-quoted (`'hello'`); doubled quote escapes a
  literal quote (`'don''t'`).
- **Comments**: `{ … }`, `(* … *)`, and `// …` to end of line.
- **Compiler directives**: inside a brace comment starting with `$`,
  e.g. `{$R+}`, `{$Q-}`, comma-separated for multiple
  (`{$R+,Q+}`):

  | Directive | Effect |
  |-----------|--------|
  | `{$R+}` / `{$R-}` | Enable/disable runtime range checks |
  | `{$Q+}` / `{$Q-}` | Enable/disable arithmetic overflow checks |
  | `{$I+}` / `{$I-}` | Enable/disable IO error trapping (`ioresult`) |

## Reserved words

```
and       array   begin          case    char     const
dispose   div     do             downto  else     end
false     file    for            forward function goto
if        implementation in      initialization
integer   interface     label    mod     new      nil
not       of      or             packed  procedure
program   read    readln         real    record   repeat
set       string  text           then    to       true
type      unit    until          uses    var      while
with      write   writeln
```

`exit`, `break`, `continue` are **not** reserved and **not**
implemented as control-flow primitives — wrap loops in flag
variables instead.

## Built-in scalar types

| Type      | Width / range                                             |
|-----------|-----------------------------------------------------------|
| `integer` | 64-bit signed                                             |
| `real`    | 64-bit IEEE-754 (`double`)                                |
| `char`    | 8-bit                                                     |
| `boolean` | `false` (0) / `true` (1)                                  |
| `string`  | Length-prefixed dynamic string                            |
| `text`    | A textual file handle (used with `assign`/`reset` etc.)   |

Subrange types of the form `lo..hi` (where both bounds are integer
literals) and enumerated types `(A, B, C)` are also user-definable.

## Type system

```pascal
type
  Color    = (Red, Green, Blue);          { enum }
  Percent  = 0..100;                       { subrange }
  IntArr   = array[1..10] of integer;      { fixed-size array }
  Matrix   = array[1..3, 1..3] of real;    { multi-dim array }
  Point    = record x, y: real; end;       { record }
  Shape    = record                        { variant record }
               name: string;
               case kind: integer of
                 1: (radius: real);
                 2: (width, height: real);
             end;
  IntSet   = set of integer;               { 256-bit bit-set }
  IntPtr   = ^integer;                     { typed pointer }
  Node     = record                        { recursive via inline ^ }
               value: integer;
               next:  ^Node;
             end;
  TextFile = file of char;                 { typed file }
```

Notes / restrictions:

- **Subrange / array bounds** must be **integer literals**, not
  named constants. `array[1..MaxItems]` does not parse.
- **Forward type references**: declare records first when they need to
  point at themselves; use `next: ^Node` *inline*. Declaring `TreePtr
  = ^Tree` *before* `Tree = record ...` is not supported.
- `set of integer` represents a 256-bit bitmap (ordinals 0..255).
- `string` is dynamically sized, with a runtime length prefix; you
  can pass it freely without size annotations.

## Constants

```pascal
const
  MaxItems = 10;
  Pi       = 3.14159265358979;
  Greeting = 'Hello';
  PadChar  = '.';
```

Constants are visible only at the **program (outer) scope**. They are
**not in scope inside procedure / function bodies** — inline the
literal value, or pass it as a parameter.

## Variables

```pascal
var
  i, j, k:  integer;
  arr:      IntArr;
  pt1, pt2: Point;
  s:        string;
```

All variables are zero-initialised at the start of the program (and
each procedure call) — integers to `0`, reals to `0.0`, strings to
`''`, sets to `[]`, pointers to `nil`.

## Procedures and functions

```pascal
procedure Swap(var a, b: integer);
var tmp: integer;
begin
  tmp := a; a := b; b := tmp
end;

function Factorial(n: integer): integer;
begin
  if n <= 1 then Factorial := 1
  else Factorial := n * Factorial(n - 1)
end;

{ Forward decl for mutual recursion }
procedure Odd(n: integer); forward;
procedure Even(n: integer);
begin
  if n = 0 then writeln('even') else Odd(n - 1)
end;
procedure Odd(n: integer);
begin
  if n = 0 then writeln('odd')  else Even(n - 1)
end;
```

- A function returns its value by **assigning to its own name**:
  `Factorial := <expr>`. There is no `Result` alias and no `return`
  statement.
- `var` parameters pass by reference. Their argument must be a plain
  variable name or a simple field/element access — **`SwapInt(arr[i],
  arr[i+1])` does NOT typecheck** because `arr[i+1]` involves
  arithmetic in the index.
- Procedures and functions can be nested; nested procs see the
  enclosing scope's variables.
- `forward` declares a header so two procedures can call each other.
- **Conformant array parameters** — `var a: array of integer` — are
  parsed but only with limited support; prefer typed arrays.

## Statements

```pascal
{ Assignment }
x := 1;
arr[i] := arr[j] + 1;
pt1.x := 3.0;
tbl.rows[i].x := pt.x;     { chained lvalues OK }
p^ := 42;                   { dereference assign }

{ Procedure call }
writeln('hello');
Swap(a, b);

{ if / then / else }
if x > 0 then writeln('positive')
else if x = 0 then writeln('zero')
else writeln('negative');

{ while / repeat / for }
while i <= n do begin write(i); i := i + 1 end;

repeat
  i := i * 2
until i > 1000;

for i := 1 to 10 do  ...    { also: for i := 10 downto 1 }

{ case (with ranges and an else clause) }
case n of
  0:        writeln('zero');
  1, 2:     writeln('small');
  3..5:     writeln('medium');
  6, 7:     writeln('largish')
else
  writeln('other')
end;

{ goto + label (numeric labels declared up front) }
label 99;
...
99:  i := i + 1;
     if i < 3 then goto 99;

{ with — saves typing record-field prefixes inside the block }
with pt1 do
begin
  x := x + 1.0;
  y := y + 2.0
end;

{ heap }
new(p);   p^ := 42;   dispose(p);
```

### Statement-level limits

- **No `exit` / `break` / `continue`** — exit a loop with a sentinel
  flag; exit a function via the assign-to-name idiom plus a guarding
  `if`.
- **No `try` / `except`** error handling.
- **No string indexing in expressions** — `s[k]` (read or write) is
  not supported. To get a single-character substring use
  `copy(s, k, 1)` (returns a `string`, not a `char`).
- **No string-element assignment** — `s[k] := ch` is not supported.
- **No unary minus on real** — write `0.0 - r` instead of `-r` when
  `r` is a real expression.

## Expressions

Operator precedence (lowest → highest):

| Group           | Operators                            |
|-----------------|--------------------------------------|
| Comparison      | `=`, `<>`, `<`, `<=`, `>`, `>=`, `in`|
| Additive / OR   | `+`, `-`, `or`                       |
| Multiplicative  | `*`, `/`, `div`, `mod`, `and`        |
| Unary           | `-` (integers only), `not`           |
| Primary         | literals, `IDENT`, `IDENT(...)`, `(expr)` |

`/` returns `real` even if both operands are integer; `div` and `mod`
are integer-only.

Boolean operators `and` and `or` are short-circuit.

`set` literals: `[1, 3, 5..9, 13]`.
`set` operators: `+` (union), `-` (difference), `*` (intersection),
`in` (membership).

## Built-in routines

### Arithmetic / math

| Builtin       | Type signature             | Notes                       |
|---------------|----------------------------|-----------------------------|
| `abs(x)`      | int → int / real → real    |                             |
| `sqr(x)`      | int → int / real → real    |                             |
| `sqrt(x)`     | real → real                |                             |
| `sin(x)`      | real → real                | radians                     |
| `cos(x)`      | real → real                | radians                     |
| `exp(x)`      | real → real                | `e^x`                       |
| `ln(x)`       | real → real                | natural log                 |
| `arctan(x)`   | real → real                |                             |
| `trunc(r)`    | real → integer             | toward zero                 |
| `round(r)`    | real → integer             | half-to-even                |
| `odd(n)`      | integer → boolean          |                             |
| `maxint`      | constant: `9_223_372_036_854_775_807` |                  |

### Ordinals

| Builtin       | Notes                                            |
|---------------|--------------------------------------------------|
| `succ(x)`     | next ordinal (`integer`, `char`, enum)           |
| `pred(x)`     | previous ordinal                                 |
| `ord(x)`      | ordinal value of `char` / enum / boolean / int   |
| `chr(n)`      | `n: integer → char`                              |
| `inc(v)` / `inc(v, k)` | mutate variable in place               |
| `dec(v)` / `dec(v, k)` | mutate variable in place               |
| `low(arr)`    | low array bound                                  |
| `high(arr)`   | high array bound                                 |

### Strings

| Builtin          | Notes                                              |
|------------------|----------------------------------------------------|
| `length(s)`      | character count                                    |
| `copy(s, i, n)`  | substring of `s` starting at `i`, length `n`       |
| `pos(sub, s)`    | 1-based position of `sub` in `s`, or 0 if absent   |
| `concat(a,b,…)`  | concatenate 2+ strings                             |
| `str(n, s)`      | format integer `n` into string `s`                 |
| `val(s, n, c)`   | parse `s` into integer `n`; `c` = first bad index  |
| `upcase(c)`      | uppercase single `char`                            |
| `delete(s, i, n)`| remove `n` chars from `s` at position `i`          |
| `insert(t, s, i)`| insert string `t` into `s` at position `i`         |

### Sets

| Builtin       | Notes                                |
|---------------|--------------------------------------|
| `include(s,e)`| add ordinal `e` to set `s`           |
| `exclude(s,e)`| remove ordinal `e` from set `s`      |
| `e in s`      | membership test (operator)           |

### Pointers / heap

| Builtin       | Notes                                |
|---------------|--------------------------------------|
| `new(p)`      | allocate, store address in `p`       |
| `dispose(p)`  | free                                 |
| `nil`         | null pointer literal                 |
| `p^`          | dereference                          |

### IO and files

| Builtin                | Notes                                              |
|------------------------|----------------------------------------------------|
| `writeln(args)`        | console + capture file (each arg may use `:width:precision`) |
| `write(args)`          | same, no trailing newline                          |
| `readln(vars)`         | read whitespace-separated values                   |
| `read(vars)`           | as above, no newline consumption                   |
| `assign(f, name)`      | bind file variable `f` to filesystem path          |
| `reset(f)`             | open for reading                                   |
| `rewrite(f)`           | open for writing (truncating)                      |
| `close(f)`             | flush + close                                      |
| `eof(f)` / `eoln(f)`   | end-of-file / end-of-line                          |
| `filepos(f)`           | current byte offset                                |
| `filesize(f)`          | total size in bytes                                |
| `seek(f, n)`           | move to offset `n`                                 |
| `ioresult`             | int: 0 on success, error code from last IO op      |

`writeln` / `write` accept a leading file argument: `writeln(f, …)`.
The predefined files `input` and `output` map to stdin / stdout.

Console output is also captured to a temp file (path resolved via
`std::env::temp_dir()`) so the IDE can render it in the Output panel
even when stdout is redirected.

### Format specifiers (write/writeln only)

```pascal
writeln(n:6);          { right-align integer in width 6 }
writeln(r:10:4);       { real in width 10, 4 decimals }
writeln(s:20);         { right-align string in width 20 }
```

## Errors and runtime trapping

When `{$R+}` is in effect, out-of-range array indices and subrange
assignments abort with a runtime message on stderr including the
source line. Same for `{$Q+}` on integer overflow.

Failing IO operations set `ioresult` instead of aborting when
`{$I-}` is active. With `{$I+}` (default) they abort.

## Debugger integration

The compiler emits DWARF debug info on every statement. The IDE
gutter displays **breakpoints** as red markers, settable on:

- any executable statement line
- the closing `end` keyword of any block (including the program's
  outermost `end.` — the codegen emits a synthetic alloca there so
  the debugger has somewhere to stop)

`writeln`, `read`, etc. emit through a runtime helper that captures
output to the IDE's console-capture file in addition to stdout.

The watch window decodes Pascal-aware values:

- **Enum** — shown by name, e.g. `(Color) c = Green`
  (`DW_TAG_enumeration_type` metadata).
- **Set** — shown as a Pascal set literal (`[1, 3..5]`).
- **Variant record** — only the active variant's fields are listed,
  picked at runtime by the tag value. Fixed fields and the tag are
  always shown; variants belonging to inactive cases are filtered
  out using metadata recorded in `<exe>.bruto-meta`.

## Supported platforms

The bruto-pascal compiler runs (and compiles target programs to
native code) on:

- **macOS aarch64 / x86_64** — DWARF in a `.dSYM` bundle alongside
  the binary
- **Linux x86_64 / aarch64** — DWARF embedded; non-PIE binary
- **Windows x86_64** (MSVC) — PDB-less DWARF; UCRT linkage

See [`CHANGELOG.md`](../CHANGELOG.md) for per-version platform
status.

## Known gaps versus Standard Pascal / FPC

- No `exit` / `break` / `continue` statements.
- No string indexing (`s[i]`) and no string-element assignment
  (`s[i] := c`).
- No unary minus on real expressions.
- Constants from the program scope aren't visible inside procedures.
- Subrange / array bounds must be integer literals, not named
  constants.
- No object-Pascal classes or generics. (Units / `uses` clause **are**
  supported — see the Units section above.)
- No `goto` to non-numeric labels (numeric only).
- No `try / except / finally`, no exceptions.
- Conformant array parameters are limited; prefer typed arrays.

These limitations are tracked in the issues backlog and may relax in
future releases.
