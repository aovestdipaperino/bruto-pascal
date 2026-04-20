# Mini-Pascal Language TODO

Remaining features not yet implemented, compared to standard/Turbo Pascal.

## Implemented

- **Types:** integer, real, boolean, char, string, pointer, array (single & multi-dim), record (with variant parts), enumerated, subrange, set, named aliases
- **Declarations:** program, label, const, type, var, procedure, function, value/var parameters
- **Statements:** assignment, if/then/else, while/do, for/to/downto, repeat/until, case/of, with, goto/label, begin/end blocks, procedure calls, writeln/write/readln, new/dispose
- **Expressions:** arithmetic (+, -, *, div, /, mod), comparisons (=, <>, <, >, <=, >=), boolean (and, or, not), unary negation, in (set membership), function calls, array indexing (single & multi-dim), record field access, pointer dereference, set constructors
- **Builtins:** length, ord, chr, string concat (+), string compare

---

## Standard Functions & Procedures

### P0 - Arithmetic / Conversion
- [ ] `abs(x)` — absolute value (integer and real)
- [ ] `sqr(x)` — square (x * x)
- [ ] `sqrt(x)` — square root (returns real)
- [ ] `trunc(x)` — truncate real to integer
- [ ] `round(x)` — round real to integer
- [ ] `sin(x)`, `cos(x)`, `arctan(x)`, `exp(x)`, `ln(x)` — math functions

### P0 - Ordinal
- [ ] `succ(x)` — successor (x + 1 for ordinals)
- [ ] `pred(x)` — predecessor (x - 1 for ordinals)
- [ ] `inc(x)` / `inc(x, n)` — increment variable in-place
- [ ] `dec(x)` / `dec(x, n)` — decrement variable in-place
- [ ] `low(x)` / `high(x)` — bounds of array or ordinal type

### P1 - String Operations
- [ ] `copy(s, index, count)` — substring
- [ ] `concat(s1, s2, ...)` — concatenate (variadic)
- [ ] `pos(substr, s)` — find substring position
- [ ] `delete(s, index, count)` — remove from string (mutating)
- [ ] `insert(source, s, index)` — insert into string (mutating)
- [ ] `str(x, s)` — number to string
- [ ] `val(s, x, code)` — string to number
- [ ] `upcase(ch)` — uppercase a char

### P1 - Set Operations
- [ ] `include(s, elem)` — add element to set
- [ ] `exclude(s, elem)` — remove element from set
- [ ] Set comparison operators: `=`, `<>`, `<=` (subset), `>=` (superset)

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

### P1 - Forward Declarations
- [ ] `forward` directive for mutual recursion
- [ ] Token `KwForward` already exists in lexer but is unused by parser

### P1 - Nested LValue Assignments
- [ ] `a[i].field := expr` — index then field
- [ ] `p^.next^ := expr` — chained pointer dereference
- [ ] `r.field[i] := expr` — field then index
- [ ] General chained LValue: any combination of `.field`, `[index]`, `^`

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
