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
- **`Sockets`**: FPC's socket unit for macOS and Linux: `fpSocket`,
  `fpBind`, `fpListen`, `fpAccept`, `fpConnect`, `fpSend`, `fpRecv`,
  `fpSendTo`, `fpRecvFrom`, socket options, `CloseSocket`, `SocketError`,
  `htons`/`htonl`, `StrToNetAddr`/`NetAddrToStr`, and `TInetSockAddr`
  with each system's layout. A write to a closed connection returns an
  error instead of raising `SIGPIPE`.
- **`NetDB`**: `ResolveHostByName` (through `getaddrinfo`, so
  `/etc/hosts` and DNS).
- **`NetObjects`**: networking as Turbo Pascal objects: `TTcpClient`
  (`Connect` by host name, `SendString`, `ReadLine`, `ReadAll`),
  `TTcpServer` (`Listen`, `Accept`), `TUdpSocket` and `THttpClient`
  (plain-HTTP `Get`, chunked bodies decoded, `Header`). Constructors
  `Fail` when they can't connect, so `if not C.Connect(...) then` works.
- **`Classes`**: FPC's lists, string lists, streams and `TComponent`
  (owned components are freed with their owner). `TFPList` and
  `TList` (pointer lists with `Sort`), `TStrings` / `TStringList`
  (`Strings[]` by default, `Objects[]`, `IndexOf`, `Sort`, `CustomSort`,
  `Sorted` with `Duplicates`, `CaseSensitive`, `OwnsObjects`, `Text`,
  `CommaText`, `DelimitedText` with `Delimiter`, `QuoteChar` and
  `StrictDelimiter`, `Names[]` / `Values[]` / `ValueFromIndex[]`,
  `LoadFromFile` / `SaveToFile`, `OnChange`, `for S in List`),
  `TPersistent.Assign`, and streams: `TStream` (`Read`, `Write`, `Seek`,
  `Position`, `Size`, `ReadBuffer`, `WriteBuffer`, `CopyFrom`,
  `ReadAnsiString`...), `THandleStream`, `TFileStream` (`fmCreate`,
  `fmOpenRead`...), `TMemoryStream` and `TStringStream`. Errors raise
  FPC's exceptions (`EListError`, `EStringListError`, `EFOpenError`...).
- **`Math`**: FPC's commonly used routines: `Min`/`Max`, `InRange`,
  `EnsureRange`, `Sign`, `CompareValue`, `IsNan`, `IsInfinite`,
  `IsZero`, `SameValue`, `Floor`/`Ceil` (and the 64-bit ones), `RoundTo`,
  `SimpleRoundTo`, `Power`, `IntPower`, `Log10`, `Log2`, `LogN`,
  `LnXP1`, `Hypot`, the trigonometric and hyperbolic functions and their
  inverses, angle conversions, `Sum`, `Mean`, `MinValue`/`MaxValue`,
  `StdDev`, `Variance`, `RandomRange`, `RandG`, `DivMod`, `NaN` and
  `Infinity`, and `GetExceptionMask`/`SetExceptionMask`.
- **`Variants`**: FPC's Variant routines (see Variant below):
  `VarType`, `VarTypeAsText`, `VarIsNull`/`VarIsEmpty`/`VarIsClear`/
  `VarIsNumeric`/`VarIsStr`/`VarIsArray`..., `VarToStr`/`VarToStrDef`,
  `VarToWideStr`, `VarAsType`, `VarCast`, `VarClear`, `VarCopy`,
  `VarSameValue`, `VarCompareValue`, `VarInRange`, `Null`, `Unassigned`,
  `VarArrayCreate`, `VarArrayOf`, `VarArrayLowBound`/`HighBound`/
  `DimCount`, `VarArrayRedim`, `GetPropValue`/`SetPropValue`,
  `Get`/`SetVariantProp`, and the `EVariant...` exceptions.
- **`SysUtils`**: besides the string and file-name routines (among them
  `ChangeFileExt`, `ExtractFileName`/`Path`/`Dir`/`Ext`,
  `Include`/`ExcludeTrailingPathDelimiter`, `TryStrToInt`/`Int64`,
  `CurrToStr`/`StrToCurr`) and the
  exceptions: `FileOpen` / `FileCreate` / `FileRead` / `FileWrite` /
  `FileSeek` / `FileClose`, `DeleteFile`, `RenameFile`, `CompareStr`,
  `CompareText`, `SameText`, `AnsiCompareText`, `QuotedStr`,
  `GetLastOSError`, `SysErrorMessage`.
