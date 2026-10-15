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
are picked up automatically. A unit file may be named `.pas` or `.pp`.

Each unit has its own scope. Two units may declare the same name; a
reference finds the unit's own declaration first, then the one in the
last unit of its `uses` clause that exports it, and `Unit.Name`
(`Video.InitVideo`, `Objects.TRect`) names a particular unit's.

### Units that ship with the compiler

When a used unit isn't found beside the program, Bruto's own versions
of these FPC units are used. They implement what Free Vision needs on a
Unix terminal:

- **`Video`**: a screen buffer of character/attribute cells (code page
  437), drawn with ANSI sequences on the terminal's alternate screen.
  After `InitEnhancedVideo` the buffer is `EnhancedVideoBuf`, whose
  cells (`TEnhancedVideoCell`) hold a grapheme cluster
  (`ExtendedGraphemeCluster`, a UnicodeString) and an `Attribute`; a
  wide cluster (CJK, most emoji) covers the cell to its right too.
  `ExtendedGraphemeClusterDisplayWidth` and `StringDisplayWidth` give
  widths in cells.
- **`GraphemeBreakProperty`**: `TUnicodeStringExtendedGraphemeClustersEnumerator`,
  which splits a UnicodeString into user-perceived characters for a
  `for-in` loop (base characters with their combining marks, emoji
  sequences, flags). FPC has it as a class in System; here it is an
  `object`.
- **`Keyboard`**: raw-mode input decoded into DOS-style key codes
  (`$3B00` for F1, `$4800` for Up, Alt and Ctrl combinations). Enhanced
  key events carry the typed character in `UnicodeChar` (UTF-8 input is
  decoded; a character outside the BMP comes as two events, one per
  surrogate).
- **`Mouse`**: xterm SGR mouse reports, including the wheel.
- **`BaseUnix`**, **`Unix`**, **`UnixType`**, **`TermIO`**: the C
  library calls and types Free Vision uses.
- **`Dos`**: environment, `Exec`, directory search (`FindFirst` /
  `FindNext` / `FindClose`), `FSplit`, `FExpand`, `FSearch`, dates and
  times.
- **`BrutoConsole`**: the terminal layer the three above share.
- **`fpwidestring`**, **`cwstring`**: empty, since conversions between
  UnicodeString and AnsiString are built in.

Units may use each other from their implementation sections; only the
units an interface uses must not lead back to it.

## Lexical elements

- **Identifiers**: ASCII letters / digits / underscore, must start
  with a letter. Case-insensitive, like keywords: `Count`, `count` and
  `COUNT` are the same name, and so are `Length` and `length`. The
  debugger shows each name the way it was first written.
- **Numbers**: decimal integers (`42`), hex `$FF`, binary `%1010`,
  octal `&17`, reals with explicit `.` (`3.14`, `1.0e3`).
- **Strings**: single-quoted (`'hello'`); doubled quote escapes a
  literal quote (`'don''t'`). A string can't span lines.
- **Characters by code**: `#65` or `#$41` is `'A'`; `^M` is `#13`
  (control characters, `^A` = `#1`). Quoted strings and codes written
  next to each other form one string: `'line'#13#10`, `^M^J`.
  Strings are byte strings: `#129` is the single byte 129.
- **Comments**: `{ … }`, `(* … *)`, and `// …` to end of line. Brace
  comments nest, as in FPC: `{ outer { inner } still outer }`.
