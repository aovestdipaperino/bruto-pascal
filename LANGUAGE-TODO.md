# Mini-Pascal Language TODO

Remaining features not yet implemented, compared to standard/Turbo Pascal.

## Implemented

- **Types:** integer, real, boolean, char, string, pointer, array (single & multi-dim), record (with variant parts), enumerated, subrange, set, named aliases
- **Declarations:** program, label, const, type, var, procedure, function, value/var parameters
- **Statements:** assignment, if/then/else, while/do, for/to/downto, repeat/until, case/of, with, goto/label, begin/end blocks, procedure calls, writeln/write/readln, new/dispose
- **Expressions:** arithmetic (+, -, *, div, /, mod), comparisons (=, <>, <, >, <=, >=), boolean (and, or, not), unary negation, in (set membership), function calls, array indexing (single & multi-dim), record field access, pointer dereference, set constructors
- **Builtins:** length, ord, chr, string concat (+), string compare, abs, sqr, sqrt, trunc, round, sin, cos, arctan, exp, ln, succ, pred, inc, dec, low, high, copy, concat, pos, delete, insert, str, val, upcase, include, exclude
- **Assignments:** simple, pointer deref, array index, multi-dim index, field, chained LValues (`a[i].field := expr`)
- **Forward declarations:** `procedure X; forward;` for mutual recursion
- **Set comparisons:** `=`, `<>`, `<=` (subset), `>=` (superset)

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

- [ ] `file of <type>` — typed file type
- [ ] `text` — text file type
- [ ] `assign(f, filename)` — associate file variable with path
- [ ] `reset(f)` — open for reading
- [ ] `rewrite(f)` — open for writing
- [ ] `append(f)` — open for appending (Turbo Pascal extension)
- [ ] `close(f)` — close file
- [ ] `read(f, vars...)` / `write(f, exprs...)` — file read/write
- [ ] `readln(f, vars...)` / `writeln(f, exprs...)` — file read/write with newline
- [ ] `eof(f)` / `eoln(f)` — end-of-file / end-of-line tests
- [ ] `seek(f, pos)` / `filepos(f)` / `filesize(f)` — random access (typed files)
- [ ] `ioresult` — I/O error code (with `{$I-}` equivalent)

---

## Language Features

### P0 - Nested Procedures/Functions
- [ ] Procedures/functions declared inside other procedures/functions
- [ ] Access to enclosing scope variables (static link / display)

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

- [ ] Typed constants (`const x: integer = 42` — mutable, initialized)
- [ ] String length type (`string[N]` — fixed-length strings)
- [ ] Packed arrays / packed records
- [ ] Type coercion / type casting (`integer(x)`, `char(x)`)
- [ ] Conformant array parameters (ISO Pascal)

---

## Codegen / Runtime

- [ ] Bounds checking for arrays and subranges (with compiler switch)
- [ ] Overflow checking for integer arithmetic
- [ ] Stack overflow detection
- [ ] `readln` for types other than integer (real, char, string)
- [ ] Write format specifiers: `write(x:10)`, `write(r:8:2)`
- [ ] `nil` constant for pointer types
- [ ] Proper string memory management (currently uses static/leaked strings)
- [ ] Dynamic string support (heap-allocated, reference-counted or copied)

---

## IDE / Debugger

- [ ] Syntax highlighting for new keywords: `set`, `in`, `label`, `goto`, `case`, `with`
  (already partially done — verify all are highlighted)
- [ ] Display set values in watch window
- [ ] Display enum values by name in watch window (currently shows ordinal)
- [ ] Display variant record fields in watch window

---

## Priority Key

- **P0** — Expected in any Pascal compiler; likely to hit in real programs
- **P1** — Common Turbo Pascal features; needed for non-trivial programs
- **P2** — Advanced features; nice-to-have for compatibility