- **`OpenSSL`**: FPC's names for the OpenSSL calls TLS needs
  (`InitSSLInterface`, `SslCtxNew`, `SslNew`, `SslConnect`, `SslRead`,
  ...). libssl and libcrypto (OpenSSL 1.1 or 3) are loaded at run time:
  Homebrew's on macOS, the system's on Linux, `libssl-3-x64.dll` on
  Windows.
- **`ssockets`**, **`sslbase`**, **`sslsockets`**, **`opensslsockets`**:
  FPC's socket streams. `TInetSocket.Create(Host, Port[, Handler])`
  connects (a `TStream`), `TInetServer` listens and accepts
  (`GetConnection`, or `StartAccepting` with `OnConnect`), and a
  `TSSLSocketHandler` makes either one TLS: with `opensslsockets` in the
  `uses` clause, `TSSLSocketHandler.GetDefaultHandler` gives an OpenSSL
  handler. `VerifyPeerCert` checks the server's certificate chain and
  host name (against the system's trusted certificates, or
  `CertificateData.TrustedCertificate`); a server gets its certificate
  and key from `CertificateData.Certificate` / `.PrivateKey` (PEM
  files). Unix only, like `Sockets`.
- **`fphttpclient`**: FPC's `TFPHTTPClient`: `Get` (to a string, a
  stream or a file), `SimpleGet`, `Post`, `FormPost`, `Put`, `Delete`,
  `Head`, request and response headers, `AllowRedirect`, basic
  authentication, chunked bodies. `https://` URLs need `opensslsockets`
  in the `uses` clause; set `VerifySSLCertificate` to check certificates
  (off by default, as in FPC). `Get` raises `EHTTPClient` for a status
  other than 200.
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
  Strings are byte strings: `#129` is the single byte 129, and a
  literal's characters are the source's bytes, as in FPC: in a UTF-8
  source `'é'` is two bytes (a source that isn't UTF-8 is read byte by
  byte).
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
| `real`    | 64-bit IEEE-754 (`double`; also `Extended`, `Comp`) |
| `Single`  | 32-bit IEEE-754: 4 bytes in records and arrays, widened to `real` in expressions |
| `Currency` | FPC's fixed point: an Int64 holding the value times 10000 (see below) |
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
own type with one of these names, which then takes precedence. As in
FPC, arithmetic between `QWord`s (or a `QWord` and another unsigned value
or a non-negative literal) is unsigned: `div`, `mod`, comparisons,
`Write`, `Str` and `IntToStr` treat values above `high(Int64)` as the
large numbers they are.

Subrange types of the form `lo..hi` (where both bounds are integer
literals) and enumerated types `(A, B, C)` are also user-definable. An
enumeration's values can be given (`(szSmall = 1, szLarge = 5, szHuge)`:
`szHuge` is 6). `Write` writes an enumeration value by its name, left-
justified in its width, as FPC does. An enumeration value takes the
bytes FPC gives it: 4 in FPC's own modes, as few as fit (1, 2 or 4) in
Delphi and TP modes, at least `{$PACKENUM n}` (`{$Z1}`, `{$Z2}`, `{$Z4}`)
where given. A `packed record` has no padding between its fields. A set
takes the bytes FPC gives it: 4 when no element is above 31, else 32, in
FPC's own modes; in Delphi and TP modes, or with `{$PACKSET 1}` (2, 4,
8), only the bytes from its lowest element's to its highest's (rounded
to the pack size, 3 becoming 4), so `set of 20..30` takes 2 bytes
starting at element 16, as in FPC. `for X in TColor` runs through an
enumeration's values, `for X in S` through a set's members.

A `Currency` is laid out as FPC lays it out on 64-bit ARM: an Int64
holding the value times 10000, so four decimal places are exact. In an
expression it reads as a `real`, but `+`, `-` and `*` with a Currency
operand give a Currency computed as FPC computes it: the other operand
is made a Currency first (rounding halves to even), and a product keeps
the 128-bit quotient by 10000, truncated. `/` gives a `real`; storing a
`real` into a Currency rounds it. `Write` formats a Currency as FPC does
(`2.500000000000000000E+00`, or `C:0:2`), `CurrToStr`/`StrToCurr` are in
SysUtils, Currency properties have RTTI (`ftCurr`) and stream as floats,
and a Currency in a Variant is a varCurrency.