- **Compiler directives**: inside a brace comment starting with `$`,
  e.g. `{$R+}`, `{$Q-}`, comma-separated for multiple
  (`{$R+,Q+}`):

  | Directive | Effect |
  |-----------|--------|
  | `{$R+}` / `{$R-}` | Enable/disable runtime range checks |
  | `{$Q+}` / `{$Q-}` | Enable/disable arithmetic overflow checks |
  | `{$I+}` / `{$I-}` | Enable/disable IO error trapping (`ioresult`) |

  Conditional compilation and include files work as in FPC:

  | Directive | Effect |
  |-----------|--------|
  | `{$DEFINE X}` / `{$UNDEF X}` | Define or remove a conditional symbol |
  | `{$IFDEF X}` / `{$IFNDEF X}` | Compile what follows only if `X` is (not) defined |
  | `{$IF expr}` / `{$ELSEIF expr}` | `expr` may use `defined(X)`, `not`, `and`, `or`, parentheses, numbers, comparisons and `FPC_FULLVERSION` (30202) |
  | `{$ELSE}`, `{$ENDIF}` / `{$IFEND}` | Close a branch / the group |
  | `{$I file}` / `{$INCLUDE file}` | Insert another file here. It is looked up next to the including file, then in the program's directory and the working directory; a name without an extension also matches `.inc`, `.pp` and `.pas`, and the case of the name doesn't matter |
  | `{$ERROR msg}` / `{$FATAL msg}` | Stop with `msg` |

  Symbols are case-insensitive. `FPC`, `BRUTO`, `CPU64`,
  `ENDIAN_LITTLE`, the CPU (`CPUX86_64` or `CPUAARCH64`) and the
  platform (`UNIX` plus `DARWIN` and `BSD` on macOS, `LINUX` on Linux,
  `WINDOWS` / `MSWINDOWS` / `WIN64` on Windows) are predefined. Other
  directives FPC knows (`{$mode}`, `{$H-}`, `{$codepage}` and so on) are
  accepted and ignored. Only `{$` with no space in between is a
  directive: `{ $ifdef X }` is an ordinary comment.

  `{$DEFINE NAME := text}` also makes `NAME` a macro: wherever it
  appears, `text` is read in its place (FPC's `{$MACRO ON}` style).
  `Unit.Name` qualifiers (`System.Length`, `Objects.TRect`) are
  accepted; units share one namespace, so the qualifier is dropped.

## Reserved words

```
and       array   begin          case    char     const
constructor  destructor  dispose div   do       downto
else      end     false          file    for      forward
function  goto    if             implementation   in
inherited initialization  integer  interface      label
mod       new     nil            not     object   of
or        packed  procedure      program read     readln
real      record  repeat         set     shl      shr
string    text    then           to      true     type
unit      until   uses           var     while    with
write     writeln xor
```

`read`, `write`, `new` and their kin can still be used as method names
(`TStream.Write`) and assigned as function results.

`exit`, `break` and `continue` are predeclared statements rather than
reserved words, as in Turbo Pascal: a variable may still be named
`exit`.

## Built-in scalar types

| Type      | Width / range                                             |
|-----------|-----------------------------------------------------------|
| `integer` | 64-bit signed                                             |
| `real`    | 64-bit IEEE-754 (`double`)                                |
| `char`    | 8-bit                                                     |
| `WideChar` | 16-bit, one UTF-16 code unit (`UnicodeChar` too)        |
| `boolean` | `false` (0) / `true` (1)                                  |
| `string`  | Dynamic string (AnsiString): length-prefixed, may hold #0, also a C string |
| `UnicodeString` | UTF-16 string, as FPC's (`WideString` too)        |
| `text`    | A textual file handle (used with `assign`/`reset` etc.)   |

FPC's fixed-width integers are predefined too:

| Type | Width | Range |
|------|-------|-------|
| `ShortInt` / `Int8` | 8-bit signed | -128..127 |
| `Byte` / `UInt8` | 8-bit unsigned | 0..255 |
| `SmallInt` / `Int16` | 16-bit signed | -32768..32767 |
| `Word` / `UInt16` | 16-bit unsigned | 0..65535 |
| `LongInt` / `Int32` | 32-bit signed | -2147483648..2147483647 |
| `LongWord` / `Cardinal` / `DWord` / `UInt32` | 32-bit unsigned | 0..4294967295 |
| `Int64` / `PtrInt` / `SizeInt` / `NativeInt` | same as `integer` | |
| `QWord` / `UInt64` / `PtrUInt` / `SizeUInt` / `NativeUInt` | 64-bit unsigned | |

A variable of one of these types takes exactly that many bytes, so
records and arrays have the layout FPC gives them. In expressions
they behave like `integer`: values are widened to 64 bits when read,
and truncated to the variable's width when stored, so `Byte` arithmetic
wraps (`255 + 1` stored in a `Byte` is `0`). A program can declare its
own type with one of these names, which then takes precedence. `QWord`
arithmetic is done as signed 64-bit, so values above `high(Int64)`
compare and divide incorrectly.

Subrange types of the form `lo..hi` (where both bounds are integer
literals) and enumerated types `(A, B, C)` are also user-definable.

### AnsiString

A `string` (AnsiString) points at its characters, which end with a #0
byte and follow a 16-byte header holding a marker, a reference count and
the length, as in FPC. So `Length` is immediate and a string may contain
#0 characters, yet the same pointer is a C string for C routines and
`PChar(S)`. A C string from elsewhere (a `PChar`, the C library) is
accepted as a string too, measured up to its first #0. `SetLength` fills
new characters with #0.

### UnicodeString and WideChar

A `UnicodeString` holds UTF-16 code units laid out as in FPC: a pointer
to the units, with the length stored before them; nil is the empty
string. `AnsiString` (`string`) is UTF-8, FPC's default code page on
Unix, and converting between the two (by assignment, by passing a
parameter, or with a cast) encodes or decodes UTF-8. A byte that isn't
part of a UTF-8 sequence converts as a Latin-1 character, so `#196`
becomes `Ä`. `Length`, `Copy`, `Pos`, `Delete`, `Insert`, `SetLength`,
`UpCase`/`LowerCase`, `S[i]`, `+` and the comparisons all work on code
units, as in FPC; `write` prints UTF-8.

In a file with `{$codepage cp437}`, a string literal's characters 128..255
are code page 437's when it becomes a UnicodeString (`#219` is `█`); as
an AnsiString it keeps the bytes. Other code pages are not supported.

A character code above 255 (`#$2502`) is a `WideChar`, and a string
literal containing one is a UnicodeString when stored as one (an
AnsiString gets it in UTF-8). An `array of WideChar` can be initialized
from a string constant. `UnicodeString(P)` of a raw pointer and
`Pointer(S)` reinterpret, as FPC's do for collection items.

Bruto doesn't count references: strings are never changed in place,
so `S[i] := C` builds a new string. Memory isn't freed.

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

- **Subrange / array bounds** are constant expressions: integer and
  character literals, untyped constants, enumeration values, `+ - * div
  mod`, unary minus, and `ord` / `chr` / `succ` / `pred` / `abs`. So
  `array[0..MaxItems - 1]` and `array[Red..Blue]` both work. Typed
  constants (`const N: integer = 3`) are initialised variables and can't
  be used as bounds.
- **Pointer types can come first**: `PNode = ^TNode` may be declared
  before `TNode`, and `TNode` may contain a `Next: PNode` field.
- `set of integer` represents a 256-bit bitmap (ordinals 0..255).
- **Short strings**: `string[N]` and `ShortString` (and plain `string`
  under `{$H-}` or `{$mode objfpc}`, `fpc` or `tp`, as in FPC) are
  stored in place as N+1 bytes, byte 0 holding the length: `s[0]` reads
  or sets it. Assigning a longer string truncates. In expressions they
  behave like any string.
- `string` is dynamically sized (a NUL-terminated C string on the
  heap); you can pass it freely without size annotations. `s[i]` reads
  or writes its `i`-th character (from 1). Writing copies the string
  first, so other variables holding the same text are unaffected.
- `Pointer` is an untyped pointer. It can hold any address but can't be
  dereferenced until it is cast to a typed pointer (`PRec(p)^`).
- Procedural types: `type TProc = procedure(n: integer);` or
  `function(x: real): real`. A variable of such a type holds `@Proc` or
  a routine name and is called like the routine.

## Constants

```pascal
const
  MaxItems = 10;
  Pi       = 3.14159265358979;
  Greeting = 'Hello';
  PadChar  = '.';
```

Program-level constants are visible everywhere, including inside
procedure and function bodies, and untyped ones can be used in type
bounds (see above), where `length`, `sizeof`, `low`, `high`, `lo` and
`hi` of constants and built-in types also work.

Typed constants can have record and array values:

```pascal
const
  Origin: TPoint = (X: 0; Y: 0);
  Primes: array[1..4] of integer = (2, 3, 5, 7);
  Empty:  TPoint = ();                     { every field zero }
```

A `resourcestring` section declares string constants like `const`.
FPC hint directives after a declaration (`deprecated 'message'`,
`platform`, `experimental`) are accepted and ignored.

## Variables

```pascal
var
  i, j, k:  integer;
  arr:      IntArr;
  pt1, pt2: Point;
  s:        string;
```

Program-level variables are globals: every procedure and function can
read and assign them, unless a local or parameter of the same name
shadows them. The debugger's watch window shows them alongside the
current routine's locals.

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
  `Factorial := <expr>`, or with `exit(<expr>)`, which also leaves the
  function. `Result` also names the function's result, as in FPC.
- A function without parameters can be called by its bare name, as in
  `writeln(Title)`, unless a variable of the same name is in scope.
- `var`, `out` and `constref` parameters pass by reference; the
  argument can be any variable, element, field or `p^`. `const`
  parameters pass by value.
- **Untyped parameters**: `var Buf` or `const Data` with no type pass
  an address; the routine reads the memory through a cast
  (`TBytes(Buf)[0]`) or an `absolute` variable
  (`var Bytes: TBytes absolute Buf;`).
- Procedures and functions can be nested; nested procs see the
  enclosing scope's variables.
- `forward` declares a header so two procedures can call each other,
  though it is rarely needed: any routine can call one declared further
  down.
- **Overloading**: routines may share a name if their parameter types
  differ; each call picks the one whose parameters fit its arguments.
- **Nested procedural types**: `type TCallback = procedure(Item:
  Pointer) is nested;` accepts a local routine, which keeps access to
  its parent's variables while the callback runs.
- **External routines**: `function CLength(P: PChar): LongInt; cdecl;
  external 'c' name 'strlen';` calls a C library function (`name`
  defaults to the routine's own). With `varargs` a call may pass more
  arguments than declared, for C functions like `ioctl` or `printf`.
- A routine's declarations (`const`, `type`, `var`, nested routines)
  can come in any order and repeat, as can a program's or unit's.
- **Conformant array parameters** — `var a: array of integer` — are
  parsed but only with limited support; prefer typed arrays.

## Objects

Turbo Pascal `object` types, as Free Vision uses them:

```pascal
type
  PShape = ^TShape;
  TShape = object
    Name: string;
    constructor Init(AName: string);
    function Area: real; virtual;
    destructor Done; virtual;
  end;
  TCircle = object(TShape)            { single inheritance }
    Radius: real;
    constructor Init(AName: string; R: real);
    function Area: real; virtual;     { overrides TShape.Area }
  end;

constructor TCircle.Init(AName: string; R: real);
begin
  inherited Init(AName);              { parent's constructor }
  Radius := R                         { fields by bare name inside methods }
end;
```

- Methods are declared in the type and implemented as
  `procedure TType.Method(...)`; the implementation may leave out the
  parameter list. Inside a method, the object's fields and methods can
  be used by bare name, and `Self` is the object itself.
- `virtual` methods are called through the object's VMT, so the actual
  type's version runs. A method declared `virtual; abstract;` stops the
  program with runtime error 211 if it is called.
- A constructor sets up the VMT, so an object with virtual methods must
  be constructed before they are called: `obj.Init(...)` for a variable,
  `New(p, Init(...))` or `p := New(PType, Init(...))` for one on the
  heap. `Dispose(p, Done)` calls the destructor and frees the memory.
- `TypeOf(TType)` or `TypeOf(obj)` gives the VMT's address. The VMT
  layout (size, negated size, parent link, method slots) is FPC's.
- `private`, `public` and `protected` sections are accepted but not
  enforced.

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
for c in s do ...           { the characters of a string, the elements of
                              an array, or an enumerator: for E in
                              T.Create(...) runs constructor Create on a
                              hidden T (an object type), then
                              while E.MoveNext do X := E.Current }
                            { both bounds are evaluated once; the loop stops
                              at the final value, so `for b := 0 to 255` with
                              a Byte `b` ends }

{ leaving loops and routines early }
for i := 1 to n do
begin
  if a[i] = 0 then continue;  { next iteration }
  if a[i] < 0 then break;     { leave the innermost loop }
end;
exit;                         { leave the current procedure }
exit(i);                      { in a function: set the result, then leave }

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

- **No `try` / `except`** error handling.

## Expressions

Operator precedence (lowest → highest):

| Group           | Operators                            |
|-----------------|--------------------------------------|
| Comparison      | `=`, `<>`, `<`, `<=`, `>`, `>=`, `in`|
| Additive / OR   | `+`, `-`, `or`, `xor`                |
| Multiplicative  | `*`, `/`, `div`, `mod`, `and`, `shl`, `shr` |
| Unary           | `-`, `not`                           |
| Primary         | literals, `IDENT`, `IDENT(...)`, `(expr)` |

`/` returns `real` even if both operands are integer; `div` and `mod`
are integer-only.

`and`, `or`, `xor` and `not` are logical on booleans and bitwise on
integers. On booleans, `and` and `or` short-circuit: in
`(p <> nil) and (p^ > 0)` the right side only runs when `p` isn't
`nil`. `shl` and `shr` shift integers; `shr` is a logical shift, as in
FPC.

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
| `low(x)`      | low bound of an array, subrange, enum or integer type (variable or type name) |
| `high(x)`     | high bound, likewise: `high(Word)` is 65535      |
| `sizeof(x)`   | size in bytes of a variable or type, including alignment padding |

### Strings

| Builtin          | Notes                                              |
|------------------|----------------------------------------------------|
| `length(s)`      | character count                                    |
| `copy(s, i, n)`  | substring of `s` starting at `i`, length `n`       |
| `pos(sub, s)`    | 1-based position of `sub` in `s`, or 0 if absent   |
| `concat(a,b,…)`  | concatenate 2+ strings                             |
| `str(n, s)`      | format integer `n` into string `s`                 |
| `val(s, n, c)`   | parse `s` into integer or real `n` (`$`, `%`, `&` prefixes too); `c` = first bad index, 0 if none |
| `upcase(c)`      | uppercase `char`, or `WideChar`/UnicodeString (Latin, Greek, Cyrillic) |
| `delete(s, i, n)`| remove `n` chars from `s` at position `i`          |
| `insert(t, s, i)`| insert string `t` into `s` at position `i`         |
| `Utf8ToUnicode`, `UnicodeToUtf8` | FPC's buffer conversions; the result counts the terminating zero |
| `UTF8ToString`, `UTF8Decode`, `UTF8Encode` | UTF-8 to UnicodeString and back |

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
| `p^`          | dereference; works on any pointer expression, e.g. `PRec(p)^.Id` |
| `p + n`, `p - n` | step a typed pointer by `n` elements (bytes for `Pointer`) |
| `p - q`       | the distance between two pointers, in elements |
| `TProc(p)(args)` | call through a procedural value given by a cast |
| `@x`          | address of a variable, element, field, or routine (`@Proc`) |
| `assigned(p)` | `p <> nil`, for pointers and procedural variables |
| `T(x)`        | cast to type `T`: integers ↔ pointers, pointer ↔ pointer, narrowing to a fixed-width integer (`Byte(300)` is 44) |

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
| `reset(f, 1)` / `rewrite(f, 1)` | open an untyped `file` in binary read/write mode |
| `blockread(f, buf, n [, done])` / `blockwrite(...)` | raw bytes to or from an untyped file |
| `truncate(f)`          | cut the file at the current position               |

### System routines

Routines from FPC's `System` unit, used when the program doesn't
declare its own of the same name (`System.X` always means these):
`Move(src, dst, n)`, `FillChar(dst, n, value)`, `GetMem(p, size)`,
`FreeMem(p [, size])`, `ReAllocMem(p, size)`, `Halt([code])`,
`RunError(code)`, `ParamCount`, `ParamStr(i)`, `Hi`, `Lo`, `Swap`,
`Ofs`, `SetLength(s, n)` (a dynamic string's new characters are
spaces). The variables `FileMode` and `ExitCode` exist too, as does
`ExitProc`: a procedure stored there runs when the program ends,
normally or through `Halt`, and may store another. The types
`PByte`, `PChar` and the other `P`-prefixed pointers to built-in types,
`AnsiChar`, `ShortString`, `Double`, `FileRec`. A typed pointer can be
indexed like an array: `p[i]`.

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

- No Object Pascal `class` types or generics; Turbo Pascal `object`
  types are supported (see Objects). Units and the `uses` clause are
  supported too (see Units).
- No `goto` to non-numeric labels (numeric only).
- No `try / except / finally`, no exceptions.
- Conformant array parameters are limited; prefer typed arrays.

These limitations are tracked in the issues backlog and may relax in
future releases.
