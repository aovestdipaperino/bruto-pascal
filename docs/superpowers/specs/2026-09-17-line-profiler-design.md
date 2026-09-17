# Line profiler for the Bruto IDE

Date: 2026-09-17. Status: approved design.

## Goal

Let the user profile a Pascal program from the IDE and see where time goes,
down to individual source lines, in the spirit of Borland's Turbo Profiler and
of the `line-profiler` project for Rust. Results appear both inline in the
editor (a per-line time column with heat tinting) and in a separate Profile
window (a call tree of procedures and lines).

## Non-goals

- Profiling under the debugger. Profile runs execute to completion outside
  lldb.
- Sampling. This is an instrumented, deterministic profiler.
- Cross-file attribution beyond what the `uses` resolver already gives
  codegen: units compiled into the same module are instrumented, but the
  inline column is shown only for the editor whose file produced the line.
- Persisting profiles across IDE sessions.

## Approach

Bruto owns its LLVM IR through inkwell and already stamps a debug location on
every statement, so instrumentation happens at codegen time. No IR rewriting
and no compiler wrapper, unlike `line-profiler`.

Three hooks, all `extern "C"`:

| Hook | Inserted at | Arguments |
|---|---|---|
| `__bruto_prof_enter(u32 loc)` | first instruction of every procedure, function and the main block | id of the routine |
| `__bruto_prof_exit()` | before every `ret` (including the implicit one and `Exit`/`goto` out) | none |
| `__bruto_prof_line(u32 loc)` | at the point where `set_debug_loc` is called for a statement | id of the statement |

Location ids are `u32`, assigned sequentially by codegen as statements and
routines are compiled. The id table (id, kind, line, column, routine name) is
written next to the executable as `<exe>.bruto-prof-map`, one entry per line
in the form `P <id> <line> <name>` or `L <id> <line> <col>`.

The main program block is treated as a routine named `program`. Nested
procedures are routines in their own right.

### Runtime

A C source file of roughly 200 lines embedded as a string constant in
`bruto-pascal-lang` (`src/prof_runtime.c` included with `include_str!`). On a
profile build it is written to the temp dir and compiled with the same `cc`
the linker step uses, producing an object that is linked only into profile
builds. Normal builds never reference the hooks and pay nothing.

The runtime keeps a call tree in a fixed open-addressing hash table:

- Node key: `(parent_node_index, loc_id)`. Root has index `u32::MAX`.
- Node value: `kind`, `loc_id`, `parent`, `calls`, `self_ns`, `total_ns`.
- Capacity 65 536 nodes. When full, further new nodes are dropped and a flag
  is set in the file header so the IDE can warn.
- A fixed stack of 4 096 frames; each frame records the node index, the entry
  timestamp, and the timestamp of the last `line` hook so the previous line
  gets its self time when the next line begins. Deeper recursion stops
  recording (a flag is set) rather than overflowing.

Time source: `clock_gettime(CLOCK_MONOTONIC)` on Unix,
`QueryPerformanceCounter` on Windows, converted to nanoseconds.

Attribution rules match `line-profiler`: a line's self time runs from its hook
to the next hook in the same frame, minus time spent in routines entered in
between; a routine's total time runs from enter to exit and its self time is
total minus children totals. Loop headers are hooked once per statement, not
per iteration, so iteration overhead is charged to the last body statement.