### AnsiString

A `string` (AnsiString) points at its characters, which end with a #0
byte and follow a 16-byte header holding a marker, a reference count and
the length, as in FPC. So `Length` is immediate and a string may contain
#0 characters, yet the same pointer is a C string for C routines and
`PChar(S)`. A C string from elsewhere (a `PChar`, the C library) is
accepted as a string too, measured up to its first #0. `SetLength` fills
new characters with #0.

Strings are reference counted, as in FPC: assigning one counts it, the
string it replaces is released, a routine releases its string locals and
value parameters when it returns, and a string a statement makes without
storing it is freed when the statement ends. A string written into raw
memory (`Move`, `GetMem`) isn't counted, as in FPC. Building with the
environment variable `BRUTO_NO_ARC=1` turns counting off (strings are
then never freed).

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

Like AnsiStrings, UnicodeStrings are reference counted. A string is never
changed in place: `S[i] := C` builds a new string.

### Variant

A `Variant` (`OleVariant` too) is FPC's: 16 bytes laid out as `TVarData`
(declared in System with the `varXXX` type codes), holding a value of
any simple type. Working with Variants needs the `Variants` unit, as in
FPC. A value assigned to a Variant takes the type FPC gives it: a
constant the smallest integer type that holds it (`42` is a ShortInt,
`200` a Byte), a variable its own type, other integer expressions Int64,
reals Double, `string` and `Char` String, `UnicodeString` and `WideChar`
OleStr. The operators follow FPC's rules: `10 + 3` is an Integer (an
Int64 when it overflows), `/` gives a Double, `'10' + 5` is 15.0, two
strings concatenate, Null with anything is Null, `7 = '7'` is true, and
converting `'abc'` to a number raises `EVariantError`. A Variant converts
to the type it is assigned to, passed as or cast to (`I := V`,
`string(V)`), rounding reals to even as FPC does; Null raises
`EVariantTypeCastError` (`NullStrictConvert`). `Write` writes a Variant
as `VarToStr` gives it, and a Variant can be a condition (`if V then`).

Variant arrays have any number of dimensions:
`VarArrayCreate([0, 9], varInteger)`, `VarArrayCreate([1, 3, 1, 3],
varDouble)`, `VarArrayOf([1, 'two', 3.5])`, read and written as `V[I]`,
`V[I, J]` or, for an array held in an element, `V[I][J]`; their elements
are laid out as FPC's, so `VarArrayRedim` (of the last dimension) moves
them as it does in FPC. Assigning a variant array copies it (the copy is
made when a shared one is changed). Strings and arrays in Variants are
reference counted. `VarClear` clears a string or array but, as in FPC,
leaves a number's bytes, so a cleared Variant property is still
streamed (as `nil`). Published Variant properties have RTTI
(`tkVariant`) and are streamed as FPC streams them. Two FPC 3.2.2
behaviors are not reproduced: on 64-bit ARM it streams a Currency held
in a Variant with the wrong value, and whether a property assigned
`Unassigned` is streamed depends on what its temporary held before.

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

### Dynamic and open arrays

`array of T` declares a dynamic array: indexed from 0, `nil` (length 0)
until `SetLength(A, N)` gives it N zeroed elements (`SetLength(G, W, H)`
for an array of arrays). `Length`, `High`, `Low`, `Copy(A, Start,
Count)`, `Insert(Value, A, Index)`, `Delete(A, Index, Count)`, `A := [1,
2, 3]` and `for X in A` work as in FPC. Assigning one dynamic array to
another shares the elements (as in FPC, there is no copy on write);
`SetLength` gives the variable its own copy. They are reference counted
and freed with their elements, like strings.

As a parameter's type, `array of T` is an open array: any array of T can
be passed (a static array, a dynamic one, `[a, b, c]`), indexed from 0
with `High(A)` its last index; a `var` open array changes the caller's
elements. `array of const` takes values of any type as `TVarRec`s
(`VType` is `vtInteger`, `vtInt64`, `vtAnsiString`, `vtChar`,
`vtBoolean`, `vtExtended`, `vtPointer`, `vtObject`...), as SysUtils'
`Format` does.

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

A variable can be given its first value where it is declared, as in FPC:
`var Count: Integer = 5;`, `Primes: array[1..4] of Integer = (2, 3, 5,
7);`. A routine's such locals get the value on every call.

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

