# Mini-Pascal Language TODO

Remaining features not yet implemented, compared to standard/Turbo Pascal.

## Implemented

- **Types:** integer, real, boolean, char, string, pointer, array (single & multi-dim), record (with variant parts), enumerated, subrange, set, file/text, procedural, conformant array, named aliases. `packed` accepted as no-op.
- **Declarations:** program (with parameters `(input, output)`), label, const (with optional type annotation), type, var, procedure, function (incl. nested with capture-lifting), procedural and functional parameters, conformant array parameters, value/var parameters
- **Statements:** assignment, if/then/else, while/do, for/to/downto, repeat/until, case/of, with, goto/label, begin/end blocks, procedure calls (incl. indirect through procedural variables), writeln/write/readln (with format specifiers and file form), new/dispose
- **Expressions:** arithmetic (+, -, *, div, /, mod), comparisons (=, <>, <, >, <=, >=), boolean (and, or, not), unary negation, in (set membership), function calls (direct or indirect), type casts (`integer(x)` etc.), array indexing (single & multi-dim, fixed or conformant), record field access, pointer dereference, set constructors, `nil`, `maxint`
- **Builtins:** length, ord, chr, string concat (+), string compare, abs, sqr, sqrt, trunc, round, sin, cos, arctan, exp, ln, odd, succ, pred, inc, dec, low, high, copy, concat, pos, delete, insert, str, val, upcase, include, exclude, pack, unpack
- **File I/O:** assign, reset, rewrite, append, close, read, readln, write, writeln, eof, eoln, seek, filepos, filesize, page, get, put, f^ buffer variable, ioresult; predefined `input` and `output` text files
- **Assignments:** simple, pointer deref, array index, multi-dim index, field, chained LValues (`a[i].field := expr`), file buffer (`f^ := x`)
- **Forward declarations:** `procedure X; forward;` for mutual recursion
- **Set comparisons:** `=`, `<>`, `<=` (subset), `>=` (superset)
- **Compiler directives:** `{$R+/-}` bounds check, `{$Q+/-}` overflow check, `{$I+/-}` I/O check

---

## Standard Functions & Procedures

### P0 - Arithmetic / Conversion
- [x] `abs(x)` — absolute value (integer and real)
- [x] `sqr(x)` — square (x * x)
- [x] `sqrt(x)` — square root (returns real)
- [x] `trunc(x)` — truncate real to integer
- [x] `round(x)` — round real to integer
- [x] `sin(x)`, `cos(x)`, `arctan(x)`, `exp(x)`, `ln(x)` — math functions

### P0 - Ordinal
- [x] `succ(x)` — successor (x + 1 for ordinals)
- [x] `pred(x)` — predecessor (x - 1 for ordinals)
- [x] `inc(x)` / `inc(x, n)` — increment variable in-place
- [x] `dec(x)` / `dec(x, n)` — decrement variable in-place
- [x] `low(x)` / `high(x)` — bounds of array or ordinal type

### P1 - String Operations
- [x] `copy(s, index, count)` — substring
- [x] `concat(s1, s2, ...)` — concatenate (variadic)
- [x] `pos(substr, s)` — find substring position
- [x] `delete(s, index, count)` — remove from string (mutating)
- [x] `insert(source, s, index)` — insert into string (mutating)
- [x] `str(x, s)` — number to string
- [x] `val(s, x, code)` — string to number
- [x] `upcase(ch)` — uppercase a char

### P1 - Set Operations
- [x] `include(s, elem)` — add element to set
- [x] `exclude(s, elem)` — remove element from set
- [x] Set comparison operators: `=`, `<>`, `<=` (subset), `>=` (superset)

---

## File I/O

- [x] `file of <type>` — typed file type (parsed; runtime treats as text-style)
- [x] `text` — text file type
- [x] `assign(f, filename)` — associate file variable with path
- [x] `reset(f)` — open for reading
- [x] `rewrite(f)` — open for writing
- [x] `append(f)` — open for appending (Turbo Pascal extension)
- [x] `close(f)` — close file
- [x] `read(f, vars...)` / `write(f, exprs...)` — file read/write
- [x] `readln(f, vars...)` / `writeln(f, exprs...)` — file read/write with newline
- [x] `eof(f)` — end-of-file test
- [x] `eoln(f)` — end-of-line test (peeks next char)
- [x] `seek(f, pos)` / `filepos(f)` / `filesize(f)` — random access via fseek/ftell
- [x] `ioresult` — I/O error code (with `{$I+/-}` directive recognized)

---

## Language Features

### ~~P0 - Nested Procedures/Functions~~ (DONE)
- [x] Procedures/functions declared inside other procedures/functions
- [x] Access to enclosing scope variables (via lifted captures, equivalent to static link)

### ~~P1 - Forward Declarations~~ (DONE)
- [x] `forward` directive for mutual recursion

### ~~P1 - Nested LValue Assignments~~ (DONE)
- [x] `a[i].field := expr` — index then field
- [x] `p^.next^ := expr` — chained pointer dereference
- [x] `r.field[i] := expr` — field then index
- [x] General chained LValue: any combination of `.field`, `[index]`, `^`

### P2 - Units / Modules
- [ ] `unit` declaration with `interface` / `implementation` sections
- [ ] `uses` clause for importing units

### P2 - Object-Oriented (Turbo Pascal 5.5+)
- [ ] `object` types with methods and inheritance
- [ ] `constructor` / `destructor`
- [ ] `virtual` methods and VMT

### P2 - Exception Handling (Delphi)
- [ ] `try..except..end`
- [ ] `try..finally..end`
- [ ] `raise`

---

## Type System Improvements

- [x] Typed constants (`const x: integer = 42` — mutable, initialized)
- [x] String length type (`string[N]` — parsed; treated as plain string)
- [x] Packed arrays / packed records (`packed` accepted; layout unchanged)
- [x] Type coercion / type casting (`integer(x)`, `char(x)`, `real(x)`, `boolean(x)`)
- [x] Conformant array parameters (ISO 7185)
- [x] Procedural and functional parameters (Wirth)

---

## Codegen / Runtime

- [x] Bounds checking for arrays (with `{$R+}` switch)
- [x] Overflow checking for integer arithmetic (with `{$Q+}` switch)
- [ ] Stack overflow detection
- [x] `readln` for types other than integer (real, char, string; multi-target)
- [x] Write format specifiers: `write(x:10)`, `write(r:8:2)`
- [x] `nil` constant for pointer types
- [ ] Proper string memory management (currently uses static/leaked strings)
- [ ] Dynamic string support (heap-allocated, reference-counted or copied)

---

## IDE / Debugger

- [x] Syntax highlighting for new keywords: `set`, `in`, `label`, `goto`, `case`, `with`,
      `file`, `assign`, `reset`, `rewrite`, `close`, `eof`, `eoln`, `nil`
- [x] Display set values in watch window (decoded as Pascal set literal)
- [ ] Display enum values by name in watch window (still shows ordinal — needs DWARF enum metadata)
- [ ] Display variant record fields in watch window (lldb shows raw bytes for variant union)

---

## Priority Key

- **P0** — Expected in any Pascal compiler; likely to hit in real programs
- **P1** — Common Turbo Pascal features; needed for non-trivial programs
- **P2** — Advanced features; nice-to-have for compatibility