An `atexit` handler writes the file. The program writes `<exe>.bruto-prof` by
default (the path is baked in by codegen via `__bruto_prof_set_output`, called
right after the program's enter hook); `BRUTO_PROF_OUT` overrides it at
runtime. Codegen already installs `atexit` style teardown for the console
capture, so the same path is used.

### Profile file

`<exe>.bruto-prof`, little-endian binary:

```
Header (24 bytes)
  magic     "BPRF"     4
  version   u32        4   (1)
  flags     u32        4   bit0 = table full, bit1 = stack overflow
  elapsed   u64        8   nanoseconds, program start to exit
  count     u32        4
Node (33 bytes) × count
  kind      u8             1 = routine, 2 = line
  loc_id    u32
  parent    u32            index into this array, u32::MAX for root children
  calls     u64
  self_ns   u64
  total_ns  u64
```

### Language-agnostic model (`bruto-lang`)

`bruto-lang/src/profile.rs`:

```rust
pub struct Profile {
    pub elapsed_ns: u64,
    pub truncated: bool,
    pub nodes: Vec<ProfileNode>,
}
pub struct ProfileNode {
    pub kind: ProfileKind,            // Routine | Line
    pub name: String,                 // routine name, empty for lines
    pub line: usize,                  // 1-based source line
    pub parent: Option<usize>,        // index into nodes
    pub calls: u64,
    pub self_ns: u64,
    pub total_ns: u64,
}
```

`Profile::line_totals() -> HashMap<usize, (u64 self_ns, u64 hits)>`
aggregates line nodes across all callers; this is what the inline column
shows.

`Language` gains:

```rust
fn profile_job_at(&self, source: &str, source_path: Option<&Path>) -> Box<dyn BuildJob>;
fn load_profile(&self, result: &BuildResult) -> Result<Profile, String>;
```

`BuildResult` gains `profile_path: Option<String>` and
`profile_map_path: Option<String>`, both `Some` only for profile builds.

### Pascal crate

- `CodeGen` gets `instrument: bool` and a `ProfMap` collector. `set_debug_loc`
  for statements gains a sibling `emit_prof_line(span)` called from
  `compile_statement`; `compile_proc_decl` and the main block wrap the body
  with enter/exit. Every `ret` path goes through one helper so `exit` is not
  missed.
- `PascalBuildJob` gains a `Profile` variant of its state machine: after the
  object is emitted it compiles the runtime C file (`cc -c`), then links both
  objects. Cancel kills whichever child is live, as today.
- The temp paths use a `bruto_pascal_prof` stem so a profile build never
  clobbers the normal build's executable.
- `load_profile` reads the binary file and the map file into a `Profile`.

### IDE (`bruto-ide`)

Commands (all in the application range, from 450):

| Command | Menu | Key |
|---|---|---|
| `CM_PROFILE` | Build > Profile | Shift-F9 |
| `CM_SHOW_PROFILE` | Windows > Profile | |
| `CM_TOGGLE_PROFILE_COLUMN` | Windows > Profile Column | |

`CM_PROFILE` runs the profile build in the existing progress dialog, runs the
executable exactly as `Run` does (output in the Output panel), then calls
`load_profile`, stores the `Profile` in `IdeState`, pushes `line_totals()`
into the focused editor, and opens the Profile window. A truncated profile
prints a yellow warning line in the Output panel.

Inline column (`IdeEditorWindow`):

- New field `line_profile: Option<LineProfile>` where `LineProfile` holds
  the per-line map, the run's total nanoseconds, and a `visible` flag.
- When `Some` and visible, a 7-character column sits between the gutter and
  the editor showing the line's share of total time as `12.4% ` (blank when
  the line has no hits, `<0.1% ` below that). The editor child is narrowed by
  the column width in `sync_interior_layout`, exactly as the gutter does.
- Row tinting is a background overlay painted after `window_draw`, like the
  exec-line overlay, on three heat buckets by share of total: 1 to 5 percent
  dark red, 5 to 20 percent red, above 20 percent bright red with white
  text. The exec-line and error-line overlays paint over it.
- The column is hidden until a profile run completes, and cleared (set to
  `None`) on the next Build, Run, Profile, or when the buffer is modified.
- `Windows > Profile Column` toggles `visible`; the entry is enabled only
  when data exists.

Profile window (`profile_window.rs`, `ProfilePanel`):

- Pattern: `CallStackPanel`. Gray window, owner-relative drawing, one row
  per visible tree node.
- Rows: `▸`/`▾` for collapsible routines, indent by depth, then
  `name or line N`, percent of total, total, self, calls. Sorted by total
  descending within each parent.
- Keys: Up/Down move, Right/Left or Enter expand/collapse, Space or
  double-click jumps the editor to the line (routine rows jump to the
  routine header line). Selection is drawn with the green highlight the call
  stack uses.
- Jumps are delivered the same way the call stack panel delivers them: a
  `pending_jump: Option<usize>` drained by the IDE loop.

### Error handling

- Missing `cc`: the profile build fails with the linker's message, as today.
- Runtime compile failure: `BuildPhase::Failed("profiler runtime: …")`.
- Program crashes before `atexit`: no profile file; the IDE reports
  "Program exited with code N; no profile written" in the Output panel.
- Corrupt or truncated file: `load_profile` returns an error shown in a
  message box; no partial data is displayed.

### Testing

- `bruto-pascal-lang`: `profile_build_and_run` builds a program with a hot
  loop calling a procedure, runs it, loads the profile, and asserts: the
  hottest line is the loop body, the procedure node has the expected call
  count, `elapsed_ns > 0`, `truncated == false`. Uses the unique
  `bruto_pascal_prof` stem so it does not collide with the existing tests.
- `bruto-lang`: unit tests for `Profile::line_totals` aggregation and the
  binary reader on a hand-built byte vector, including the truncated flag.
- `bruto-ide`: unit tests for the heat-bucket function and for the tree
  flattening that turns `Profile` into visible rows given a set of collapsed
  nodes.
- Manual: run the IDE, `Build > Profile` on `demo.pas`, confirm the column,
  the tinting, the Profile window, and that Build clears the column.

## Out of scope for this iteration

- Per-unit profile columns for files other than the main program.
- Exporting the profile (CSV, Mermaid) from the IDE.
- Profiling with optimization enabled.