Parameters can have default values, used when a call leaves them out
(`procedure Connect(const Host: string; Port: Word = 80);`). A unit's
implementation may leave out the defaults its interface declares.
Procedural types keep `var`, `out` and untyped `const` parameters by
reference. A statement can call a method on a call's result
(`TFoo.Create(...).Free`).

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

## Classes

Object Pascal `class` types, with FPC's semantics:

```pascal
type
  TShape = class
  private
    FName: string;
    procedure SetName(const V: string);
  public
    constructor Create(const AName: string); virtual;
    destructor Destroy; override;
    function Area: Double; virtual; abstract;
    class function Kind: string; virtual;
    property Name: string read FName write SetName;
  end;
  TShapeClass = class of TShape;

  TSquare = class(TShape)
  ...

var
  S: TShape;
  C: TShapeClass;
begin
  C := TSquare;
  S := C.Create('sq');                { virtual constructor }
  writeln(S.Name, ' ', S.Area:0:1, ' ', S.ClassName);
  if S is TSquare then writeln((S as TSquare).Side:0:1);
  S.Free;
end.
```

- An instance lives on the heap and a variable of class type refers to
  it: `TFoo.Create(...)` allocates (zeroed) and constructs one,
  `Obj.Free` destroys it unless `Obj` is nil, and `Obj.Field`,
  `Obj.Method` need no `^`. Assigning a class variable copies the
  reference.
- Every class descends from `TObject` (`Create`, `Destroy`, `Free`,
  `ClassName`, `ClassNameIs`, `ClassType`, `ClassParent`,
  `InheritsFrom`, `InstanceSize`, `Equals`, `GetHashCode`, `ToString`).
  `TClass` is `class of TObject`. SysUtils has `FreeAndNil`.
- `virtual` starts a new slot; `override` replaces the parent's method
  (it is an error if there is none to replace). `abstract` methods stop
  the program with runtime error 211 if called. `inherited Method(...)`
  and a bare `inherited;` call the parent's version.
- The destructor frees the instance after its body has run, releasing
  the strings its fields hold; `inherited Destroy` inside a destructor
  doesn't free it twice.
- `class procedure` / `class function`: `Self` is the class. They can be
  called on the class (`TFoo.Kind`), a class reference or an instance,
  and can be virtual.
- `class of T` types hold a class (its VMT). A class name used as a
  value is its class reference.
