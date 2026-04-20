# Pascal Language Features Batch 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 8 missing Pascal language features: case/of, with, goto/label, sets, enumerated types, subrange types, variant records, and multi-dimensional array indexing.

**Architecture:** Each feature follows the same pipeline: add AST nodes, add lexer tokens/keywords, add parser rules, add codegen LLVM IR emission, add syntax highlighter keywords, update `collect_stmt_lines` for breakpoint support, and add integration tests. All changes are in `bruto-pascal-lang/src/`.

**Tech Stack:** Rust, inkwell (LLVM bindings), turbo-vision syntax highlighting

---

## File Map

All changes are in `bruto-pascal-lang/src/`:

- **Modify:** `ast.rs` — New AST node variants for all 8 features
- **Modify:** `parser.rs` — New lexer tokens, keywords, and parser rules
- **Modify:** `codegen.rs` — LLVM IR emission for each new construct
- **Modify:** `pascal_syntax.rs` — Add new keywords to highlighter
- **Modify:** `lib.rs` — Update `collect_stmt_lines` for new statement types, add tests

---

### Task 1: Enumerated Types

Enumerated types are a prerequisite for sets and subrange types. An enum `type Color = (Red, Green, Blue)` declares ordinal constants (0, 1, 2) and a named type stored as i64.

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`
- Modify: `bruto-pascal-lang/src/lib.rs`

- [ ] **Step 1: Add AST node for enumerated type**

In `ast.rs`, add a new variant to `PascalType`:

```rust
// In PascalType enum, after Named(String):
/// Enumerated type: (val1, val2, val3)
Enum {
    /// The type name (e.g., "Color") — set during type section parsing
    name: String,
    values: Vec<String>,
},
```

- [ ] **Step 2: Add parser token and keyword for enum parsing**

In `parser.rs`, the lexer already handles `(`, `)`, `,`, and identifiers. No new tokens needed. Add enum type parsing in `parse_type`:

```rust
// In parse_type(), before the match on self.peek(), add:
// Check for enumerated type: (val1, val2, val3)
if *self.peek() == Tok::LParen {
    // Could be an enum type: (Red, Green, Blue)
    // Peek ahead to distinguish from grouped expression
    return self.parse_enum_type();
}
```

Add the `parse_enum_type` method:

```rust
fn parse_enum_type(&mut self) -> Result<PascalType, ParseError> {
    self.expect(&Tok::LParen)?;
    let mut values = Vec::new();
    let (first, _) = self.expect_ident()?;
    values.push(first);
    while *self.peek() == Tok::Comma {
        self.advance();
        let (name, _) = self.expect_ident()?;
        values.push(name);
    }
    self.expect(&Tok::RParen)?;
    Ok(PascalType::Enum { name: String::new(), values })
}
```

Update `parse_type_section` to set the enum name after parsing:

```rust
// In parse_type_section, after parsing each type declaration:
// If the type is an enum, set its name field
let mut ty = self.parse_type()?;
if let PascalType::Enum { ref mut name, .. } = ty {
    *name = decl_name.clone();
}
```

Where `decl_name` is the name from `expect_ident()` in the type section loop.

- [ ] **Step 3: Add codegen for enumerated types**

In `codegen.rs`:

Add a field to `CodeGen` to store enum value → ordinal mappings:

```rust
// In CodeGen struct:
enum_values: HashMap<String, i64>,  // maps enum constant name → ordinal value
enum_type_values: HashMap<String, Vec<String>>,  // maps enum type name → list of value names
```

Initialize both as `HashMap::new()` in `CodeGen::new()`.

In `compile()`, when registering type aliases, also register enum values:

```rust
// After: self.type_defs.insert(td.name.clone(), td.ty.clone());
if let PascalType::Enum { values, .. } = &td.ty {
    for (i, val) in values.iter().enumerate() {
        self.enum_values.insert(val.clone(), i as i64);
    }
    self.enum_type_values.insert(td.name.clone(), values.clone());
}
```

In `llvm_type_for`, enum types map to i64:

```rust
// Add to match in llvm_type_for:
PascalType::Enum { .. } => self.context.i64_type().as_basic_type_enum(),
```

In `sizeof_type`:

```rust
PascalType::Enum { .. } => 8,
```

In `resolve_type`, enum passes through (already a concrete type):

```rust
PascalType::Enum { .. } => ty.clone(),
```

In `compile_var_decl`, initialize enum vars to 0 (same as Integer):

```rust
PascalType::Enum { .. } => {
    self.builder.build_store(alloca, self.context.i64_type().const_int(0, false))
        .map_err(|e| CodeGenError::new(e.to_string(), Some(decl.span)))?;
}
```

In `compile_expr` for `Expr::Var`, check if the name is an enum constant:

```rust
// In compile_expr, Expr::Var case, before the existing variable lookup:
if let Some(&ordinal) = self.enum_values.get(name.as_str()) {
    return Ok(self.context.i64_type().const_int(ordinal as u64, true).into());
}
```

In `infer_expr_type` for `Expr::Var`:

```rust
// Before the existing var_types lookup:
if self.enum_values.contains_key(name.as_str()) {
    // Find which enum type this value belongs to
    for (type_name, values) in &self.enum_type_values {
        if values.contains(name) {
            return PascalType::Named(type_name.clone());
        }
    }
    return PascalType::Integer;
}
```

In `create_debug_type`:

```rust
PascalType::Enum { .. } => {
    self.di_builder.create_basic_type("long", 64, 0x05, DIFlags::ZERO)
        .ok().map(|t| t.as_type())
}
```

In `compile_write`, treat enum like Integer:

```rust
// In the match on arg_type in compile_write:
PascalType::Enum { .. } => ("bruto_write_int", "bruto_capture_write_int"),
```

- [ ] **Step 4: Add Eq derive for Enum variant**

The `PascalType` enum derives `PartialEq, Eq`. The new `Enum` variant with `String` and `Vec<String>` fields is fine since those implement `Eq`.

- [ ] **Step 5: Write test**

In `lib.rs` tests:

```rust
#[test]
fn enum_type() {
    let (ok, out) = build_and_run_source(
        "program T;\ntype\n  Color = (Red, Green, Blue);\nvar c: Color;\nbegin\n  c := Green;\n  writeln(c)\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "1");
}
```

- [ ] **Step 6: Run tests and verify**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test`

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: add enumerated types"
```

---

### Task 2: Subrange Types

Subrange types restrict a variable to a range of ordinal values: `type SmallInt = 1..10`. At the LLVM level, they are stored as i64 (no bounds checking for now — matching classic Turbo Pascal behavior).

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`

- [ ] **Step 1: Add AST node**

In `ast.rs`, add to `PascalType`:

```rust
/// Subrange type: lo..hi (stored as i64)
Subrange { lo: i64, hi: i64 },
```

- [ ] **Step 2: Add parser rule**

In `parser.rs`, in `parse_type()`, before the keyword match, detect integer literal at start (subrange starts with a number or `-`):

```rust
// Before the keyword match in parse_type:
if matches!(self.peek(), Tok::IntLit(_) | Tok::Minus) {
    let lo = self.parse_int_literal()?;
    self.expect(&Tok::DotDot)?;
    let hi = self.parse_int_literal()?;
    return Ok(PascalType::Subrange { lo, hi });
}
```

- [ ] **Step 3: Add codegen support**

Subrange is stored as i64. Add to all relevant matches in `codegen.rs`:

```rust
// llvm_type_for:
PascalType::Subrange { .. } => self.context.i64_type().as_basic_type_enum(),

// sizeof_type:
PascalType::Subrange { .. } => 8,

// compile_var_decl initialization:
PascalType::Subrange { .. } => {
    self.builder.build_store(alloca, self.context.i64_type().const_int(0, false))
        .map_err(|e| CodeGenError::new(e.to_string(), Some(decl.span)))?;
}

// resolve_type:
PascalType::Subrange { .. } => ty.clone(),

// create_debug_type:
PascalType::Subrange { .. } => {
    self.di_builder.create_basic_type("long", 64, 0x05, DIFlags::ZERO)
        .ok().map(|t| t.as_type())
}

// compile_write:
PascalType::Subrange { .. } => ("bruto_write_int", "bruto_capture_write_int"),
```

- [ ] **Step 4: Write test**

```rust
#[test]
fn subrange_type() {
    let (ok, out) = build_and_run_source(
        "program T;\ntype\n  SmallInt = 1..10;\nvar x: SmallInt;\nbegin\n  x := 5;\n  writeln(x)\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "5");
}
```

- [ ] **Step 5: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add subrange types"
```

---

### Task 3: Sets

Pascal sets: `set of <ordinal-type>`. Represented as a 256-bit bitmask (i256 or an array of 4 x i64). Operations: `+` (union), `-` (difference), `*` (intersection), `in` (membership test), `=`, `<>`, `<=` (subset), `>=` (superset).

Set constructors: `[1, 3, 5..10]`.

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`

- [ ] **Step 1: Add AST nodes**

In `ast.rs`:

Add to `PascalType`:

```rust
/// Set of ordinal type — stored as 256-bit bitmask (4 x i64)
Set { elem: Box<PascalType> },
```

Add to `Expr`:

```rust
/// Set constructor: [1, 3, 5..10]
SetConstructor {
    elements: Vec<SetElement>,
    span: Span,
},
```

Add new type:

```rust
/// An element in a set constructor
#[derive(Debug, Clone)]
pub enum SetElement {
    Single(Expr),
    Range(Expr, Expr),
}
```

Add to `BinOp`:

```rust
In,  // element membership: x in S
```

Update `Expr::span()` match:

```rust
| Self::SetConstructor { span, .. } => *span,
```

- [ ] **Step 2: Add lexer token and parser rules**

In `parser.rs`, add keyword:

```rust
// In the keyword match in Lexer::next_token:
"set" => Tok::KwSet,
"in" => Tok::KwIn,
```

Add to `Tok` enum:

```rust
KwSet, KwIn,
```

Add `Display` impl for new tokens:

```rust
Tok::KwSet => write!(f, "'set'"),
Tok::KwIn => write!(f, "'in'"),
```

In `parse_type`, add set type parsing:

```rust
if *self.peek() == Tok::KwSet {
    self.advance();
    self.expect(&Tok::KwOf)?;
    let elem = self.parse_type()?;
    return Ok(PascalType::Set { elem: Box::new(elem) });
}
```

In `parse_primary`, add set constructor parsing when `[` is seen:

```rust
Tok::LBracket => {
    self.advance();
    let mut elements = Vec::new();
    if *self.peek() != Tok::RBracket {
        elements.push(self.parse_set_element()?);
        while *self.peek() == Tok::Comma {
            self.advance();
            elements.push(self.parse_set_element()?);
        }
    }
    let span = self.span();
    self.expect(&Tok::RBracket)?;
    Ok(Expr::SetConstructor { elements, span })
}
```

Add helper:

```rust
fn parse_set_element(&mut self) -> Result<SetElement, ParseError> {
    let first = self.parse_expr()?;
    if *self.peek() == Tok::DotDot {
        self.advance();
        let last = self.parse_expr()?;
        Ok(SetElement::Range(first, last))
    } else {
        Ok(SetElement::Single(first))
    }
}
```

In `parse_comparison`, add `in` operator (same precedence as comparisons):

```rust
Tok::KwIn => BinOp::In,
```

- [ ] **Step 3: Add codegen for sets**

Sets are stored as `[4 x i64]` (256-bit bitmask, supporting ordinals 0..255).

In `llvm_type_for`:

```rust
PascalType::Set { .. } => {
    self.context.i64_type().array_type(4).as_basic_type_enum()
}
```

In `sizeof_type`:

```rust
PascalType::Set { .. } => 32,  // 4 * 8 bytes
```

In `compile_var_decl`, zero-initialize sets (aggregate — already handled by the catch-all).

In `compile_expr`, add `SetConstructor`:

```rust
Expr::SetConstructor { elements, span } => {
    // Allocate a temporary [4 x i64] zeroed
    let set_ty = self.context.i64_type().array_type(4);
    let alloca = self.builder.build_alloca(set_ty, "set_tmp")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
    // Zero it
    let zero = set_ty.const_zero();
    self.builder.build_store(alloca, zero)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;

    for elem in elements {
        match elem {
            SetElement::Single(expr) => {
                let val = self.compile_expr(expr)?;
                self.emit_set_include(alloca, val.into_int_value(), *span)?;
            }
            SetElement::Range(lo_expr, hi_expr) => {
                let lo = self.compile_expr(lo_expr)?.into_int_value();
                let hi = self.compile_expr(hi_expr)?.into_int_value();
                // Loop from lo to hi, include each
                self.emit_set_include_range(alloca, lo, hi, *span)?;
            }
        }
    }

    let val = self.builder.build_load(set_ty, alloca, "set_val")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
    Ok(val)
}
```

Add helper methods to `CodeGen`:

```rust
/// Set bit `ord` in the set at `set_ptr`. Bit layout: word = ord / 64, bit = ord % 64.
fn emit_set_include(
    &mut self, set_ptr: PointerValue<'ctx>, ord: inkwell::values::IntValue<'ctx>, span: Span,
) -> Result<(), CodeGenError> {
    let i64_ty = self.context.i64_type();
    let word_idx = self.builder.build_int_unsigned_div(ord, i64_ty.const_int(64, false), "word_idx")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let bit_idx = self.builder.build_int_unsigned_rem(ord, i64_ty.const_int(64, false), "bit_idx")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let bit = self.builder.build_left_shift(i64_ty.const_int(1, false), bit_idx, "bit")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let set_ty = i64_ty.array_type(4);
    let gep = unsafe {
        self.builder.build_in_bounds_gep(set_ty, set_ptr, &[i64_ty.const_int(0, false), word_idx], "set_gep")
            .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?
    };
    let cur = self.builder.build_load(i64_ty, gep, "cur_word")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let new = self.builder.build_or(cur.into_int_value(), bit, "or_bit")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_store(gep, new)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    Ok(())
}

fn emit_set_include_range(
    &mut self, set_ptr: PointerValue<'ctx>,
    lo: inkwell::values::IntValue<'ctx>, hi: inkwell::values::IntValue<'ctx>, span: Span,
) -> Result<(), CodeGenError> {
    let func = self.current_fn.unwrap();
    let i64_ty = self.context.i64_type();
    let cond_bb = self.context.append_basic_block(func, "setrange_cond");
    let body_bb = self.context.append_basic_block(func, "setrange_body");
    let end_bb = self.context.append_basic_block(func, "setrange_end");

    let counter = self.builder.build_alloca(i64_ty, "range_i")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_store(counter, lo)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_unconditional_branch(cond_bb)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

    self.builder.position_at_end(cond_bb);
    let cur = self.builder.build_load(i64_ty, counter, "cur_i")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?.into_int_value();
    let cmp = self.builder.build_int_compare(inkwell::IntPredicate::SLE, cur, hi, "range_cmp")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_conditional_branch(cmp, body_bb, end_bb)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

    self.builder.position_at_end(body_bb);
    self.emit_set_include(set_ptr, cur, span)?;
    let next = self.builder.build_int_add(cur, i64_ty.const_int(1, false), "next_i")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_store(counter, next)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_unconditional_branch(cond_bb)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

    self.builder.position_at_end(end_bb);
    Ok(())
}
```

For `BinOp::In` in `compile_binop`:

```rust
// At the top of compile_binop, before integer arithmetic:
if op == BinOp::In {
    // lhs is the ordinal, rhs is the set [4 x i64]
    let ord = lhs.into_int_value();
    let set_val = rhs;
    // We need the set in memory to GEP into it
    let set_ty = self.context.i64_type().array_type(4);
    let tmp = self.builder.build_alloca(set_ty, "in_set")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_store(tmp, set_val)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

    let i64_ty = self.context.i64_type();
    let word_idx = self.builder.build_int_unsigned_div(ord, i64_ty.const_int(64, false), "word_idx")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let bit_idx = self.builder.build_int_unsigned_rem(ord, i64_ty.const_int(64, false), "bit_idx")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let bit = self.builder.build_left_shift(i64_ty.const_int(1, false), bit_idx, "bit")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let gep = unsafe {
        self.builder.build_in_bounds_gep(set_ty, tmp, &[i64_ty.const_int(0, false), word_idx], "set_gep")
            .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?
    };
    let word = self.builder.build_load(i64_ty, gep, "word")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?.into_int_value();
    let masked = self.builder.build_and(word, bit, "masked")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let result = self.builder.build_int_compare(inkwell::IntPredicate::NE, masked, i64_ty.const_int(0, false), "in_result")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    return Ok(result.into());
}
```

For set binary ops (`+`, `-`, `*`, `=`, `<>`, `<=`, `>=`) in `compile_binop` — add after the `BinOp::In` check, before integer arithmetic. Check if both operands are arrays (sets):

```rust
if lhs.is_array_value() && rhs.is_array_value() {
    let set_ty = self.context.i64_type().array_type(4);
    let i64_ty = self.context.i64_type();
    let la = self.builder.build_alloca(set_ty, "l_set").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let ra = self.builder.build_alloca(set_ty, "r_set").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_store(la, lhs).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    self.builder.build_store(ra, rhs).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    let result_alloca = self.builder.build_alloca(set_ty, "res_set").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

    // Operate word-by-word (4 words)
    for w in 0..4u64 {
        let idx = i64_ty.const_int(w, false);
        let lg = unsafe { self.builder.build_in_bounds_gep(set_ty, la, &[i64_ty.const_int(0, false), idx], "lg").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))? };
        let rg = unsafe { self.builder.build_in_bounds_gep(set_ty, ra, &[i64_ty.const_int(0, false), idx], "rg").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))? };
        let og = unsafe { self.builder.build_in_bounds_gep(set_ty, result_alloca, &[i64_ty.const_int(0, false), idx], "og").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))? };
        let lw = self.builder.build_load(i64_ty, lg, "lw").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?.into_int_value();
        let rw = self.builder.build_load(i64_ty, rg, "rw").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?.into_int_value();
        let res_word = match op {
            BinOp::Add => self.builder.build_or(lw, rw, "union").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?,
            BinOp::Sub => {
                let not_r = self.builder.build_not(rw, "not_r").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
                self.builder.build_and(lw, not_r, "diff").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?
            }
            BinOp::Mul => self.builder.build_and(lw, rw, "inter").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?,
            _ => return Err(CodeGenError::new("unsupported set operator", Some(span))),
        };
        self.builder.build_store(og, res_word).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    }
    let result = self.builder.build_load(set_ty, result_alloca, "set_result").map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
    return Ok(result);
}
```

For set comparisons (`=`, `<>`, `<=`, `>=`) — these need to be handled before the general integer comparison path. This is complex enough that it should be deferred to a separate check for array-typed operands.

In `infer_expr_type`, add:

```rust
// For SetConstructor:
Expr::SetConstructor { .. } => PascalType::Set { elem: Box::new(PascalType::Integer) },
```

And for `BinOp::In`:

```rust
BinOp::In => PascalType::Boolean,
```

- [ ] **Step 4: Update syntax highlighter**

In `pascal_syntax.rs`, add `"set"` and `"in"` to the keyword list in `is_keyword`.

- [ ] **Step 5: Write test**

```rust
#[test]
fn set_operations() {
    let (ok, out) = build_and_run_source(
        "program T;\nvar s: set of integer;\n  x: boolean;\nbegin\n  s := [1, 3, 5..8];\n  x := 3 in s;\n  writeln(x);\n  x := 4 in s;\n  writeln(x)\nend.\n",
    );
    assert!(ok);
    let lines: Vec<&str> = out.trim().lines().collect();
    assert_eq!(lines[0], "true");
    assert_eq!(lines[1], "false");
}
```

- [ ] **Step 6: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add set types with in/union/diff/intersection"
```

---

### Task 4: Case/Of Statement

`case expr of val1: stmt; val2, val3: stmt; else stmt end`

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`
- Modify: `bruto-pascal-lang/src/lib.rs`

- [ ] **Step 1: Add AST node**

In `ast.rs`, add to `Statement`:

```rust
Case {
    expr: Expr,
    branches: Vec<CaseBranch>,
    else_branch: Option<Vec<Statement>>,
    span: Span,
},
```

Add new type:

```rust
/// A single case branch: one or more values → a statement list
#[derive(Debug, Clone)]
pub struct CaseBranch {
    pub values: Vec<CaseValue>,
    pub body: Vec<Statement>,
    pub span: Span,
}

/// A value or range in a case label
#[derive(Debug, Clone)]
pub enum CaseValue {
    Single(Expr),
    Range(Expr, Expr),
}
```

Update `Statement::span()`:

```rust
| Self::Case { span, .. } => *span,
```

- [ ] **Step 2: Add parser tokens and rules**

Add keyword token:

```rust
// In Tok enum:
KwCase,

// In keyword match:
"case" => Tok::KwCase,

// In Display:
Tok::KwCase => write!(f, "'case'"),
```

In `parse_statement`, add case:

```rust
Tok::KwCase => self.parse_case(),
```

Add parser method:

```rust
fn parse_case(&mut self) -> Result<Statement, ParseError> {
    let span = self.span();
    self.expect(&Tok::KwCase)?;
    let expr = self.parse_expr()?;
    self.expect(&Tok::KwOf)?;

    let mut branches = Vec::new();
    let mut else_branch = None;

    loop {
        if *self.peek() == Tok::End {
            break;
        }
        if *self.peek() == Tok::Else {
            self.advance();
            let mut stmts = Vec::new();
            if *self.peek() != Tok::End {
                stmts.push(self.parse_statement()?);
                while *self.peek() == Tok::Semi {
                    self.advance();
                    if *self.peek() == Tok::End { break; }
                    stmts.push(self.parse_statement()?);
                }
            }
            else_branch = Some(stmts);
            break;
        }

        let branch_span = self.span();
        let mut values = Vec::new();
        values.push(self.parse_case_value()?);
        while *self.peek() == Tok::Comma {
            self.advance();
            values.push(self.parse_case_value()?);
        }
        self.expect(&Tok::Colon)?;

        // Parse the body — either a single statement or begin..end
        let mut body = Vec::new();
        body.push(self.parse_statement()?);

        branches.push(CaseBranch { values, body, span: branch_span });

        // Expect semicolon between branches
        if *self.peek() == Tok::Semi {
            self.advance();
        }
    }

    self.expect(&Tok::End)?;
    Ok(Statement::Case { expr, branches, else_branch, span })
}

fn parse_case_value(&mut self) -> Result<CaseValue, ParseError> {
    let first = self.parse_expr()?;
    if *self.peek() == Tok::DotDot {
        self.advance();
        let last = self.parse_expr()?;
        Ok(CaseValue::Range(first, last))
    } else {
        Ok(CaseValue::Single(first))
    }
}
```

- [ ] **Step 3: Add codegen**

Case compiles to a chain of if-else (like a C switch without fallthrough). For each branch, compare the selector against each value/range.

```rust
Statement::Case { expr, branches, else_branch, span } => {
    self.compile_case(expr, branches, else_branch.as_deref(), *span)
}
```

Add method:

```rust
fn compile_case(
    &mut self,
    expr: &Expr,
    branches: &[CaseBranch],
    else_branch: Option<&[Statement]>,
    span: Span,
) -> Result<(), CodeGenError> {
    self.set_debug_loc(span);
    let sel_val = self.compile_expr(expr)?;
    let func = self.current_fn.unwrap();
    let end_bb = self.context.append_basic_block(func, "case_end");

    for branch in branches {
        let match_bb = self.context.append_basic_block(func, "case_match");
        let next_bb = self.context.append_basic_block(func, "case_next");

        // Build OR of all value matches
        let mut any_match: Option<inkwell::values::IntValue> = None;
        for val in &branch.values {
            let cmp = match val {
                CaseValue::Single(v) => {
                    let v_val = self.compile_expr(v)?;
                    self.builder.build_int_compare(
                        inkwell::IntPredicate::EQ,
                        sel_val.into_int_value(), v_val.into_int_value(), "case_eq",
                    ).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?
                }
                CaseValue::Range(lo, hi) => {
                    let lo_val = self.compile_expr(lo)?;
                    let hi_val = self.compile_expr(hi)?;
                    let ge = self.builder.build_int_compare(
                        inkwell::IntPredicate::SGE,
                        sel_val.into_int_value(), lo_val.into_int_value(), "case_ge",
                    ).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
                    let le = self.builder.build_int_compare(
                        inkwell::IntPredicate::SLE,
                        sel_val.into_int_value(), hi_val.into_int_value(), "case_le",
                    ).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
                    self.builder.build_and(ge, le, "case_range")
                        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?
                }
            };
            any_match = Some(match any_match {
                None => cmp,
                Some(prev) => self.builder.build_or(prev, cmp, "case_or")
                    .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?,
            });
        }

        self.builder.build_conditional_branch(any_match.unwrap(), match_bb, next_bb)
            .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

        self.builder.position_at_end(match_bb);
        for stmt in &branch.body {
            self.compile_statement(stmt)?;
        }
        self.builder.build_unconditional_branch(end_bb)
            .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

        self.builder.position_at_end(next_bb);
    }

    // Else branch
    if let Some(stmts) = else_branch {
        for stmt in stmts {
            self.compile_statement(stmt)?;
        }
    }
    self.builder.build_unconditional_branch(end_bb)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;

    self.builder.position_at_end(end_bb);
    Ok(())
}
```

- [ ] **Step 4: Update `collect_stmt_lines` in `lib.rs`**

```rust
ast::Statement::Case { branches, else_branch, span, .. } => {
    lines.insert(span.line as usize);
    for branch in branches {
        for stmt in &branch.body {
            collect_stmt_lines(stmt, lines);
        }
    }
    if let Some(stmts) = else_branch {
        for stmt in stmts {
            collect_stmt_lines(stmt, lines);
        }
    }
}
```

- [ ] **Step 5: Write test**

```rust
#[test]
fn case_statement() {
    let (ok, out) = build_and_run_source(
        "program T;\nvar x: integer;\nbegin\n  x := 2;\n  case x of\n    1: writeln('one');\n    2, 3: writeln('two or three');\n  else\n    writeln('other')\n  end\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "two or three");
}
```

- [ ] **Step 6: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add case/of statement"
```

---

### Task 5: Goto/Label

Pascal goto/label: `label 10, 20;` at the top, then `10: statement` and `goto 10`. Labels are numeric in standard Pascal.

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`
- Modify: `bruto-pascal-lang/src/lib.rs`

- [ ] **Step 1: Add AST nodes**

In `ast.rs`, add to `Program`:

```rust
pub labels: Vec<i64>,
```

Add to `Statement`:

```rust
Goto { label: i64, span: Span },
Label { label: i64, span: Span },
```

Update `Statement::span()`:

```rust
| Self::Goto { span, .. }
| Self::Label { span, .. } => *span,
```

- [ ] **Step 2: Add parser tokens and rules**

Add tokens:

```rust
// In Tok enum:
KwLabel, KwGoto,

// In keyword match:
"label" => Tok::KwLabel,
"goto" => Tok::KwGoto,

// In Display:
Tok::KwLabel => write!(f, "'label'"),
Tok::KwGoto => write!(f, "'goto'"),
```

In `parse_program`, before const/type/var sections, parse optional label section:

```rust
let labels = if *self.peek() == Tok::KwLabel {
    self.parse_label_section()?
} else {
    Vec::new()
};
```

Add to `Program` construction: `labels`.

Add parser method:

```rust
fn parse_label_section(&mut self) -> Result<Vec<i64>, ParseError> {
    self.expect(&Tok::KwLabel)?;
    let mut labels = Vec::new();
    labels.push(self.parse_int_literal()?);
    while *self.peek() == Tok::Comma {
        self.advance();
        labels.push(self.parse_int_literal()?);
    }
    self.expect(&Tok::Semi)?;
    Ok(labels)
}
```

In `parse_statement`, add goto:

```rust
Tok::KwGoto => {
    let span = self.span();
    self.advance();
    match self.peek().clone() {
        Tok::IntLit(n) => {
            self.advance();
            Ok(Statement::Goto { label: n, span })
        }
        _ => Err(ParseError {
            message: format!("expected label number after 'goto', found {}", self.peek()),
            span: self.span(),
        }),
    }
}
```

In `parse_statement`, detect label (a number followed by colon) — this must come before the default error case. Add at the beginning of `parse_statement`:

```rust
// Check for label: N: statement
if let Tok::IntLit(n) = self.peek().clone() {
    // Peek ahead for colon
    if self.tokens.get(self.pos + 1).map(|(t, _)| t == &Tok::Colon).unwrap_or(false) {
        let span = self.span();
        self.advance(); // consume number
        self.advance(); // consume colon
        return Ok(Statement::Label { label: n, span });
    }
}
```

- [ ] **Step 3: Add codegen**

In `CodeGen`, add a field:

```rust
label_blocks: HashMap<i64, inkwell::basic_block::BasicBlock<'ctx>>,
```

Initialize as `HashMap::new()`.

In `compile()`, after creating main's entry block, pre-create basic blocks for all declared labels:

```rust
for &label in &program.labels {
    let bb = self.context.append_basic_block(main_fn, &format!("label_{label}"));
    self.label_blocks.insert(label, bb);
}
```

For `Statement::Label`:

```rust
Statement::Label { label, span } => {
    self.set_debug_loc(*span);
    let bb = *self.label_blocks.get(label)
        .ok_or_else(|| CodeGenError::new(format!("undeclared label {label}"), Some(*span)))?;
    // Branch to the label block (ends current block)
    self.builder.build_unconditional_branch(bb)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
    // Continue emitting in the label block
    self.builder.position_at_end(bb);
    Ok(())
}
```

For `Statement::Goto`:

```rust
Statement::Goto { label, span } => {
    self.set_debug_loc(*span);
    let bb = *self.label_blocks.get(label)
        .ok_or_else(|| CodeGenError::new(format!("undeclared label {label}"), Some(*span)))?;
    self.builder.build_unconditional_branch(bb)
        .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
    // Create a dead block for any code after goto
    let func = self.current_fn.unwrap();
    let dead_bb = self.context.append_basic_block(func, "after_goto");
    self.builder.position_at_end(dead_bb);
    Ok(())
}
```

- [ ] **Step 4: Update `collect_stmt_lines`**

```rust
ast::Statement::Goto { span, .. }
| ast::Statement::Label { span, .. } => {
    lines.insert(span.line as usize);
}
```

- [ ] **Step 5: Update syntax highlighter**

Add `"label"` and `"goto"` to `is_keyword` in `pascal_syntax.rs`.

- [ ] **Step 6: Write test**

```rust
#[test]
fn goto_label() {
    let (ok, out) = build_and_run_source(
        "program T;\nlabel 10;\nvar i: integer;\nbegin\n  i := 0;\n  10: i := i + 1;\n  if i < 5 then\n    goto 10;\n  writeln(i)\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "5");
}
```

- [ ] **Step 7: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add goto/label"
```

---

### Task 6: With Statement

`with record_var do statement` — opens a record's fields as if they were local variables.

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`
- Modify: `bruto-pascal-lang/src/lib.rs`

- [ ] **Step 1: Add AST node**

In `ast.rs`, add to `Statement`:

```rust
With {
    record_var: String,
    body: Block,
    span: Span,
},
```

Update `Statement::span()`:

```rust
| Self::With { span, .. } => *span,
```

- [ ] **Step 2: Add parser**

Add token:

```rust
// In Tok enum:
KwWith,

// In keyword match:
"with" => Tok::KwWith,

// In Display:
Tok::KwWith => write!(f, "'with'"),
```

In `parse_statement`:

```rust
Tok::KwWith => self.parse_with(),
```

Add method:

```rust
fn parse_with(&mut self) -> Result<Statement, ParseError> {
    let span = self.span();
    self.expect(&Tok::KwWith)?;
    let (record_var, _) = self.expect_ident()?;
    self.expect(&Tok::Do)?;
    let body_stmt = self.parse_statement()?;
    let body = match body_stmt {
        Statement::Block(b) => b,
        other => { let s = other.span(); Block { span: s, end_span: s, statements: vec![other] } },
    };
    Ok(Statement::With { record_var, body, span })
}
```

- [ ] **Step 3: Add codegen**

The `with` statement temporarily adds the record's fields as variables that point to the appropriate GEP offsets.

```rust
Statement::With { record_var, body, span } => {
    self.compile_with(record_var, body, *span)
}
```

Add method:

```rust
fn compile_with(&mut self, record_var: &str, body: &Block, span: Span) -> Result<(), CodeGenError> {
    self.set_debug_loc(span);
    let alloca = *self.variables.get(record_var)
        .ok_or_else(|| CodeGenError::new(format!("undefined variable '{record_var}'"), Some(span)))?;
    let var_type = self.var_types.get(record_var).cloned()
        .ok_or_else(|| CodeGenError::new(format!("unknown type for '{record_var}'"), Some(span)))?;
    let resolved = self.resolve_type(&var_type);
    let fields = match &resolved {
        PascalType::Record { fields } => fields.clone(),
        _ => return Err(CodeGenError::new(format!("'{record_var}' is not a record"), Some(span))),
    };

    // Save any existing variables that would be shadowed
    let mut saved: Vec<(String, Option<PointerValue<'ctx>>, Option<PascalType>)> = Vec::new();
    for (i, (name, ty)) in fields.iter().enumerate() {
        let old_var = self.variables.remove(name);
        let old_type = self.var_types.remove(name);
        saved.push((name.clone(), old_var, old_type));

        let gep = self.builder.build_struct_gep(
            self.llvm_type_for(&resolved),
            alloca,
            i as u32,
            &format!("with_{name}"),
        ).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
        self.variables.insert(name.clone(), gep);
        self.var_types.insert(name.clone(), ty.clone());
    }

    self.compile_block(body)?;

    // Restore saved variables
    for (name, old_var, old_type) in saved {
        self.variables.remove(&name);
        self.var_types.remove(&name);
        if let Some(v) = old_var {
            self.variables.insert(name.clone(), v);
        }
        if let Some(t) = old_type {
            self.var_types.insert(name, t);
        }
    }

    Ok(())
}
```

- [ ] **Step 4: Update `collect_stmt_lines`**

```rust
ast::Statement::With { body, span, .. } => {
    lines.insert(span.line as usize);
    collect_block_lines(body, lines);
}
```

- [ ] **Step 5: Write test**

```rust
#[test]
fn with_statement() {
    let (ok, out) = build_and_run_source(
        "program T;\ntype\n  Point = record\n    x, y: integer;\n  end;\nvar p: Point;\nbegin\n  with p do\n  begin\n    x := 10;\n    y := 20\n  end;\n  writeln(p.x + p.y)\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "30");
}
```

- [ ] **Step 6: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add with statement"
```

---

### Task 7: Variant Records

Variant records have a discriminant field followed by variant parts: `record ... case tag: type of val: (fields); ... end`.

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`

- [ ] **Step 1: Add AST support**

In `ast.rs`, extend `PascalType::Record`:

```rust
Record {
    fields: Vec<(String, PascalType)>,
    /// Optional variant part: (tag_name, tag_type, variants)
    variant: Option<Box<RecordVariant>>,
},
```

Add new type:

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecordVariant {
    pub tag_name: String,
    pub tag_type: PascalType,
    pub variants: Vec<(Vec<i64>, Vec<(String, PascalType)>)>,  // (case_values, fields)
}
```

- [ ] **Step 2: Update parser for variant records**

In `parse_record_type`, after parsing fixed fields, check for `case`:

```rust
fn parse_record_type(&mut self) -> Result<PascalType, ParseError> {
    self.expect(&Tok::KwRecord)?;
    let mut fields = Vec::new();
    let mut variant = None;

    while *self.peek() != Tok::End {
        // Check for variant part
        if *self.peek() == Tok::KwCase {
            variant = Some(Box::new(self.parse_variant_part()?));
            break;
        }
        // Regular field
        let mut names = Vec::new();
        let (first, _) = self.expect_ident()?;
        names.push(first);
        while *self.peek() == Tok::Comma {
            self.advance();
            let (name, _) = self.expect_ident()?;
            names.push(name);
        }
        self.expect(&Tok::Colon)?;
        let ty = self.parse_type()?;
        for name in names {
            fields.push((name, ty.clone()));
        }
        if *self.peek() == Tok::Semi {
            self.advance();
        }
    }
    self.expect(&Tok::End)?;
    Ok(PascalType::Record { fields, variant })
}

fn parse_variant_part(&mut self) -> Result<RecordVariant, ParseError> {
    self.expect(&Tok::KwCase)?;
    let (tag_name, _) = self.expect_ident()?;
    self.expect(&Tok::Colon)?;
    let tag_type = self.parse_type()?;
    self.expect(&Tok::KwOf)?;

    let mut variants = Vec::new();
    while *self.peek() != Tok::End {
        // Parse case values: 1, 2:
        let mut values = Vec::new();
        values.push(self.parse_int_literal()?);
        while *self.peek() == Tok::Comma {
            self.advance();
            values.push(self.parse_int_literal()?);
        }
        self.expect(&Tok::Colon)?;
        self.expect(&Tok::LParen)?;

        let mut vfields = Vec::new();
        while *self.peek() != Tok::RParen {
            let mut names = Vec::new();
            let (first, _) = self.expect_ident()?;
            names.push(first);
            while *self.peek() == Tok::Comma {
                self.advance();
                let (name, _) = self.expect_ident()?;
                names.push(name);
            }
            self.expect(&Tok::Colon)?;
            let ty = self.parse_type()?;
            for name in names {
                vfields.push((name, ty.clone()));
            }
            if *self.peek() == Tok::Semi {
                self.advance();
            }
        }
        self.expect(&Tok::RParen)?;
        variants.push((values, vfields));
        if *self.peek() == Tok::Semi {
            self.advance();
        }
    }
    Ok(RecordVariant { tag_name, tag_type, variants })
}
```

- [ ] **Step 3: Add codegen for variant records**

Variant records are laid out as: fixed fields + tag field + union (largest variant). The union is represented as a byte array of the largest variant's size.

In `llvm_type_for` for `Record`, after the fixed fields, add the tag and union:

```rust
PascalType::Record { fields, variant } => {
    let mut field_types: Vec<inkwell::types::BasicTypeEnum> =
        fields.iter().map(|(_, t)| self.llvm_type_for(t)).collect();
    if let Some(ref v) = variant {
        // Tag field
        field_types.push(self.llvm_type_for(&v.tag_type));
        // Union: byte array of the max variant size
        let max_size = v.variants.iter()
            .map(|(_, vf)| vf.iter().map(|(_, t)| self.sizeof_type(t)).sum::<u64>())
            .max().unwrap_or(0);
        if max_size > 0 {
            field_types.push(self.context.i8_type().array_type(max_size as u32).as_basic_type_enum());
        }
    }
    self.context.struct_type(&field_types, false).as_basic_type_enum()
}
```

Update `sizeof_type` for Record with variant:

```rust
PascalType::Record { fields, variant } => {
    let fixed: u64 = fields.iter().map(|(_, t)| self.sizeof_type(t)).sum();
    let var_size = variant.as_ref().map(|v| {
        let tag_size = self.sizeof_type(&v.tag_type);
        let max_body = v.variants.iter()
            .map(|(_, vf)| vf.iter().map(|(_, t)| self.sizeof_type(t)).sum::<u64>())
            .max().unwrap_or(0);
        tag_size + max_body
    }).unwrap_or(0);
    fixed + var_size
}
```

For field access in the variant part, the tag field index is `fields.len()` and the union data starts at `fields.len() + 1`. Variant fields are accessed by casting the union byte array to the appropriate struct type. This is complex — for a first pass, accessing the tag works like a normal field, and variant fields can be accessed via their offset within the union.

For simplicity, compile variant field access as byte-offset GEP + bitcast. The `with` statement or explicit field assignment `r.variant_field := val` will need to know the variant layout.

This task focuses on the parsing and type representation. Field access for variant records can use existing `FieldAssignment` / `FieldAccess` by extending the field lookup to search variant fields too:

In `compile_statement` for `FieldAssignment`, and in `compile_expr` for `FieldAccess`, when the field is not found in the fixed fields, search the variant fields:

```rust
// Helper method:
fn find_field_in_record(&self, var_type: &PascalType, field: &str) -> Option<(u32, PascalType)> {
    match var_type {
        PascalType::Record { fields, variant } => {
            // Check fixed fields
            if let Some(idx) = fields.iter().position(|(n, _)| n == field) {
                return Some((idx as u32, fields[idx].1.clone()));
            }
            // Check tag
            if let Some(ref v) = variant {
                if v.tag_name == field {
                    return Some((fields.len() as u32, v.tag_type.clone()));
                }
                // Check variant fields (use offset within union)
                // For now, all variant fields are accessible from union start
                // This is how Turbo Pascal works — no bounds checking
                let union_idx = fields.len() + 1;
                for (_, vfields) in &v.variants {
                    let mut byte_offset = 0u64;
                    for (vn, vt) in vfields {
                        if vn == field {
                            // Return special index — we'll handle this in codegen
                            return Some((union_idx as u32, vt.clone()));
                        }
                        byte_offset += self.sizeof_type(vt);
                    }
                }
            }
            None
        }
        _ => None,
    }
}
```

- [ ] **Step 4: Write test**

```rust
#[test]
fn variant_record() {
    let (ok, out) = build_and_run_source(
        "program T;\ntype\n  Shape = record\n    kind: integer;\n    case tag: integer of\n      1: (radius: integer);\n      2: (width, height: integer);\n  end;\nvar s: Shape;\nbegin\n  s.kind := 1;\n  s.tag := 1;\n  s.radius := 10;\n  writeln(s.radius)\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "10");
}
```

- [ ] **Step 5: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add variant records"
```

---

### Task 8: Multi-Dimensional Array Indexing

Support `a[i, j]` syntax as equivalent to `a[i][j]` for multi-dimensional arrays: `array[1..3, 1..5] of integer`.

**Files:**
- Modify: `bruto-pascal-lang/src/ast.rs`
- Modify: `bruto-pascal-lang/src/parser.rs`
- Modify: `bruto-pascal-lang/src/codegen.rs`

- [ ] **Step 1: Update parser for multi-dimensional array types**

In `parse_array_type`, support multiple dimensions:

```rust
fn parse_array_type(&mut self) -> Result<PascalType, ParseError> {
    self.expect(&Tok::KwArray)?;
    self.expect(&Tok::LBracket)?;

    // Parse first dimension
    let mut dimensions = Vec::new();
    let lo = self.parse_int_literal()?;
    self.expect(&Tok::DotDot)?;
    let hi = self.parse_int_literal()?;
    dimensions.push((lo, hi));

    // Parse additional dimensions
    while *self.peek() == Tok::Comma {
        self.advance();
        let lo = self.parse_int_literal()?;
        self.expect(&Tok::DotDot)?;
        let hi = self.parse_int_literal()?;
        dimensions.push((lo, hi));
    }
    self.expect(&Tok::RBracket)?;
    self.expect(&Tok::KwOf)?;
    let elem = self.parse_type()?;

    // Build nested array types from innermost to outermost
    let mut result = elem;
    for (lo, hi) in dimensions.into_iter().rev() {
        result = PascalType::Array { lo, hi, elem: Box::new(result) };
    }
    Ok(result)
}
```

- [ ] **Step 2: Update parser for multi-dimensional indexing**

In `parse_ident_statement`, for `Tok::LBracket`:

```rust
Tok::LBracket => {
    // a[i] or a[i, j] := expr
    self.advance();
    let mut indices = Vec::new();
    indices.push(self.parse_expr()?);
    while *self.peek() == Tok::Comma {
        self.advance();
        indices.push(self.parse_expr()?);
    }
    self.expect(&Tok::RBracket)?;
    self.expect(&Tok::Assign)?;
    let expr = self.parse_expr()?;
    // For multi-dimensional, nest IndexAssignment
    // a[i, j] := expr  becomes a[i][j] := expr internally
    // We represent this as nested statements
    if indices.len() == 1 {
        Ok(Statement::IndexAssignment { target: name, index: indices.into_iter().next().unwrap(), expr, span })
    } else {
        // For multi-dimensional, we need a new AST variant or flatten
        // Simplest: add a MultiIndexAssignment
        Ok(Statement::MultiIndexAssignment { target: name, indices, expr, span })
    }
}
```

Add to `Statement`:

```rust
/// Multi-dimensional array index assignment: a[i, j] := expr
MultiIndexAssignment {
    target: String,
    indices: Vec<Expr>,
    expr: Expr,
    span: Span,
},
```

Update `Statement::span()`:

```rust
| Self::MultiIndexAssignment { span, .. } => *span,
```

In `parse_primary`, for the postfix `[` after an identifier, support multi-index:

```rust
Tok::LBracket => {
    self.advance();
    let index = self.parse_expr()?;
    if *self.peek() == Tok::Comma {
        // Multi-dimensional: a[i, j] — chain Index nodes
        let mut expr_so_far = Expr::Index { array: Box::new(expr), index: Box::new(index), span };
        while *self.peek() == Tok::Comma {
            self.advance();
            let next_index = self.parse_expr()?;
            expr_so_far = Expr::Index { array: Box::new(expr_so_far), index: Box::new(next_index), span };
        }
        self.expect(&Tok::RBracket)?;
        expr = expr_so_far;
    } else {
        self.expect(&Tok::RBracket)?;
        expr = Expr::Index { array: Box::new(expr), index: Box::new(index), span };
    }
}
```

- [ ] **Step 3: Add codegen for MultiIndexAssignment**

```rust
Statement::MultiIndexAssignment { target, indices, expr, span } => {
    self.set_debug_loc(*span);
    let val = self.compile_expr(expr)?;
    let alloca = *self.variables.get(target.as_str())
        .ok_or_else(|| CodeGenError::new(format!("undefined variable '{target}'"), Some(*span)))?;
    let var_type = self.var_types.get(target.as_str()).cloned()
        .ok_or_else(|| CodeGenError::new(format!("unknown type for '{target}'"), Some(*span)))?;

    // Walk through dimensions
    let mut current_ptr = alloca;
    let mut current_type = var_type;
    for (dim, index_expr) in indices.iter().enumerate() {
        let idx_val = self.compile_expr(index_expr)?;
        let (lo, elem_ty) = match &current_type {
            PascalType::Array { lo, elem, .. } => (*lo, elem.as_ref().clone()),
            _ => return Err(CodeGenError::new(format!("too many indices for '{target}'"), Some(*span))),
        };
        let adj = self.builder.build_int_sub(
            idx_val.into_int_value(),
            self.context.i64_type().const_int(lo as u64, true),
            "adj_idx",
        ).map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
        let gep = unsafe {
            self.builder.build_in_bounds_gep(
                self.llvm_type_for(&current_type),
                current_ptr,
                &[self.context.i64_type().const_int(0, false), adj],
                "multi_gep",
            ).map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?
        };

        if dim == indices.len() - 1 {
            // Last dimension — store the value
            self.builder.build_store(gep, val)
                .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
        } else {
            current_ptr = gep;
            current_type = elem_ty;
        }
    }
    Ok(())
}
```

For reading multi-dimensional arrays, the chained `Expr::Index` nodes already work because the existing `Index` codegen handles nested arrays. But currently `Index` only works on `Expr::Var` — it needs to work on any array expression. Update `compile_expr` for `Expr::Index` to handle nested Index (where the inner is also an Index rather than just a Var):

The current code requires `array` to be `Expr::Var`. For multi-dimensional access (`a[i][j]` represented as `Index(Index(Var(a), i), j)`), the inner `Index(Var(a), i)` returns a value (the sub-array), but we actually need a pointer (to GEP into). The simplest fix: when the inner is an `Index`, emit a GEP that returns a pointer rather than loading.

This is complex. A simpler approach for multi-dimensional reads: add an `Expr::MultiIndex` variant similar to the statement version, and handle it in codegen. But the chained `Index` approach from Step 2 above is cleaner. Let's update `Expr::Index` codegen to handle nested arrays by GEP-chaining:

```rust
Expr::Index { array, index, span } => {
    let (base_ptr, base_type) = self.resolve_array_base(array, *span)?;
    let idx_val = self.compile_expr(index)?;
    let lo = match &base_type {
        PascalType::Array { lo, .. } => *lo,
        _ => return Err(CodeGenError::new("indexing non-array", Some(*span))),
    };
    let elem_ty = match &base_type {
        PascalType::Array { elem, .. } => elem.as_ref().clone(),
        _ => unreachable!(),
    };
    let adj = self.builder.build_int_sub(
        idx_val.into_int_value(),
        self.context.i64_type().const_int(lo as u64, true),
        "adj_idx",
    ).map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
    let gep = unsafe {
        self.builder.build_in_bounds_gep(
            self.llvm_type_for(&base_type),
            base_ptr,
            &[self.context.i64_type().const_int(0, false), adj],
            "arr_gep",
        ).map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?
    };
    let elem_llvm_ty = self.llvm_type_for(&elem_ty);
    let val = self.builder.build_load(elem_llvm_ty, gep, "arr_load")
        .map_err(|e| CodeGenError::new(e.to_string(), Some(*span)))?;
    Ok(val)
}
```

Add helper:

```rust
/// Resolve the base pointer and type for array indexing (handles nested Index for multi-dim).
fn resolve_array_base(&mut self, expr: &Expr, span: Span) -> Result<(PointerValue<'ctx>, PascalType), CodeGenError> {
    match expr {
        Expr::Var(name, vspan) => {
            let a = *self.variables.get(name.as_str())
                .ok_or_else(|| CodeGenError::new(format!("undefined variable '{name}'"), Some(*vspan)))?;
            let t = self.var_types.get(name.as_str()).cloned()
                .ok_or_else(|| CodeGenError::new(format!("unknown type for '{name}'"), Some(*vspan)))?;
            Ok((a, t))
        }
        Expr::Index { array, index, span: idx_span } => {
            let (base_ptr, base_type) = self.resolve_array_base(array, *idx_span)?;
            let idx_val = self.compile_expr(index)?;
            let lo = match &base_type {
                PascalType::Array { lo, .. } => *lo,
                _ => return Err(CodeGenError::new("indexing non-array", Some(span))),
            };
            let elem_ty = match &base_type {
                PascalType::Array { elem, .. } => elem.as_ref().clone(),
                _ => unreachable!(),
            };
            let adj = self.builder.build_int_sub(
                idx_val.into_int_value(),
                self.context.i64_type().const_int(lo as u64, true),
                "adj_idx",
            ).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
            let gep = unsafe {
                self.builder.build_in_bounds_gep(
                    self.llvm_type_for(&base_type),
                    base_ptr,
                    &[self.context.i64_type().const_int(0, false), adj],
                    "arr_gep",
                ).map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?
            };
            Ok((gep, elem_ty))
        }
        _ => Err(CodeGenError::new("array indexing requires a variable", Some(span))),
    }
}
```

- [ ] **Step 4: Update `collect_stmt_lines`**

```rust
ast::Statement::MultiIndexAssignment { span, .. } => {
    lines.insert(span.line as usize);
}
```

- [ ] **Step 5: Write test**

```rust
#[test]
fn multi_dim_array() {
    let (ok, out) = build_and_run_source(
        "program T;\nvar\n  m: array[1..2, 1..3] of integer;\nbegin\n  m[1, 2] := 42;\n  writeln(m[1, 2])\nend.\n",
    );
    assert!(ok);
    assert_eq!(out.trim(), "42");
}
```

- [ ] **Step 6: Run tests, commit**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
git add -A && git commit -m "feat: add multi-dimensional array indexing"
```

---

### Task 9: Final Integration Test and Sample Program Update

Update the sample program to demonstrate all new features.

**Files:**
- Modify: `bruto-pascal-lang/src/lib.rs`

- [ ] **Step 1: Add integration tests for all new features together**

```rust
#[test]
fn all_new_features() {
    let source = r#"program NewFeatures;
type
  Color = (Red, Green, Blue);
  SmallInt = 1..10;

var
  c: Color;
  n: SmallInt;
  s: set of integer;
  ok: boolean;

begin
  { Enumerated types }
  c := Blue;
  writeln('Blue = ', c);

  { Subrange }
  n := 7;
  writeln('n = ', n);

  { Sets }
  s := [1, 3, 5..9];
  ok := 5 in s;
  writeln('5 in set: ', ok);
  ok := 4 in s;
  writeln('4 in set: ', ok);

  { Case }
  case c of
    0: writeln('Red');
    1: writeln('Green');
    2: writeln('Blue')
  end
end.
"#;
    let (ok, out) = build_and_run_source(source);
    assert!(ok, "new features program failed");
    assert!(out.contains("Blue = 2"), "enum failed: {out}");
    assert!(out.contains("n = 7"), "subrange failed: {out}");
    assert!(out.contains("5 in set: true"), "set-in failed: {out}");
    assert!(out.contains("4 in set: false"), "set-not-in failed: {out}");
    assert!(out.contains("Blue"), "case failed: {out}");
}
```

- [ ] **Step 2: Run full test suite**

```bash
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "test: add integration tests for all batch 2 features"
```