- `Obj is TFoo` tests the instance's class (false for nil); `Obj as
  TFoo` gives the instance, or stops with runtime error 219 if it isn't
  one (nil stays nil).
- Properties read and write a field (or a field path, `FPoint.X`) or
  call a getter and setter. Array properties take index parameters
  (`property Items[I: Integer]: T read GetItem write SetItem;`), the
  `default` one is reached as `Obj[I]`, and `index N` passes N to a
  shared getter or setter. Inside the class's methods, and in a `with`
  on an instance, properties can be used by bare name.
- Forward declarations (`TFoo = class;`) and classes with no body
  (`EFoo = class(TBase);`) are allowed. `published`, `strict private` and
  so on are accepted but not enforced.
- Classes and `object` types mix freely in one program: an object can
  hold a class reference and a class can hold a pointer to an object.
  Where the program has a `TObject` of its own (Free Vision's Objects
  unit), the root class is still the one classes descend from, and its
  `ClassName` is still `TObject`. As in FPC, a unit's `TObject` hides the
  root class only where that unit is used (the last unit in `uses`
  wins), so SysUtils, Classes and the program's own class units can sit
  beside Free Vision in one program.
- Methods can be overloaded (`function Get(const URL: string): string;
  overload;` beside `procedure Get(const URL: string; Stream: TStream);
  overload;`); the call's arguments pick one. In a class, a method with
  the name of an ancestor's but other parameters adds an overload; in an
  `object` type it hides the ancestor's, as in Turbo Pascal.
- Method pointers (`procedure(...) of object`, `function(...): T of
  object`) hold a method and its instance, as FPC's `TMethod` (`Code`,
  `Data`): `B.OnClick := @Form.ButtonClick` (or `@ButtonClick` inside
  one of the form's methods, or without `@`), then `B.OnClick(Self)` or
  `if Assigned(FOnClick) then FOnClick(Self)`. A virtual method is looked
  up when the pointer is made. Methods of `object` types work too.
- `class var` fields are one variable shared by the class and its
  descendants, reached by bare name in their methods, as `TFoo.Count`
  or through an instance.
- As in FPC, `AfterConstruction` runs after a class's constructor made
  an instance, and `BeforeDestruction` before its destructor frees one.
- `published` properties carry run-time type information, as do the
  ones in the default section of a class compiled with `{$M+}` or
  descending from one (`TPersistent`); see Run-time type information.
- Components stream as FPC's do (see Streaming components).

## Run-time type information

`TypeInfo(T)` gives a type's information (a `PTypeInfo`) and
`Obj.ClassInfo` a class's; the records (`TTypeInfo`, `TTypeData`,
`TPropInfo`, `TTypeKind`...) have FPC's names and fields, laid out
Bruto's way. The `TypInfo` unit reads them as FPC's does:

```pascal
uses TypInfo;
...
WriteLn(GetEnumName(TypeInfo(TColor), Ord(clBlue)));     { clBlue }
N := GetPropList(Widget, List);                          { published props }
SetEnumProp(Widget, 'Shape', 'shTriangle');
WriteLn(GetStrProp(Widget, 'Caption'), GetOrdProp(Widget, 'Width'));
```

Published properties may read and write fields, static or virtual
methods (with `index N` too); `default` and `stored` are recorded.
Properties are listed inherited first, in declaration order
(`GetPropList` with kinds sorts them by name). Variants
(`GetPropValue`) aren't available.

## Streaming components

The `Classes` unit writes and reads components in FPC's binary format
(`TPF0`), byte for byte the same as FPC's, and converts it to and from
the text form (`.lfm`/`.dfm` style):

```pascal
RegisterClasses([TForm1, TButton]);
Stream.WriteComponent(Form);          { published properties, children }
Stream.Position := 0;
ObjectBinaryToText(Stream, Text);     { object Form1: TForm1 ... end }
Form := TForm1.Create(nil);
Stream.ReadComponent(Form);           { or ReadComponent(nil): a new one }
```

As in FPC, a property is written unless it equals its `default` (or,
without one, unless a string or float is empty or zero) or `stored` says
not; object properties that aren't components are written as their own
properties (`Font.Size = 12`), components by name (`Buddy = Side`), and
events by the name of the root's published method (`OnClick =
OkClick`). Children are the components `GetChildren` gives (none, for a
plain `TComponent`). Reading creates children with `FindClass` (the
classes `RegisterClass` registered) and the root as their owner, sets
the root's published field of each child's name, resolves component
references at the end, and calls `Loaded`. `TObject.FieldAddress`,
`MethodAddress` and `MethodName` read the published field and method
tables. Collections (`TCollection`, `TCollectionItem`,
`TOwnedCollection`, FPC's) stream as `Columns = < item ... end >`.
Variant properties are written by their value's type, as FPC writes
them, and read back (strings as OleStr, integers as Integer or Int64).

## Interfaces

COM interfaces, FPC's default kind: reference counted, with a GUID.

```pascal
type
  IShape = interface
    ['{A0000000-0000-0000-0000-000000000001}']
    function Area: Double;
    function GetName: string;
    property Name: string read GetName;
  end;

  TSquare = class(TInterfacedObject, IShape)
    FSide: Double;
    constructor Create(ASide: Double);
    function Area: Double;
    function GetName: string;
  end;
...
var
  S: IShape;
begin
  S := TSquare.Create(2);       { freed when the last reference goes }
  WriteLn(S.Name, ' ', S.Area:0:1);
  if Supports(S, INamed, N) then ...
end.
```

- An interface lists methods and properties (through its methods); it
  descends from `IInterface` (alias `IUnknown`: `QueryInterface`,
  `_AddRef`, `_Release`) or from the interface in parentheses. A class
  lists the interfaces it implements after its parent (`class(TParent,
  IFoo, IBar)`, or `class(IFoo)` with TObject as parent), and must have
  a method of each name. Descendant classes implement them too, with
  their overrides of virtual methods. Generic interfaces work
  (`specialize IBox<Integer>` in the list).
- `TInterfacedObject` counts references and destroys itself at zero;
  `RefCount` reads the count. `TObject.GetInterface(IID, Ref)` finds an
  interface by GUID; an interface's name used as a value is its `TGUID`
  (`I.QueryInterface(IFoo, Ref)`).
- Storing a reference counts it and releases the one replaced; locals,
  value parameters and fields release theirs as strings do, and records,
  arrays and dynamic arrays of interfaces are counted too. `const`
  parameters aren't counted, as in FPC.
- A class instance converts implicitly to an interface its class lists
  (not to that interface's ancestors, as in FPC), and an interface to
  its ancestors. `X as IFoo` and `X is IFoo` (X an instance or an
  interface) look the interface up at run time (`as` stops with runtime
  error 219 if it isn't there), `I as TFoo` gives the instance, and
  `Supports(X, IFoo)` / `Supports(X, IFoo, Ref)` answer the question
  (setting `Ref` or nil). `IFoo(X)` converts too, giving nil where the
  class lacks IFoo. References compare (`I = J`, `I <> nil`,
  `Assigned(I)`) by instance.
- As FPC does, the reference a function returns (or `as` makes) is held
  in a hidden temporary until a later statement reuses it or the routine
  ends, so objects behind such temporaries are destroyed at the same
  points as in FPC. Global interface variables aren't released at the
  program's end.
- Method resolution clauses name the method implementing an interface's
  method when the names differ: `function IReader.Name = ReaderName;`.
- A property can implement an interface for the class (`property Inner:
  IWriter read FInner implements IWriter;`): the class's IWriter is what
  the property gives, an interface or an instance of a class
  implementing it (whose count then decides its lifetime, as in FPC).
- `{$interfaces corba}` makes the interfaces declared after it CORBA
  ones: not counted, not descending from IInterface, and their GUID may
  be any string (`['IShape']`).

## Exceptions

```pascal
uses SysUtils;

procedure Load(const Name: string);
begin
  if Name = '' then
    raise EArgumentException.Create('no file name');
  ...
end;

begin
  try
    Load(ParamStr(1));
    WriteLn(StrToInt('12x'));
  except
    on E: EConvertError do WriteLn('not a number: ', E.Message);
    on E: Exception do WriteLn(E.ClassName, ': ', E.Message);
  end;
end.
```

- `raise Obj` raises any class instance; `[at Address]` is accepted and
  ignored. A bare `raise` in a handler raises the exception being handled
  again.
- `try ... except ... end`: the `on [Name:] Class do Statement` handlers
  are tried in order, then `else`; without `on` handlers the statements
  after `except` handle everything. An exception no handler matches goes
  on to the enclosing `try`. A handled exception is freed when its
  handler ends.
- `try ... finally ... end`: the `finally` statements run however the
  block is left, by an exception, `exit`, `break` or `continue`.
- An exception nothing handles stops the program with exit code 217 and
  FPC's report on stderr (`An unhandled exception occurred at $...:`,
  then `EClass: message`).
- A class's constructor that raises destroys the instance it was making
  (its destructor runs) before the exception goes on.
- Routines an exception leaves early release their string locals.
- SysUtils has FPC's `Exception` (`Create`, `CreateFmt`, `CreateHelp`,
  `Message`, `HelpContext`, `ToString`) and its usual descendants
  (`EConvertError`, `EInvalidCast`, `EAbort`, `EDivByZero`,
  `ERangeError`, `EIntOverflow`, `EAccessViolation`, `EInOutError`,
  `EOutOfMemory`, `EArgumentException`, `ENotImplemented`...), `Abort`
  and `ExceptObject`. With SysUtils, the runtime errors the compiler
  checks for (a failed `as`, an abstract method call) become the
  matching exceptions; `StrToInt` raises `EConvertError`. `RunError`
  still stops the program, as in FPC.
- Implementation: frames with `setjmp`/`longjmp`, as FPC uses on most
  targets. A routine containing a `try` statement is compiled without
  optimization.
- An integer division by zero is runtime error 200 and a memory access
  fault (a nil pointer...) runtime error 216: with SysUtils they raise
  `EDivByZero` and `EAccessViolation`; without, FPC's report
  (`Runtime error 200 at $...`) goes to stderr and the program stops
  with that exit code. Range and overflow check failures raise
  `ERangeError` and `EIntOverflow` with SysUtils.
- As in FPC, a `goto` into or out of a `try` block (or its `except` or
  `finally` part) is a compile-time error.
- Floating point errors raise `EZeroDivide`, `EInvalidOp` and
  `EOverflow` (see Arithmetic / math).

## Generics

Generic classes, objects, records and other types, with FPC's syntax
(`generic TStack<T> = class ... end;`, `specialize TStack<Integer>`) or
Delphi's (`TStack<T> = class`, `TStack<Integer>`), in programs and units:

```pascal
type
  generic TStack<T> = class
  private
    FItems: array of T;
    FCount: Integer;
  public
    procedure Push(const Item: T);
    function Pop: T;
  end;
  TIntStack = specialize TStack<Integer>;

procedure TStack.Push(const Item: T);
...
var S: TIntStack;
begin
  S := TIntStack.Create;           { or specialize TStack<Integer>.Create }
```

Generic routines too: `generic function Larger<T>(const A, B: T): T;`
called as `specialize Larger<Integer>(3, 9)` (or `function Larger<T>` and
`Larger<Integer>(3, 9)` in Delphi mode).

Each specialization is a copy of the generic with its parameters replaced,
made once per distinct list of arguments (so `TStack<Integer>` written
twice is one type). Its `ClassName` is FPC's: `TStack<System.LongInt>`,
each argument named with the unit (or program) declaring it. A generic class can derive from a specialization
(`class(specialize TBase<T>)`); `Default(T)` gives a parameter type's zero
value; constraints (`<T: class>`) are accepted and not checked. The `fgl`
unit has `TFPGList<T>`, `TFPGObjectList<T>` and `TFPGMap<TKey, TData>`, and
`Generics.Collections` has `TList<T>`, `TObjectList<T>`, `TStack<T>`,
`TQueue<T>`, `TDictionary<TKey, TValue>`, `TPair` and `TArray`.

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
| `int(r)` / `frac(r)` | real → real         | whole part / fraction       |
| `trunc(r)`    | real → integer             | toward zero                 |
| `round(r)`    | real → integer             | half-to-even                |
| `odd(n)`      | integer → boolean          |                             |
| `maxint`      | constant: `9_223_372_036_854_775_807` |                  |
| `pi`          | real                       |                             |
| `random(n)` / `random` | integer in `0..n-1` / real in `[0, 1)` | FPC 3.2's Mersenne Twister: a given `RandSeed` gives FPC's numbers, for LongInt and Int64 arguments alike (an Int64 one, such as `Length(A)`, draws as FPC's Int64 overload does); `randomize` seeds from the clock |

A floating point division by zero, an invalid operation (`0/0`,
`Sqrt(-1)`, `Ln(-1)`, `Frac` of an infinity, `Trunc`/`Round` of a value
outside Int64) and an overflow (also a Double too large for the Single
it is stored in) stop the program with FPC's runtime errors 208, 207
and 205, or raise `EZeroDivide`, `EInvalidOp` and `EOverflow` with
SysUtils, unless the Math unit's `SetExceptionMask` masks them
(underflow and inexact results are masked, as in FPC; a masked
`Trunc` saturates). On 64-bit ARM macOS, as FPC does there, every one of
them is runtime error 216 instead, `EAccessViolation` ("Access
violation") with SysUtils. Arithmetic on infinities and NaNs already
there doesn't trap.

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
| `WriteStr(s, args)` | what `Write(args)` would write, into `s` (`:width:precision` too) |
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

Reals come out exactly as FPC writes them (its `str_real`, digit for
digit): unformatted, in scientific form with 17 significant digits and a
3-digit exponent (` 1.5000000000000000E+000`), 10 digits and 2 for a
`Single` (or a literal a Single holds exactly); `r:w` fits the mantissa
to the width; `r:w:d` is fixed point with FPC's rounding. Infinities are
`+Inf` and `-Inf`, NaN is `Nan`. `Str` formats the same way.

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

- Turbo Pascal `object` types, Object Pascal classes and COM interfaces
  are supported (see Objects, Classes and Interfaces), and so are units
  and the `uses` clause (see Units).
- The transcendental functions (`Sin`, `Exp`, `Ln`...) come from the C
  library, so their last bit can differ from FPC's own routines.
- `Integer` is 32 bits wide in `{$mode objfpc}` and `{$mode delphi}`, as
  in FPC (`MaxInt` follows), and 64 bits otherwise (FPC's `{$mode fpc}`
  and `{$mode tp}` make it 16). The FPC-derived units (SysUtils,
  Classes, the socket and HTTP units) are compiled in objfpc mode, as in
  FPC; a routine with 64-bit Integer parameters passed as a callback to
  them (`List.CustomSort(@MyCompare)`) is adapted automatically.
- No `goto` to non-numeric labels (numeric only).
- Conformant array parameters are limited; prefer typed arrays.

These limitations are tracked in the issues backlog and may relax in
future releases.
