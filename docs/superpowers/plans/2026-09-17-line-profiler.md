# Line Profiler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Build > Profile` to the Bruto IDE: an instrumented build and run that reports per-line and per-routine time, shown as a heat column in the editor and as a call tree in a Profile window.

**Architecture:** Pascal codegen (inkwell) inserts `__bruto_prof_enter/exit/line` calls when instrumentation is on and writes an id map next to the executable. A small C runtime, embedded as a string in `bruto-pascal-lang`, is compiled with `cc` and linked only into profile builds; it keeps a call tree and writes `<exe>.bruto-prof` at exit. `bruto-lang` owns the language-agnostic `Profile` model and the binary reader. `bruto-ide` adds the command, a heat column overlay on `IdeEditorWindow`, and a `ProfilePanel` window.

**Tech Stack:** Rust 2024, inkwell 0.8 (LLVM 18), turbo-vision 3.0, C11 runtime compiled by the system `cc`.

## Global Constraints

- Build/test always with `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18` in the environment.
- `bruto-pascal-lang` tests must run with `--test-threads=1` (the build writes fixed temp paths).
- The pre-commit hook runs workspace clippy and fails on pre-existing debt; commit with `--no-verify` after running `rustfmt --edition 2024` on touched files and `cargo clippy` on the touched crate to make sure no NEW warnings are added.
- Application command ids start at 450 for this feature (library reserves 0–199; existing IDE commands use 400–443).
- Profile temp files use the stem `bruto_pascal_prof` so they never collide with the normal build's `bruto_pascal_out`.
- Spec: `docs/superpowers/specs/2026-09-17-line-profiler-design.md`.
- Each crate is its own git repository (submodules): commit inside `bruto-lang/`, `bruto-pascal-lang/`, `bruto-ide/` respectively, then commit the parent to advance pointers. Every commit message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## File structure

| File | Responsibility |
|---|---|
| `bruto-lang/src/profile.rs` (new) | `Profile`, `ProfileNode`, `ProfileKind`; `Profile::from_bytes`, `Profile::read_map`, `Profile::load`, `line_totals` |
| `bruto-lang/src/language.rs` | `BuildResult` gains `profile_path`/`profile_map_path`; `Language` gains `profile_job_at`, `load_profile` |
| `bruto-pascal-lang/src/prof_runtime.c` (new) | C runtime: hooks, call-tree table, file writer |
| `bruto-pascal-lang/src/prof_runtime.rs` (new) | `write_runtime_source`, `spawn_runtime_compile` |
| `bruto-pascal-lang/src/codegen.rs` | `instrument` flag, id allocation, hook emission, `write_prof_map`, `spawn_linker_objs` |
| `bruto-pascal-lang/src/lib.rs` | `PascalBuildJob` profile mode, `Language::profile_job_at`/`load_profile` |
| `bruto-ide/src/commands.rs` | `CM_PROFILE`, `CM_SHOW_PROFILE`, `CM_TOGGLE_PROFILE_COLUMN` |
| `bruto-ide/src/heat.rs` (new) | `LineProfile`, `heat_bucket`, `format_share` |
| `bruto-ide/src/ide_editor.rs` | profile column overlay, editor narrowing, clear-on-edit |
| `bruto-ide/src/profile_window.rs` (new) | `ProfilePanel` tree view, `flatten_tree` |
| `bruto-ide/src/ide.rs` | menu/status wiring, `handle_profile`, window install, jump |
| `CHANGELOG.md` | Unreleased entry |

---

### Task 1: Profile model and binary reader in `bruto-lang`

**Files:**
- Create: `bruto-lang/src/profile.rs`
- Modify: `bruto-lang/src/lib.rs`
- Modify: `bruto-lang/src/language.rs`

**Interfaces:**
- Produces:
  ```rust
  pub enum ProfileKind { Routine, Line }
  pub struct ProfileNode { pub kind: ProfileKind, pub name: String, pub line: usize, pub parent: Option<usize>, pub calls: u64, pub self_ns: u64, pub total_ns: u64 }
  pub struct Profile { pub elapsed_ns: u64, pub truncated: bool, pub nodes: Vec<ProfileNode> }
  impl Profile {
      pub fn from_bytes(bytes: &[u8], map: &ProfMap) -> Result<Profile, String>;
      pub fn read_map(text: &str) -> Result<ProfMap, String>;
      pub fn load(profile_path: &str, map_path: &str) -> Result<Profile, String>;
      pub fn line_totals(&self) -> HashMap<usize, (u64, u64)>; // line -> (self_ns, hits)
  }
  pub struct ProfMap { pub entries: HashMap<u32, MapEntry> }
  pub struct MapEntry { pub kind: ProfileKind, pub line: usize, pub name: String }
  // language.rs
  pub struct BuildResult { ..existing.., pub profile_path: Option<String>, pub profile_map_path: Option<String> }
  trait Language { fn profile_job_at(&self, source: &str, source_path: Option<&Path>) -> Box<dyn BuildJob>; fn load_profile(&self, result: &BuildResult) -> Result<Profile, String>; }
  ```

- [ ] **Step 1: Write the failing tests**

Create `bruto-lang/src/profile.rs` with only the test module first:

```rust
//! Language-agnostic profiling results, produced by an instrumented run
//! and consumed by the IDE. See docs/superpowers/specs/2026-09-17-line-profiler-design.md.

#[cfg(test)]
mod tests {
    use super::*;

    fn le_u32(v: &mut Vec<u8>, x: u32) { v.extend_from_slice(&x.to_le_bytes()); }
    fn le_u64(v: &mut Vec<u8>, x: u64) { v.extend_from_slice(&x.to_le_bytes()); }

    fn node(v: &mut Vec<u8>, kind: u8, loc: u32, parent: u32, calls: u64, self_ns: u64, total_ns: u64) {
        v.push(kind);
        le_u32(v, loc);
        le_u32(v, parent);
        le_u64(v, calls);
        le_u64(v, self_ns);
        le_u64(v, total_ns);
    }

    fn sample_map() -> ProfMap {
        Profile::read_map("P 1 3 program\nL 2 5 3\nL 3 7 5\nP 4 10 Double\nL 5 12 3\n").unwrap()
    }

    fn sample_bytes(flags: u32) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(b"BPRF");
        le_u32(&mut v, 1);
        le_u32(&mut v, flags);
        le_u64(&mut v, 1_000);
        le_u32(&mut v, 4);
        node(&mut v, 1, 1, u32::MAX, 1, 100, 1_000); // program
        node(&mut v, 2, 2, 0, 5, 300, 300);          // line 5 under program
        node(&mut v, 1, 4, 0, 5, 500, 600);          // Double under program
        node(&mut v, 2, 5, 2, 5, 600, 600);          // line 12 under Double
        v
    }

    #[test]
    fn parses_header_and_nodes() {
        let p = Profile::from_bytes(&sample_bytes(0), &sample_map()).unwrap();
        assert_eq!(p.elapsed_ns, 1_000);
        assert!(!p.truncated);
        assert_eq!(p.nodes.len(), 4);
        assert_eq!(p.nodes[0].kind, ProfileKind::Routine);
        assert_eq!(p.nodes[0].name, "program");
        assert_eq!(p.nodes[0].line, 3);
        assert_eq!(p.nodes[0].parent, None);
        assert_eq!(p.nodes[1].kind, ProfileKind::Line);
        assert_eq!(p.nodes[1].line, 5);
        assert_eq!(p.nodes[1].parent, Some(0));
        assert_eq!(p.nodes[3].parent, Some(2));
        assert_eq!(p.nodes[2].calls, 5);
    }

    #[test]
    fn truncated_flags_are_reported() {
        assert!(Profile::from_bytes(&sample_bytes(1), &sample_map()).unwrap().truncated);
        assert!(Profile::from_bytes(&sample_bytes(2), &sample_map()).unwrap().truncated);
    }

    #[test]
    fn rejects_bad_magic_and_short_data() {
        let mut bad = sample_bytes(0);
        bad[0] = b'X';
        assert!(Profile::from_bytes(&bad, &sample_map()).is_err());
        let short = &sample_bytes(0)[..30];
        assert!(Profile::from_bytes(short, &sample_map()).is_err());
    }

    #[test]
    fn unknown_location_id_is_an_error() {
        let map = Profile::read_map("P 1 3 program\n").unwrap();
        assert!(Profile::from_bytes(&sample_bytes(0), &map).is_err());
    }

    #[test]
    fn line_totals_aggregate_across_callers() {
        let p = Profile::from_bytes(&sample_bytes(0), &sample_map()).unwrap();
        let t = p.line_totals();
        assert_eq!(t.get(&5), Some(&(300, 5)));
        assert_eq!(t.get(&12), Some(&(600, 5)));
        assert_eq!(t.get(&3), None, "routine rows are not lines");
    }

    #[test]
    fn map_parser_skips_blank_and_rejects_garbage() {
        let m = Profile::read_map("\nL 7 9 1\n\n").unwrap();
        assert_eq!(m.entries[&7].line, 9);
        assert!(Profile::read_map("Q 1 2 3\n").is_err());
        assert!(Profile::read_map("L x 2 3\n").is_err());
    }
}
```

Add `pub mod profile;` to `bruto-lang/src/lib.rs`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/enzo/Code/bruto-pascal && LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-lang 2>&1 | grep -E "^error" | head -3`
Expected: compile errors, `cannot find type Profile`.

- [ ] **Step 3: Implement the model and reader**

Insert above the test module in `bruto-lang/src/profile.rs`:

```rust
use std::collections::HashMap;

/// Magic bytes at the start of a `.bruto-prof` file.
pub const MAGIC: &[u8; 4] = b"BPRF";
/// File format version this reader understands.
pub const VERSION: u32 = 1;
const HEADER_LEN: usize = 24;
const NODE_LEN: usize = 33;
const FLAG_TABLE_FULL: u32 = 1;
const FLAG_STACK_OVERFLOW: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProfileKind {
    Routine,
    Line,
}

/// One node of the call tree: a routine invocation context or a source
/// line executed within one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProfileNode {
    pub kind: ProfileKind,
    /// Routine name; empty for lines.
    pub name: String,
    /// 1-based source line (the header line for routines).
    pub line: usize,
    /// Index into `Profile::nodes`; `None` for the root's children.
    pub parent: Option<usize>,
    pub calls: u64,
    pub self_ns: u64,
    pub total_ns: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Profile {
    /// Wall-clock nanoseconds from the first hook to exit.
    pub elapsed_ns: u64,
    /// True when the runtime dropped data (node table full or stack too deep).
    pub truncated: bool,
    pub nodes: Vec<ProfileNode>,
}

/// One entry of the id map written by codegen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MapEntry {
    pub kind: ProfileKind,
    pub line: usize,
    pub name: String,
}

/// Location id -> source position, from `<exe>.bruto-prof-map`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ProfMap {
    pub entries: HashMap<u32, MapEntry>,
}

fn u32_at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}

fn u64_at(b: &[u8], at: usize) -> u64 {
    let mut a = [0u8; 8];
    a.copy_from_slice(&b[at..at + 8]);
    u64::from_le_bytes(a)
}

impl Profile {
    /// Parse the map file: lines `P <id> <line> <name>` for routines and
    /// `L <id> <line> <col>` for statements. Blank lines are ignored.
    pub fn read_map(text: &str) -> Result<ProfMap, String> {
        let mut map = ProfMap::default();
        for (n, raw) in text.lines().enumerate() {
            let line = raw.trim();
            if line.is_empty() {
                continue;
            }
            let mut parts = line.splitn(4, ' ');
            let kind = parts.next().unwrap_or("");
            let id: u32 = parts
                .next()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| format!("prof map line {}: bad id", n + 1))?;
            let src_line: usize = parts
                .next()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| format!("prof map line {}: bad line number", n + 1))?;
            let rest = parts.next().unwrap_or("");
            let entry = match kind {
                "P" => MapEntry { kind: ProfileKind::Routine, line: src_line, name: rest.to_string() },
                "L" => MapEntry { kind: ProfileKind::Line, line: src_line, name: String::new() },
                other => return Err(format!("prof map line {}: unknown kind {other:?}", n + 1)),
            };
            map.entries.insert(id, entry);
        }
        Ok(map)
    }

    /// Decode a `.bruto-prof` file body, resolving ids through `map`.
    pub fn from_bytes(bytes: &[u8], map: &ProfMap) -> Result<Profile, String> {
        if bytes.len() < HEADER_LEN {
            return Err("profile file too short".into());
        }
        if &bytes[0..4] != MAGIC {
            return Err("profile file: bad magic".into());
        }
        let version = u32_at(bytes, 4);
        if version != VERSION {
            return Err(format!("profile file: unsupported version {version}"));
        }
        let flags = u32_at(bytes, 8);
        let elapsed_ns = u64_at(bytes, 12);
        let count = u32_at(bytes, 20) as usize;
        let need = HEADER_LEN + count * NODE_LEN;
        if bytes.len() < need {
            return Err(format!("profile file: expected {need} bytes, got {}", bytes.len()));
        }
        let mut nodes = Vec::with_capacity(count);
        for i in 0..count {
            let at = HEADER_LEN + i * NODE_LEN;
            let kind_byte = bytes[at];
            let loc = u32_at(bytes, at + 1);
            let parent_raw = u32_at(bytes, at + 5);
            let calls = u64_at(bytes, at + 9);
            let self_ns = u64_at(bytes, at + 17);
            let total_ns = u64_at(bytes, at + 25);
            let entry = map
                .entries
                .get(&loc)
                .ok_or_else(|| format!("profile file: unknown location id {loc}"))?;
            let kind = match kind_byte {
                1 => ProfileKind::Routine,
                2 => ProfileKind::Line,
                k => return Err(format!("profile file: bad node kind {k}")),
            };
            let parent = if parent_raw == u32::MAX {
                None
            } else if (parent_raw as usize) < count {
                Some(parent_raw as usize)
            } else {
                return Err(format!("profile file: parent {parent_raw} out of range"));
            };
            nodes.push(ProfileNode {
                kind,
                name: entry.name.clone(),
                line: entry.line,
                parent,
                calls,
                self_ns,
                total_ns,
            });
        }
        Ok(Profile {
            elapsed_ns,
            truncated: flags & (FLAG_TABLE_FULL | FLAG_STACK_OVERFLOW) != 0,
            nodes,
        })
    }

    /// Read both files from disk.
    pub fn load(profile_path: &str, map_path: &str) -> Result<Profile, String> {
        let map_text = std::fs::read_to_string(map_path)
            .map_err(|e| format!("reading {map_path}: {e}"))?;
        let map = Self::read_map(&map_text)?;
        let bytes = std::fs::read(profile_path).map_err(|e| format!("reading {profile_path}: {e}"))?;
        Self::from_bytes(&bytes, &map)
    }

    /// Per-line `(self_ns, hits)` summed over every calling context.
    /// This is what the editor's heat column shows.
    pub fn line_totals(&self) -> HashMap<usize, (u64, u64)> {
        let mut out: HashMap<usize, (u64, u64)> = HashMap::new();
        for n in &self.nodes {
            if n.kind == ProfileKind::Line {
                let e = out.entry(n.line).or_insert((0, 0));
                e.0 += n.self_ns;
                e.1 += n.calls;
            }
        }
        out
    }
}
```

- [ ] **Step 4: Extend `BuildResult` and `Language`**

In `bruto-lang/src/language.rs`, change `BuildResult` to:

```rust
pub struct BuildResult {
    /// Path to the compiled executable.
    pub exe_path: String,
    /// Path to the source file on disk (needed for DWARF debug info resolution).
    pub source_path: String,
    /// Path to the console output capture file (program writes here via compiled-in code).
    pub console_capture_path: String,
    /// `<exe>.bruto-prof`, written by the program at exit. `Some` only for
    /// profile builds.
    pub profile_path: Option<String>,
    /// `<exe>.bruto-prof-map`, written by codegen. `Some` only for profile builds.
    pub profile_map_path: Option<String>,
}
```

Add to the `Language` trait, after `build_job_at`:

```rust
    /// Like [`build_job_at`] but with profiling instrumentation compiled
    /// in. The resulting [`BuildResult`] carries `profile_path` and
    /// `profile_map_path`. Default: a job that fails immediately, for
    /// languages without a profiler.
    fn profile_job_at(
        &self,
        source: &str,
        source_path: Option<&std::path::Path>,
    ) -> Box<dyn BuildJob> {
        let _ = (source, source_path);
        Box::new(UnsupportedJob)
    }

    /// Read the profile written by a run of a `profile_job_at` build.
    fn load_profile(&self, result: &BuildResult) -> Result<crate::profile::Profile, String> {
        let (Some(p), Some(m)) = (&result.profile_path, &result.profile_map_path) else {
            return Err("this build was not a profile build".into());
        };
        crate::profile::Profile::load(p, m)
    }
```

And at the bottom of `language.rs`:

```rust
/// `BuildJob` for languages that do not implement a feature.
struct UnsupportedJob;

impl BuildJob for UnsupportedJob {
    fn poll(&mut self) -> BuildPhase {
        BuildPhase::Failed("profiling is not supported for this language".into())
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-lang 2>&1 | grep -E "^test result|FAILED"`
Expected: `test result: ok. 6 passed`.

The workspace will not compile yet (`bruto-pascal-lang` constructs `BuildResult` without the new fields); that is fixed in Task 4. Verify only `-p bruto-lang` here.

- [ ] **Step 6: Commit (bruto-lang submodule)**

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-lang
rustfmt --edition 2024 src/profile.rs src/language.rs
git add src/profile.rs src/language.rs src/lib.rs
git commit --no-verify -m "feat: profile model, .bruto-prof reader, Language profiling hooks

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: C profiler runtime and its compile step

**Files:**
- Create: `bruto-pascal-lang/src/prof_runtime.c`
- Create: `bruto-pascal-lang/src/prof_runtime.rs`
- Modify: `bruto-pascal-lang/src/lib.rs` (add `pub mod prof_runtime;`)
- Modify: `bruto-pascal-lang/src/codegen.rs` (`spawn_linker_objs`)

**Interfaces:**
- Produces:
  ```rust
  // prof_runtime.rs
  pub const RUNTIME_SOURCE: &str; // include_str!("prof_runtime.c")
  pub fn write_runtime_source(dir: &Path) -> Result<PathBuf, String>;   // writes <dir>/bruto_prof_runtime.c
  pub fn spawn_runtime_compile(c_path: &Path, obj_path: &Path) -> Result<std::process::Child, String>; // cc -c
  // codegen.rs
  impl CodeGen { pub fn spawn_linker_objs(obj_paths: &[&str], output_path: &str) -> Result<Child, String>; }
  ```
  The C runtime exports `__bruto_prof_enter(uint32_t)`, `__bruto_prof_exit(void)`, `__bruto_prof_line(uint32_t)`, and reads the env var `BRUTO_PROF_OUT` for the output path.

- [ ] **Step 1: Write the failing test**

Create `bruto-pascal-lang/src/prof_runtime.rs`:

```rust
//! The profiler runtime that instrumented programs link against.
//!
//! The C source lives in `prof_runtime.c` and is embedded here so the
//! published crate is self-contained. On a profile build the source is
//! written to the temp dir and compiled with the same `cc` the linker
//! step already requires. Normal builds never touch it.

use std::path::{Path, PathBuf};

pub const RUNTIME_SOURCE: &str = include_str!("prof_runtime.c");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_compiles_and_records_a_tree() {
        let dir = std::env::temp_dir().join("bruto_prof_runtime_test");
        let _ = std::fs::create_dir_all(&dir);
        let c_path = write_runtime_source(&dir).unwrap();
        let obj = dir.join("rt.o");
        let status = spawn_runtime_compile(&c_path, &obj).unwrap().wait().unwrap();
        assert!(status.success(), "cc -c failed");

        // A tiny driver: main -> enter(1) line(2) enter(3) line(4) exit exit.
        let driver = dir.join("driver.c");
        std::fs::write(
            &driver,
            r#"
#include <stdint.h>
void __bruto_prof_enter(uint32_t); void __bruto_prof_exit(void); void __bruto_prof_line(uint32_t);
int main(void) {
    __bruto_prof_enter(1);
    __bruto_prof_line(2);
    for (int i = 0; i < 3; i++) { __bruto_prof_enter(3); __bruto_prof_line(4); __bruto_prof_exit(); }
    __bruto_prof_exit();
    return 0;
}
"#,
        )
        .unwrap();
        let exe = dir.join("driver");
        let cc = if cfg!(target_os = "windows") { "clang" } else { "cc" };
        let status = std::process::Command::new(cc)
            .arg(&driver)
            .arg(&obj)
            .arg("-o")
            .arg(&exe)
            .status()
            .unwrap();
        assert!(status.success(), "link failed");

        let out = dir.join("driver.bruto-prof");
        let _ = std::fs::remove_file(&out);
        let status = std::process::Command::new(&exe)
            .env("BRUTO_PROF_OUT", &out)
            .status()
            .unwrap();
        assert!(status.success());

        let bytes = std::fs::read(&out).expect("profile written");
        assert_eq!(&bytes[0..4], b"BPRF");
        let count = u32::from_le_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]);
        // Nodes: routine 1, line 2, routine 3 (once, 3 calls), line 4.
        assert_eq!(count, 4, "expected one node per (parent, loc) pair");
        // Routine 3 must have calls == 3: scan nodes for kind 1 / loc 3.
        let mut found = false;
        for i in 0..count as usize {
            let at = 24 + i * 33;
            let kind = bytes[at];
            let loc = u32::from_le_bytes([bytes[at + 1], bytes[at + 2], bytes[at + 3], bytes[at + 4]]);
            if kind == 1 && loc == 3 {
                let mut c = [0u8; 8];
                c.copy_from_slice(&bytes[at + 9..at + 17]);
                assert_eq!(u64::from_le_bytes(c), 3);
                found = true;
            }
        }
        assert!(found, "routine 3 node missing");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Add `pub mod prof_runtime;` after `pub mod parser;` in `bruto-pascal-lang/src/lib.rs`, then run:
`cd /Users/enzo/Code/bruto-pascal && LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-pascal-lang runtime_compiles 2>&1 | grep -E "^error" | head -3`
Expected: `couldn't read ... prof_runtime.c` (include_str fails) or `cannot find function write_runtime_source`.

- [ ] **Step 3: Write the C runtime**

Create `bruto-pascal-lang/src/prof_runtime.c`:

```c
/* Bruto line-profiler runtime. Linked only into profile builds.
 *
 * Codegen calls __bruto_prof_enter(id) at routine entry, __bruto_prof_exit()
 * before each return, and __bruto_prof_line(id) at each statement. The
 * runtime keeps a call tree keyed by (parent node, location id) in a fixed
 * open-addressing hash table and writes it to $BRUTO_PROF_OUT at exit.
 *
 * File format: see docs/superpowers/specs/2026-09-17-line-profiler-design.md
 * ("Profile file").
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
static uint64_t bp_now(void) {
    static LARGE_INTEGER freq;
    LARGE_INTEGER t;
    if (freq.QuadPart == 0) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return (uint64_t)((double)t.QuadPart * 1e9 / (double)freq.QuadPart);
}
#else
#include <time.h>
static uint64_t bp_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}
#endif

#define BP_CAPACITY 65536u   /* nodes; power of two */
#define BP_STACK    4096u
#define BP_NONE     0xFFFFFFFFu
#define BP_KIND_ROUTINE 1
#define BP_KIND_LINE    2
#define BP_FLAG_TABLE_FULL     1u
#define BP_FLAG_STACK_OVERFLOW 2u

typedef struct {
    uint8_t  used;
    uint8_t  kind;
    uint32_t loc;
    uint32_t parent;     /* node index or BP_NONE */
    uint64_t calls;
    uint64_t self_ns;
    uint64_t total_ns;
} bp_node;

typedef struct {
    uint32_t node;       /* routine node for this frame */
    uint64_t entered;    /* bp_now() at enter */
    uint64_t child_ns;   /* total time of callees, for self time */
    uint32_t cur_line;   /* line node currently running or BP_NONE */
    uint64_t line_start; /* bp_now() when cur_line began */
    uint64_t line_child_ns; /* callee time inside cur_line */
} bp_frame;

static bp_node  bp_nodes[BP_CAPACITY];
static uint32_t bp_count = 0;
static bp_frame bp_stack[BP_STACK];
static uint32_t bp_depth = 0;      /* frames in use */
static uint32_t bp_overflow = 0;   /* enters beyond BP_STACK, ignored */
static uint32_t bp_flags = 0;
static uint64_t bp_start = 0;
static int bp_registered = 0;

static void bp_write(void);

static uint32_t bp_find(uint32_t parent, uint32_t loc, uint8_t kind) {
    uint32_t h = (parent * 2654435761u) ^ (loc * 40503u);
    for (uint32_t probe = 0; probe < BP_CAPACITY; probe++) {
        uint32_t i = (h + probe) & (BP_CAPACITY - 1);
        bp_node *n = &bp_nodes[i];
        if (!n->used) {
            if (bp_count + 1 >= BP_CAPACITY) { bp_flags |= BP_FLAG_TABLE_FULL; return BP_NONE; }
            n->used = 1; n->kind = kind; n->loc = loc; n->parent = parent;
            bp_count++;
            return i;
        }
        if (n->loc == loc && n->parent == parent && n->kind == kind) return i;
    }
    bp_flags |= BP_FLAG_TABLE_FULL;
    return BP_NONE;
}

/* Close the running line of the top frame, charging it self time. */
static void bp_close_line(bp_frame *f, uint64_t now) {
    if (f->cur_line == BP_NONE) return;
    uint64_t span = now - f->line_start;
    bp_node *ln = &bp_nodes[f->cur_line];
    ln->total_ns += span;
    ln->self_ns += span > f->line_child_ns ? span - f->line_child_ns : 0;
    f->cur_line = BP_NONE;
    f->line_child_ns = 0;
}

void __bruto_prof_enter(uint32_t loc) {
    uint64_t now = bp_now();
    if (!bp_registered) { bp_registered = 1; bp_start = now; atexit(bp_write); }
    if (bp_overflow || bp_depth >= BP_STACK) { bp_overflow++; bp_flags |= BP_FLAG_STACK_OVERFLOW; return; }
    uint32_t parent = BP_NONE;
    if (bp_depth > 0) {
        bp_frame *top = &bp_stack[bp_depth - 1];
        parent = top->cur_line != BP_NONE ? top->cur_line : top->node;
    }
    uint32_t node = bp_find(parent, loc, BP_KIND_ROUTINE);
    bp_frame *f = &bp_stack[bp_depth++];
    f->node = node; f->entered = now; f->child_ns = 0;
    f->cur_line = BP_NONE; f->line_start = now; f->line_child_ns = 0;
    if (node != BP_NONE) bp_nodes[node].calls++;
}

void __bruto_prof_exit(void) {
    uint64_t now = bp_now();
    if (bp_overflow) { bp_overflow--; return; }
    if (bp_depth == 0) return;
    bp_frame *f = &bp_stack[--bp_depth];
    bp_close_line(f, now);
    uint64_t total = now - f->entered;
    if (f->node != BP_NONE) {
        bp_node *n = &bp_nodes[f->node];
        n->total_ns += total;
        n->self_ns += total > f->child_ns ? total - f->child_ns : 0;
    }
    if (bp_depth > 0) {
        bp_frame *caller = &bp_stack[bp_depth - 1];
        caller->child_ns += total;
        if (caller->cur_line != BP_NONE) caller->line_child_ns += total;
    }
}

void __bruto_prof_line(uint32_t loc) {
    uint64_t now = bp_now();
    if (bp_overflow || bp_depth == 0) return;
    bp_frame *f = &bp_stack[bp_depth - 1];
    bp_close_line(f, now);
    uint32_t node = bp_find(f->node, loc, BP_KIND_LINE);
    f->cur_line = node;
    f->line_start = now;
    f->line_child_ns = 0;
    if (node != BP_NONE) bp_nodes[node].calls++;
}

static void bp_put32(FILE *fp, uint32_t v) { uint8_t b[4]; for (int i = 0; i < 4; i++) b[i] = (uint8_t)(v >> (8 * i)); fwrite(b, 1, 4, fp); }
static void bp_put64(FILE *fp, uint64_t v) { uint8_t b[8]; for (int i = 0; i < 8; i++) b[i] = (uint8_t)(v >> (8 * i)); fwrite(b, 1, 8, fp); }

static void bp_write(void) {
    uint64_t now = bp_now();
    /* Close frames still open at exit (e.g. halt inside a routine). */
    while (bp_depth > 0) __bruto_prof_exit();
    const char *path = getenv("BRUTO_PROF_OUT");
    if (!path || !*path) return;
    FILE *fp = fopen(path, "wb");
    if (!fp) return;
    /* Node slots are sparse; compact them and remap parent indices. */
    uint32_t *remap = (uint32_t *)malloc(sizeof(uint32_t) * BP_CAPACITY);
    if (!remap) { fclose(fp); return; }
    uint32_t next = 0;
    for (uint32_t i = 0; i < BP_CAPACITY; i++) remap[i] = bp_nodes[i].used ? next++ : BP_NONE;
    fwrite("BPRF", 1, 4, fp);
    bp_put32(fp, 1);
    bp_put32(fp, bp_flags);
    bp_put64(fp, now - bp_start);
    bp_put32(fp, next);
    for (uint32_t i = 0; i < BP_CAPACITY; i++) {
        bp_node *n = &bp_nodes[i];
        if (!n->used) continue;
        fputc(n->kind, fp);
        bp_put32(fp, n->loc);
        bp_put32(fp, n->parent == BP_NONE ? BP_NONE : remap[n->parent]);
        bp_put64(fp, n->calls);
        bp_put64(fp, n->self_ns);
        bp_put64(fp, n->total_ns);
    }
    free(remap);
    fclose(fp);
}
```

- [ ] **Step 4: Write the Rust helpers**

Insert into `bruto-pascal-lang/src/prof_runtime.rs` above the tests:

```rust
/// Write the embedded C source to `dir/bruto_prof_runtime.c`.
pub fn write_runtime_source(dir: &Path) -> Result<PathBuf, String> {
    let path = dir.join("bruto_prof_runtime.c");
    std::fs::write(&path, RUNTIME_SOURCE).map_err(|e| format!("profiler runtime: write: {e}"))?;
    Ok(path)
}

/// Spawn `cc -c` (or `clang -c` on Windows) turning the runtime source into
/// an object file. The caller polls the child like the linker.
pub fn spawn_runtime_compile(c_path: &Path, obj_path: &Path) -> Result<std::process::Child, String> {
    let cc = if cfg!(target_os = "windows") { "clang" } else { "cc" };
    std::process::Command::new(cc)
        .arg("-O2")
        .arg("-c")
        .arg(c_path)
        .arg("-o")
        .arg(obj_path)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("profiler runtime: failed to spawn {cc}: {e}"))
}
```

- [ ] **Step 5: Add a multi-object linker spawn in `codegen.rs`**

Replace the body of `spawn_linker` so it delegates, and add `spawn_linker_objs` right after it:

```rust
    pub fn spawn_linker(obj_path: &str, output_path: &str) -> Result<std::process::Child, String> {
        Self::spawn_linker_objs(&[obj_path], output_path)
    }

    /// Same as [`spawn_linker`] for several object files (the profile build
    /// links the program object plus the profiler runtime object).
    pub fn spawn_linker_objs(
        obj_paths: &[&str],
        output_path: &str,
    ) -> Result<std::process::Child, String> {
        let linker = if cfg!(target_os = "windows") { "clang" } else { "cc" };
        let mut link_args: Vec<&str> = obj_paths.to_vec();
        link_args.extend(["-o", output_path, "-g"]);
        #[cfg(not(target_os = "windows"))]
        link_args.push("-lm");
        #[cfg(target_os = "linux")]
        link_args.push("-no-pie");
        #[cfg(all(target_os = "windows", target_env = "msvc"))]
        {
            link_args.push("-fuse-ld=lld");
            link_args.push("-lmsvcrt");
            link_args.push("-llegacy_stdio_definitions");
        }
        std::process::Command::new(linker)
            .args(&link_args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("failed to spawn linker: {e}"))
    }
```

Keep the existing doc comment about platform linker choice above `spawn_linker`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-pascal-lang runtime_compiles -- --test-threads=1 2>&1 | grep -E "^test result|FAILED|panicked"`
Expected: `test result: ok. 1 passed`. (If the crate does not compile because of `BuildResult` fields from Task 1, add `profile_path: None, profile_map_path: None,` to the `BuildResult { .. }` literal in `finalize` of `bruto-pascal-lang/src/lib.rs` now; Task 4 replaces it.)

- [ ] **Step 7: Commit (bruto-pascal-lang submodule)**

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-pascal-lang
rustfmt --edition 2024 src/prof_runtime.rs src/codegen.rs src/lib.rs
git add src/prof_runtime.c src/prof_runtime.rs src/codegen.rs src/lib.rs
git commit --no-verify -m "feat: embedded C profiler runtime and multi-object link step

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Codegen instrumentation and id map

**Files:**
- Modify: `bruto-pascal-lang/src/codegen.rs`

**Interfaces:**
- Produces:
  ```rust
  impl CodeGen { pub fn set_instrument(&mut self, on: bool); pub fn write_prof_map(&self, exe_path: &str) -> Result<String, String>; /* returns the map path */ }
  ```
  Map line format: `P <id> <line> <name>` for routines, `L <id> <line> <col>` for statements. The main block is the routine named `program`.

- [ ] **Step 1: Write the failing tests**

Append to the `tests` module at the bottom of `bruto-pascal-lang/src/lib.rs`:

```rust
    fn ir_for(source: &str, instrument: bool) -> (String, Vec<String>) {
        let mut parser = Parser::new(source);
        let program = parser.parse_program().expect("parse");
        let context = Context::create();
        let mut cg = CodeGen::new(&context, "/tmp/t.pas");
        cg.set_instrument(instrument);
        cg.compile(&program).expect("codegen");
        (cg.print_ir(), cg.prof_map_lines().to_vec())
    }

    // Globals are passed by `var` parameter: top-level procedures cannot
    // reference globals directly in the current codegen (pre-existing).
    const PROF_SRC: &str = "program P;\nvar i: integer;\nprocedure Q(var n: integer);\nbegin\n  n := n + 1\nend;\nbegin\n  i := 0;\n  Q(i)\nend.\n";

    #[test]
    fn instrumented_ir_has_hooks_and_map() {
        let (ir, map) = ir_for(PROF_SRC, true);
        assert!(ir.contains("call void @__bruto_prof_enter"));
        assert!(ir.contains("call void @__bruto_prof_exit"));
        assert!(ir.contains("call void @__bruto_prof_line"));
        // Two routines: Q (line 3) and the program block; three statements
        // (line 5, line 8, line 9).
        assert!(map.iter().any(|l| l.starts_with("P ") && l.ends_with(" 3 Q")), "{map:?}");
        assert!(map.iter().any(|l| l.starts_with("P ") && l.ends_with(" program")), "{map:?}");
        assert_eq!(map.iter().filter(|l| l.starts_with("L ")).count(), 3, "{map:?}");
        // exit before every ret: Q returns once, main returns once.
        assert_eq!(ir.matches("call void @__bruto_prof_exit").count(), 2);
    }

    #[test]
    fn uninstrumented_ir_is_clean() {
        let (ir, map) = ir_for(PROF_SRC, false);
        assert!(!ir.contains("__bruto_prof"));
        assert!(map.is_empty());
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-pascal-lang instrumented -- --test-threads=1 2>&1 | grep -E "^error" | head -3`
Expected: `no method named set_instrument`.

- [ ] **Step 3: Add the fields and helpers to `CodeGen`**

In the `CodeGen` struct (after `metadata_lines: Vec<String>,`):

```rust
    // Profiling instrumentation (see prof_runtime.rs). Off by default.
    instrument: bool,
    prof_next_id: u32,
    // `P <id> <line> <name>` / `L <id> <line> <col>` lines for <exe>.bruto-prof-map
    prof_map_lines: Vec<String>,
```

In `CodeGen::new`, after `metadata_lines: Vec::new(),`:

```rust
            instrument: false,
            prof_next_id: 1,
            prof_map_lines: Vec::new(),
```

After `write_metadata`, add:

```rust
    /// Turn profiler instrumentation on or off. Must be called before
    /// `compile`.
    pub fn set_instrument(&mut self, on: bool) {
        self.instrument = on;
    }

    /// The id map accumulated so far (for tests and `write_prof_map`).
    pub fn prof_map_lines(&self) -> &[String] {
        &self.prof_map_lines
    }

    /// Write `<exe>.bruto-prof-map` and return its path.
    pub fn write_prof_map(&self, exe_path: &str) -> Result<String, String> {
        let path = format!("{exe_path}.bruto-prof-map");
        let mut body = self.prof_map_lines.join("\n");
        body.push('\n');
        std::fs::write(&path, body).map_err(|e| format!("prof map write: {e}"))?;
        Ok(path)
    }

    // ── profiler hooks ───────────────────────────────────

    /// Declare the three runtime hooks. Called once from `compile` when
    /// instrumentation is on.
    fn emit_prof_decls(&self) {
        let void_ty = self.context.void_type();
        let i32_ty = self.context.i32_type();
        self.module
            .add_function("__bruto_prof_enter", void_ty.fn_type(&[i32_ty.into()], false), None);
        self.module
            .add_function("__bruto_prof_exit", void_ty.fn_type(&[], false), None);
        self.module
            .add_function("__bruto_prof_line", void_ty.fn_type(&[i32_ty.into()], false), None);
    }

    fn prof_alloc_id(&mut self) -> u32 {
        let id = self.prof_next_id;
        self.prof_next_id += 1;
        id
    }

    /// `__bruto_prof_enter(id)` at the current insertion point, registering
    /// `name` at `line` as a routine.
    fn emit_prof_enter(&mut self, name: &str, line: u32) -> Result<(), CodeGenError> {
        if !self.instrument {
            return Ok(());
        }
        let id = self.prof_alloc_id();
        self.prof_map_lines.push(format!("P {id} {line} {name}"));
        let f = self.module.get_function("__bruto_prof_enter").unwrap();
        self.builder
            .build_call(f, &[self.context.i32_type().const_int(id as u64, false).into()], "")
            .map_err(|e| CodeGenError::new(e.to_string(), None))?;
        Ok(())
    }

    /// `__bruto_prof_exit()` at the current insertion point (call right
    /// before every `ret`).
    fn emit_prof_exit(&mut self) -> Result<(), CodeGenError> {
        if !self.instrument {
            return Ok(());
        }
        let f = self.module.get_function("__bruto_prof_exit").unwrap();
        self.builder
            .build_call(f, &[], "")
            .map_err(|e| CodeGenError::new(e.to_string(), None))?;
        Ok(())
    }

    /// `__bruto_prof_line(id)` for the statement at `span`.
    fn emit_prof_line(&mut self, span: Span) -> Result<(), CodeGenError> {
        if !self.instrument {
            return Ok(());
        }
        let id = self.prof_alloc_id();
        self.prof_map_lines
            .push(format!("L {id} {} {}", span.line, span.column));
        let f = self.module.get_function("__bruto_prof_line").unwrap();
        self.builder
            .build_call(f, &[self.context.i32_type().const_int(id as u64, false).into()], "")
            .map_err(|e| CodeGenError::new(e.to_string(), Some(span)))?;
        Ok(())
    }
```

- [ ] **Step 4: Insert the hooks**

In `compile`, right after `self.emit_runtime_decls();`:

```rust
        if self.instrument {
            self.emit_prof_decls();
        }
```

In `compile`, replace the block that installs the stack guard so the enter hook comes first (keep the guard call as is):

```rust
        // Install signal handler to catch stack overflow / segfaults.
        self.set_debug_loc(program.span);
        self.emit_prof_enter("program", program.body.span.line)?;
        {
```

In `compile`, before the final `build_return` of main (after `self.set_debug_loc(program.body.end_span);`):

```rust
        self.emit_prof_exit()?;
```

In `compile_proc_decl`, right after `self.set_debug_loc(proc.span);` (the one following `self.current_scope = Some(di_sub...)`):

```rust
        let proc_name = proc.name.clone();
        self.emit_prof_enter(&proc_name, proc.span.line)?;
```

In `compile_proc_decl`, replace the `// Return` section with:

```rust
        // Return (profiler exit first so the routine's time closes)
        self.emit_prof_exit()?;
        if let Some(ref ret_ty) = proc.return_type {
```

(the rest of the return code is unchanged).

In `compile_statement`, wrap the existing `match` so every statement is counted. Change the start of the function to:

```rust
    fn compile_statement(&mut self, stmt: &Statement) -> Result<(), CodeGenError> {
        if !matches!(stmt, Statement::Label { .. }) {
            self.emit_prof_line(stmt.span())?;
        }
        match stmt {
```

`Statement::span()` already exists in `ast.rs` (the match at line ~329 covers every variant, including `Block`). Compound statements (`Block`, `If`, `While`) get a line hook on their opening line, which is what Turbo Profiler does too.

- [ ] **Step 5: Run tests to verify they pass**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-pascal-lang -- --test-threads=1 2>&1 | grep -E "^test result|FAILED|panicked"`
Expected: all pass, including `instrumented_ir_has_hooks_and_map` and `uninstrumented_ir_is_clean`; the existing 62 tests still pass (the uninstrumented path is unchanged). `PROF_SRC` has exactly three statements (`n := n + 1`, `i := 0`, `Q(i)`) and no compound statements, so the `L` count is exactly 3.

- [ ] **Step 6: Commit**

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-pascal-lang
rustfmt --edition 2024 src/codegen.rs src/lib.rs src/ast.rs
git add src/codegen.rs src/lib.rs src/ast.rs
git commit --no-verify -m "feat: emit profiler hooks and id map when instrumentation is on

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Profile build job and `load_profile` for Pascal

**Files:**
- Modify: `bruto-pascal-lang/src/lib.rs`

**Interfaces:**
- Consumes: `CodeGen::set_instrument`, `write_prof_map`, `spawn_linker_objs`; `prof_runtime::{write_runtime_source, spawn_runtime_compile}`; `BuildResult::{profile_path, profile_map_path}`.
- Produces: `MiniPascal::profile_job_at` (trait impl). The executable is `<tmp>/bruto_pascal_prof`, profile file `<exe>.bruto-prof`, map `<exe>.bruto-prof-map`. The program reads `BRUTO_PROF_OUT`; the IDE must set it when running (Task 7). `load_profile` uses the trait default.

- [ ] **Step 1: Write the failing test**

Append to the tests module in `bruto-pascal-lang/src/lib.rs`:

```rust
    #[test]
    fn profile_build_and_run() {
        use bruto_lang::profile::ProfileKind;
        // `acc` is passed by `var`: top-level procedures cannot reference
        // globals directly in the current codegen (pre-existing limitation).
        let src = "program Hot;\nvar i, acc: integer;\nprocedure Work(var a: integer);\nvar k: integer;\nbegin\n  for k := 1 to 2000 do\n    a := a + k\nend;\nbegin\n  acc := 0;\n  for i := 1 to 50 do\n    Work(acc);\n  writeln(acc)\nend.\n";
        let lang = MiniPascal;
        let mut job = lang.profile_job_at(src, None);
        let result = loop {
            match job.poll() {
                BuildPhase::Pending(_) => std::thread::sleep(std::time::Duration::from_millis(10)),
                BuildPhase::Done(r) => break r,
                BuildPhase::Failed(e) => panic!("profile build failed: {e}"),
            }
        };
        let prof_path = result.profile_path.clone().expect("profile path");
        let _ = std::fs::remove_file(&prof_path);
        let status = std::process::Command::new(&result.exe_path)
            .env("BRUTO_PROF_OUT", &prof_path)
            .stdout(std::process::Stdio::null())
            .status()
            .expect("run");
        assert!(status.success());

        let profile = lang.load_profile(&result).expect("load profile");
        assert!(profile.elapsed_ns > 0);
        assert!(!profile.truncated);
        let work = profile
            .nodes
            .iter()
            .find(|n| n.kind == ProfileKind::Routine && n.name == "Work")
            .expect("Work node");
        assert_eq!(work.calls, 50);
        assert_eq!(work.line, 3);
        let totals = profile.line_totals();
        let (hot_line, _) = totals
            .iter()
            .max_by_key(|(_, (self_ns, _))| *self_ns)
            .map(|(l, v)| (*l, *v))
            .unwrap();
        assert_eq!(hot_line, 7, "hottest line should be the inner assignment: {totals:?}");
        assert_eq!(totals[&7].1, 50 * 2000, "hits of the inner assignment");

        let _ = std::fs::remove_file(&result.exe_path);
        let _ = std::fs::remove_dir_all(format!("{}.dSYM", result.exe_path));
        let _ = std::fs::remove_file(&prof_path);
        let _ = std::fs::remove_file(result.profile_map_path.unwrap());
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-pascal-lang profile_build_and_run -- --test-threads=1 2>&1 | grep -E "panicked|FAILED|test result" | head -3`
Expected: FAILED with `profile build failed: profiling is not supported for this language`.

- [ ] **Step 3: Implement the profile job**

In `bruto-pascal-lang/src/lib.rs`:

Factor the search-dir logic out of `build_job_at` so both jobs share it. Replace `build_job_at` and add `profile_job_at` in the `Language for MiniPascal` impl:

```rust
    fn build_job_at(&self, source: &str, source_path: Option<&Path>) -> Box<dyn BuildJob> {
        Box::new(PascalBuildJob::new(
            source.to_string(),
            search_dirs_for(source_path),
            false,
        ))
    }

    fn profile_job_at(&self, source: &str, source_path: Option<&Path>) -> Box<dyn BuildJob> {
        Box::new(PascalBuildJob::new(
            source.to_string(),
            search_dirs_for(source_path),
            true,
        ))
    }
```

and add the free function below the impl:

```rust
/// Directories searched for `uses` units: the source file's directory
/// first, then the current directory.
fn search_dirs_for(source_path: Option<&Path>) -> Vec<PathBuf> {
    let mut search_dirs = Vec::new();
    if let Some(dir) = source_path.and_then(|p| p.parent()) {
        search_dirs.push(dir.to_path_buf());
    }
    if let Ok(cwd) = std::env::current_dir()
        && !search_dirs.iter().any(|d| d == &cwd)
    {
        search_dirs.push(cwd);
    }
    search_dirs
}
```

Change `build_job` to `Box::new(PascalBuildJob::new(source.to_string(), Vec::new(), false))`.

Update the job types:

```rust
struct PascalBuildJob {
    inner: JobInner,
    search_dirs: Vec<PathBuf>,
    /// Compile with profiler hooks and link the profiler runtime.
    profile: bool,
}

enum JobInner {
    NotStarted { source: String },
    /// Profile builds only: `cc -c` on the runtime source is running.
    CompilingRuntime {
        paths: JobPaths,
        child: std::process::Child,
    },
    Linking {
        paths: JobPaths,
        child: std::process::Child,
    },
    Dsymutil {
        paths: JobPaths,
        child: std::process::Child,
    },
    Drained,
}

struct JobPaths {
    source_path: String,
    exe_path: String,
    obj_path: String,
    /// Profile builds: the runtime object and the id map.
    runtime_obj_path: Option<String>,
    prof_map_path: Option<String>,
}
```

`PascalBuildJob::new(source, search_dirs, profile: bool)` sets the new field.

In `poll`, add an arm before `Linking`:

```rust
            JobInner::CompilingRuntime { paths, mut child } => match child.try_wait() {
                Ok(None) => {
                    self.inner = JobInner::CompilingRuntime { paths, child };
                    BuildPhase::Pending("Compiling profiler runtime…".into())
                }
                Ok(Some(status)) if status.success() => self.spawn_link(paths),
                Ok(Some(_)) => {
                    let stderr = child
                        .wait_with_output()
                        .map(|o| String::from_utf8_lossy(&o.stderr).into_owned())
                        .unwrap_or_default();
                    BuildPhase::Failed(format!("profiler runtime: {stderr}"))
                }
                Err(e) => BuildPhase::Failed(format!("waiting on profiler runtime compile: {e}")),
            },
```

In `start`, change the exe stem and the tail. Replace from `let exe_path = tmp.join(...)` through the end of the function with:

```rust
        let stem = if self.profile { "bruto_pascal_prof" } else { "bruto_pascal_out" };
        let exe_path = tmp
            .join(if cfg!(windows) { format!("{stem}.exe") } else { stem.to_string() })
            .to_string_lossy()
            .into_owned();

        if let Err(e) = std::fs::write(&source_path, &source) {
            return BuildPhase::Failed(format!("Failed to write source: {e}"));
        }

        let mut parser = Parser::new(&source);
        let mut program = match parser.parse_program() {
            Ok(p) => p,
            Err(e) => return BuildPhase::Failed(format!("Parse error: {e}")),
        };

        if let Err(e) = resolve_uses(&mut program, &self.search_dirs) {
            return BuildPhase::Failed(e);
        }

        let context = Context::create();
        let mut codegen = CodeGen::new(&context, &source_path);
        codegen.set_directives(parser.directives);
        codegen.set_instrument(self.profile);
        if let Err(e) = codegen.compile(&program) {
            return BuildPhase::Failed(format!("Codegen error: {e}"));
        }

        let obj_path = match codegen.emit_object(&exe_path) {
            Ok(p) => p,
            Err(e) => return BuildPhase::Failed(e),
        };
        let _ = codegen.write_metadata(&exe_path);

        let mut paths = JobPaths {
            source_path,
            exe_path,
            obj_path,
            runtime_obj_path: None,
            prof_map_path: None,
        };

        if self.profile {
            paths.prof_map_path = match codegen.write_prof_map(&paths.exe_path) {
                Ok(p) => Some(p),
                Err(e) => return BuildPhase::Failed(e),
            };
            let c_path = match prof_runtime::write_runtime_source(&tmp) {
                Ok(p) => p,
                Err(e) => return BuildPhase::Failed(e),
            };
            let rt_obj = tmp.join("bruto_prof_runtime.o");
            let child = match prof_runtime::spawn_runtime_compile(&c_path, &rt_obj) {
                Ok(c) => c,
                Err(e) => return BuildPhase::Failed(e),
            };
            paths.runtime_obj_path = Some(rt_obj.to_string_lossy().into_owned());
            self.inner = JobInner::CompilingRuntime { paths, child };
            return BuildPhase::Pending("Compiling profiler runtime…".into());
        }

        self.spawn_link(paths)
    }

    /// Spawn the linker over the program object (plus the runtime object
    /// for profile builds) and move to `Linking`.
    fn spawn_link(&mut self, paths: JobPaths) -> BuildPhase {
        let mut objs: Vec<&str> = vec![paths.obj_path.as_str()];
        if let Some(rt) = paths.runtime_obj_path.as_deref() {
            objs.push(rt);
        }
        let child = match CodeGen::spawn_linker_objs(&objs, &paths.exe_path) {
            Ok(c) => c,
            Err(e) => return BuildPhase::Failed(e),
        };
        self.inner = JobInner::Linking { paths, child };
        BuildPhase::Pending("Linking…".into())
    }
```

Update `finalize`:

```rust
    fn finalize(&mut self, paths: JobPaths) -> BuildPhase {
        let _ = std::fs::remove_file(&paths.obj_path);
        if let Some(rt) = &paths.runtime_obj_path {
            let _ = std::fs::remove_file(rt);
        }
        let profile_path = self.profile.then(|| format!("{}.bruto-prof", paths.exe_path));
        BuildPhase::Done(BuildResult {
            exe_path: paths.exe_path,
            source_path: paths.source_path,
            console_capture_path: bruto_lang::target::console_capture_path(),
            profile_path,
            profile_map_path: paths.prof_map_path,
        })
    }
```

Update `Drop` to also kill a `CompilingRuntime` child:

```rust
            JobInner::CompilingRuntime { child, .. }
            | JobInner::Linking { child, .. }
            | JobInner::Dsymutil { child, .. } => {
```

Add `use crate::prof_runtime;` is unnecessary since the module is in the same crate root: reference it as `prof_runtime::write_runtime_source` (module declared in lib.rs).

- [ ] **Step 4: Run the test to verify it passes**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-pascal-lang -- --test-threads=1 2>&1 | grep -E "^test result|FAILED|panicked"`
Expected: all pass, including `profile_build_and_run`.

- [ ] **Step 5: Build the whole workspace**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo build 2>&1 | grep -E "^(error|warning: unused)"`
Expected: no output (the IDE does not construct `BuildResult`).

- [ ] **Step 6: Commit**

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-pascal-lang
rustfmt --edition 2024 src/lib.rs
git add src/lib.rs
git commit --no-verify -m "feat: profile build job linking the profiler runtime

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Heat column in the editor window

**Files:**
- Create: `bruto-ide/src/heat.rs`
- Modify: `bruto-ide/src/lib.rs` (add `pub mod heat;`)
- Modify: `bruto-ide/src/commands.rs`
- Modify: `bruto-ide/src/ide_editor.rs`

**Interfaces:**
- Produces:
  ```rust
  // heat.rs
  pub const PROFILE_COL_WIDTH: i16 = 7;
  pub enum Heat { None, Cold, Warm, Hot }
  pub fn heat_bucket(share: f64) -> Heat;          // share in 0.0..=1.0
  pub fn format_share(self_ns: u64, total_ns: u64) -> String; // exactly 7 chars
  pub struct LineProfile { pub lines: HashMap<usize, (u64, u64)>, pub total_ns: u64, pub visible: bool, pub text_hash: u64 }
  pub fn text_hash(text: &str) -> u64;
  // ide_editor.rs
  impl IdeEditorWindow { pub fn set_line_profile(&mut self, p: Option<LineProfile>); pub fn has_line_profile(&self) -> bool; pub fn profile_column_visible(&self) -> bool; pub fn set_profile_column_visible(&mut self, on: bool); }
  // commands.rs
  pub const CM_PROFILE: u16 = 450; pub const CM_SHOW_PROFILE: u16 = 451; pub const CM_TOGGLE_PROFILE_COLUMN: u16 = 452;
  ```

- [ ] **Step 1: Write the failing tests**

Create `bruto-ide/src/heat.rs`:

```rust
//! Per-line profile data as shown by the editor's heat column.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};

/// Width of the profile column drawn between the gutter and the text.
pub const PROFILE_COL_WIDTH: i16 = 7;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Heat {
    /// Below 1 percent or never executed: no tint.
    None,
    /// 1 to 5 percent of total time.
    Cold,
    /// 5 to 20 percent.
    Warm,
    /// Above 20 percent.
    Hot,
}

/// Profile of one buffer: line -> (self_ns, hits), plus what it takes to
/// know when the data went stale.
#[derive(Debug, Clone)]
pub struct LineProfile {
    pub lines: HashMap<usize, (u64, u64)>,
    pub total_ns: u64,
    pub visible: bool,
    /// `text_hash` of the buffer when the profile was taken; a differing
    /// hash means the user edited and the column must go.
    pub text_hash: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buckets_follow_the_spec_thresholds() {
        assert_eq!(heat_bucket(0.0), Heat::None);
        assert_eq!(heat_bucket(0.009), Heat::None);
        assert_eq!(heat_bucket(0.01), Heat::Cold);
        assert_eq!(heat_bucket(0.049), Heat::Cold);
        assert_eq!(heat_bucket(0.05), Heat::Warm);
        assert_eq!(heat_bucket(0.199), Heat::Warm);
        assert_eq!(heat_bucket(0.2), Heat::Hot);
        assert_eq!(heat_bucket(1.0), Heat::Hot);
    }

    #[test]
    fn share_is_always_seven_chars() {
        assert_eq!(format_share(124, 1000), " 12.4% ");
        assert_eq!(format_share(1000, 1000), "100.0% ");
        assert_eq!(format_share(1, 100_000), " <0.1% ");
        assert_eq!(format_share(0, 1000), "       ");
        assert_eq!(format_share(5, 0), "       ");
        for s in [format_share(124, 1000), format_share(1, 100_000), format_share(0, 1)] {
            assert_eq!(s.chars().count(), PROFILE_COL_WIDTH as usize, "{s:?}");
        }
    }

    #[test]
    fn text_hash_changes_with_text() {
        assert_eq!(text_hash("a"), text_hash("a"));
        assert_ne!(text_hash("a"), text_hash("b"));
    }
}
```

Add `pub mod heat;` to `bruto-ide/src/lib.rs`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-ide heat 2>&1 | grep -E "^error" | head -3`
Expected: `cannot find function heat_bucket`.

- [ ] **Step 3: Implement heat helpers**

Insert above the tests in `bruto-ide/src/heat.rs`:

```rust
pub fn heat_bucket(share: f64) -> Heat {
    if share >= 0.20 {
        Heat::Hot
    } else if share >= 0.05 {
        Heat::Warm
    } else if share >= 0.01 {
        Heat::Cold
    } else {
        Heat::None
    }
}

/// The column text for a line: `" 12.4% "`, `"100.0% "`, `" <0.1% "`, or
/// blanks when the line never ran (or there is no total).
pub fn format_share(self_ns: u64, total_ns: u64) -> String {
    if total_ns == 0 || self_ns == 0 {
        return " ".repeat(PROFILE_COL_WIDTH as usize);
    }
    let pct = self_ns as f64 * 100.0 / total_ns as f64;
    if pct < 0.1 {
        return " <0.1% ".to_string();
    }
    format!("{pct:5.1}% ")
}

pub fn text_hash(text: &str) -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    text.hash(&mut h);
    h.finish()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-ide heat 2>&1 | grep -E "^test result|FAILED"`
Expected: `3 passed`.

- [ ] **Step 5: Add commands**

Append to `bruto-ide/src/commands.rs`:

```rust

/// Build with profiler instrumentation, run, and show results (Shift+F9)
pub const CM_PROFILE: u16 = 450;

/// Open the Profile window
pub const CM_SHOW_PROFILE: u16 = 451;

/// Show or hide the per-line profile column in the focused editor
pub const CM_TOGGLE_PROFILE_COLUMN: u16 = 452;
```

- [ ] **Step 6: Wire the column into `IdeEditorWindow`**

In `bruto-ide/src/ide_editor.rs`:

Imports: add `use crate::heat::{Heat, LineProfile, PROFILE_COL_WIDTH, format_share, heat_bucket, text_hash};` and `use turbo_vision::core::draw::DrawBuffer;` and `use turbo_vision::views::view::write_line_to_terminal;`.

Add a field to the struct (after `build_error`):

```rust
    /// Per-line timings from the last profile run. `None` until a profile
    /// run completes; cleared on the next build or when the text changes.
    line_profile: Option<LineProfile>,
```

and `line_profile: None,` in the `Self { .. }` literal in `new`.

Add methods to `impl IdeEditorWindow`:

```rust
    pub fn set_line_profile(&mut self, p: Option<LineProfile>) {
        self.line_profile = p;
    }

    pub fn has_line_profile(&self) -> bool {
        self.line_profile.is_some()
    }

    pub fn profile_column_visible(&self) -> bool {
        self.line_profile.as_ref().is_some_and(|p| p.visible)
    }

    pub fn set_profile_column_visible(&mut self, on: bool) {
        if let Some(p) = self.line_profile.as_mut() {
            p.visible = on;
        }
    }

    /// Width of the profile column currently occupying interior space.
    fn profile_col_width(&self) -> i16 {
        if self.profile_column_visible() {
            PROFILE_COL_WIDTH
        } else {
            0
        }
    }

    /// Drop the profile if the buffer changed since it was taken.
    fn drop_profile_if_edited(&mut self) {
        let Some(p) = self.line_profile.as_ref() else {
            return;
        };
        let now = text_hash(&self.editor.borrow().get_text());
        if now != p.text_hash {
            self.line_profile = None;
        }
    }

    /// Paint the profile column and the heat tint for every visible row.
    fn draw_profile_overlay(&self, terminal: &mut Terminal) {
        let Some(p) = self.line_profile.as_ref() else {
            return;
        };
        if !p.visible {
            return;
        }
        let extent = self.window.extent();
        let interior_h = extent.height().saturating_sub(2);
        let scroll_y = self.editor.borrow().get_delta().y.max(0) as usize;
        let col_x = 1 + GUTTER_WIDTH; // after the frame line and the gutter
        let text_attr = Attr::new(TvColor::LightGray, TvColor::Rgb { r: 0, g: 0, b: 100 });
        for row in 0..interior_h {
            let line = scroll_y + row as usize + 1;
            let (self_ns, _hits) = p.lines.get(&line).copied().unwrap_or((0, 0));
            let share = if p.total_ns == 0 { 0.0 } else { self_ns as f64 / p.total_ns as f64 };
            let heat = heat_bucket(share);
            let bg = match heat {
                Heat::None => None,
                Heat::Cold => Some(TvColor::Rgb { r: 110, g: 0, b: 0 }),
                Heat::Warm => Some(TvColor::Red),
                Heat::Hot => Some(TvColor::LightRed),
            };
            if let Some(bg) = bg {
                self.highlight_interior_row(terminal, row, bg);
                if heat == Heat::Hot {
                    // Bright rows get white text so the tint stays legible.
                    let y = 1 + row;
                    for x in (col_x + PROFILE_COL_WIDTH)..(extent.b.x - 1) {
                        if let Some(c) = terminal.read_cell(x, y) {
                            terminal.write_cell(x, y, Cell::new(c.ch, Attr::new(TvColor::White, bg)));
                        }
                    }
                }
            }
            let mut buf = DrawBuffer::new(PROFILE_COL_WIDTH as usize);
            let attr = match bg {
                Some(bg) => Attr::new(TvColor::White, bg),
                None => text_attr,
            };
            buf.move_str(0, &format_share(self_ns, p.total_ns), attr);
            write_line_to_terminal(terminal, col_x, 1 + row, &buf);
        }
    }
```

Update `sync_interior_layout` so the editor starts after the column:

```rust
        let col = self.profile_col_width();
        let editor_bounds = Rect::new(GUTTER_WIDTH + col, 0, interior_w, interior_h);
```

(the gutter bounds stay as they are).

In the `draw` override, after `self.window_draw(terminal);` and before the error-line overlay, add:

```rust
        // Profile column and heat tint first; the error and exec overlays
        // below paint over it because they are more urgent.
        self.draw_profile_overlay(terminal);
```

In the `handle_event` override, after `self.window_handle_event(event);` add:

```rust
        // An edit invalidates the profile. Only keyboard events can change
        // the text, so the hash is checked there and never per frame.
        if event.what == EventType::Nothing && self.line_profile.is_some() {
            self.drop_profile_if_edited();
        }
```

Place that check right before the `if event.what == EventType::Command && event.command == CM_CLOSE` block. Note the condition: keyboard events consumed by the editor come back as `EventType::Nothing`; mouse events also do, which costs one `get_text` per click while a profile is shown, which is acceptable.

Also clear the profile in `FileEditor::load`, `new_buffer` and `reload` (add `self.line_profile = None;` in each, next to `clear_breakpoints`).

- [ ] **Step 7: Build and run all bruto-ide tests**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-ide 2>&1 | grep -E "^test result|FAILED|^error"`
Expected: `27 passed` (24 existing + 3 heat), no errors.

- [ ] **Step 8: Commit (bruto-ide submodule)**

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-ide
rustfmt --edition 2024 src/heat.rs src/ide_editor.rs src/commands.rs src/lib.rs
git add src/heat.rs src/ide_editor.rs src/commands.rs src/lib.rs
git commit --no-verify -m "feat: per-line profile column and heat tint in the editor window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Profile window

**Files:**
- Create: `bruto-ide/src/profile_window.rs`
- Modify: `bruto-ide/src/lib.rs` (add `pub mod profile_window;`)

**Interfaces:**
- Consumes: `bruto_lang::profile::{Profile, ProfileKind, ProfileNode}`.
- Produces:
  ```rust
  pub struct Row { pub node: usize, pub depth: usize, pub expandable: bool, pub expanded: bool }
  pub fn flatten_tree(profile: &Profile, collapsed: &HashSet<usize>) -> Vec<Row>;
  pub struct ProfilePanel;  // View
  impl ProfilePanel { pub fn new(bounds: Rect) -> Self; pub fn set_profile(&mut self, p: Option<Profile>); pub fn take_pending_jump(&mut self) -> Option<usize>; /* 1-based line */ }
  ```

- [ ] **Step 1: Write the failing tests**

Create `bruto-ide/src/profile_window.rs` with the test module:

```rust
//! Profile window — a collapsible call tree of routines and lines from the
//! last profile run. Same view pattern as `CallStackPanel`: owner-relative
//! drawing, gray dialog palette, jumps delivered through `pending_jump`.

#[cfg(test)]
mod tests {
    use super::*;
    use bruto_lang::profile::{Profile, ProfileKind, ProfileNode};

    fn node(kind: ProfileKind, name: &str, line: usize, parent: Option<usize>, total: u64) -> ProfileNode {
        ProfileNode { kind, name: name.into(), line, parent, calls: 1, self_ns: total / 2, total_ns: total }
    }

    fn sample() -> Profile {
        Profile {
            elapsed_ns: 1000,
            truncated: false,
            nodes: vec![
                node(ProfileKind::Routine, "program", 1, None, 1000), // 0
                node(ProfileKind::Line, "", 10, Some(0), 100),         // 1
                node(ProfileKind::Routine, "Work", 3, Some(0), 800),   // 2
                node(ProfileKind::Line, "", 5, Some(2), 800),          // 3
                node(ProfileKind::Line, "", 11, Some(0), 50),          // 4
            ],
        }
    }

    #[test]
    fn flatten_orders_children_by_total_descending() {
        let rows = flatten_tree(&sample(), &HashSet::new());
        let order: Vec<usize> = rows.iter().map(|r| r.node).collect();
        assert_eq!(order, vec![0, 2, 3, 1, 4]);
        assert_eq!(rows[0].depth, 0);
        assert_eq!(rows[1].depth, 1);
        assert_eq!(rows[2].depth, 2);
        assert!(rows[0].expandable && rows[0].expanded);
        assert!(!rows[2].expandable, "leaf lines are not expandable");
    }

    #[test]
    fn collapsed_nodes_hide_their_subtree() {
        let mut collapsed = HashSet::new();
        collapsed.insert(2);
        let rows = flatten_tree(&sample(), &collapsed);
        let order: Vec<usize> = rows.iter().map(|r| r.node).collect();
        assert_eq!(order, vec![0, 2, 1, 4]);
        assert!(rows[1].expandable && !rows[1].expanded);
    }

    #[test]
    fn panel_navigation_and_jump() {
        use turbo_vision::core::event::{Event, KB_DOWN, KB_ENTER, KB_LEFT};
        use turbo_vision::core::geometry::Rect;
        let mut panel = ProfilePanel::new(Rect::new(0, 0, 40, 10));
        panel.set_profile(Some(sample()));
        assert_eq!(panel.selected_line(), Some(1), "program row selected first");
        panel.handle_event(&mut Event::keyboard(KB_DOWN));
        assert_eq!(panel.selected_line(), Some(3), "Work row");
        panel.handle_event(&mut Event::keyboard(KB_LEFT));
        assert_eq!(panel.row_count(), 4, "Work collapsed");
        panel.handle_event(&mut Event::keyboard(KB_ENTER));
        assert_eq!(panel.take_pending_jump(), Some(3));
        assert_eq!(panel.take_pending_jump(), None);
    }
}
```

Add `pub mod profile_window;` to `bruto-ide/src/lib.rs`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-ide profile_window 2>&1 | grep -E "^error" | head -3`
Expected: `cannot find function flatten_tree`.

- [ ] **Step 3: Implement the panel**

Insert above the tests in `bruto-ide/src/profile_window.rs`:

```rust
use std::collections::HashSet;

use bruto_lang::profile::{Profile, ProfileKind};
use turbo_vision::core::draw::DrawBuffer;
use turbo_vision::core::event::{
    Event, EventType, KB_DOWN, KB_ENTER, KB_LEFT, KB_RIGHT, KB_UP, MB_LEFT_BUTTON,
};
use turbo_vision::core::geometry::Rect;
use turbo_vision::core::palette::{Attr, TvColor};
use turbo_vision::core::state::Options;
use turbo_vision::terminal::Terminal;
use turbo_vision::views::view::{View, ViewCore, write_line_to_terminal};

const TEXT_ATTR: Attr = Attr::new(TvColor::Black, TvColor::LightGray);
const NUM_ATTR: Attr = Attr::new(TvColor::Blue, TvColor::LightGray);
const BG_ATTR: Attr = Attr::new(TvColor::Black, TvColor::LightGray);
const HL_TEXT_ATTR: Attr = Attr::new(TvColor::Black, TvColor::Green);
const HL_NUM_ATTR: Attr = Attr::new(TvColor::Blue, TvColor::Green);
const HL_BG_ATTR: Attr = Attr::new(TvColor::Black, TvColor::Green);

/// One visible row of the tree.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub node: usize,
    pub depth: usize,
    pub expandable: bool,
    pub expanded: bool,
}

/// Depth-first flattening of `profile` into display rows. Children are
/// sorted by total time, descending; nodes in `collapsed` hide their
/// subtree.
pub fn flatten_tree(profile: &Profile, collapsed: &HashSet<usize>) -> Vec<Row> {
    let n = profile.nodes.len();
    let mut children: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut roots: Vec<usize> = Vec::new();
    for (i, node) in profile.nodes.iter().enumerate() {
        match node.parent {
            Some(p) if p < n => children[p].push(i),
            _ => roots.push(i),
        }
    }
    let by_total = |a: &usize, b: &usize| profile.nodes[*b].total_ns.cmp(&profile.nodes[*a].total_ns);
    roots.sort_by(by_total);
    for c in &mut children {
        c.sort_by(by_total);
    }

    let mut rows = Vec::new();
    let mut stack: Vec<(usize, usize)> = roots.iter().rev().map(|&r| (r, 0)).collect();
    while let Some((idx, depth)) = stack.pop() {
        let expandable = !children[idx].is_empty();
        let expanded = expandable && !collapsed.contains(&idx);
        rows.push(Row { node: idx, depth, expandable, expanded });
        if expanded {
            for &c in children[idx].iter().rev() {
                stack.push((c, depth + 1));
            }
        }
    }
    rows
}

fn fmt_ns(ns: u64) -> String {
    if ns >= 1_000_000_000 {
        format!("{:.2}s", ns as f64 / 1e9)
    } else if ns >= 1_000_000 {
        format!("{:.1}ms", ns as f64 / 1e6)
    } else if ns >= 1_000 {
        format!("{:.1}µs", ns as f64 / 1e3)
    } else {
        format!("{ns}ns")
    }
}

pub struct ProfilePanel {
    core: ViewCore,
    profile: Option<Profile>,
    collapsed: HashSet<usize>,
    rows: Vec<Row>,
    selected: usize,
    top: usize,
    pending_jump: Option<usize>,
}

impl ProfilePanel {
    pub fn new(bounds: Rect) -> Self {
        let mut core = ViewCore::new(bounds);
        core.options |= Options::SELECTABLE;
        Self {
            core,
            profile: None,
            collapsed: HashSet::new(),
            rows: Vec::new(),
            selected: 0,
            top: 0,
            pending_jump: None,
        }
    }

    pub fn set_profile(&mut self, p: Option<Profile>) {
        self.profile = p;
        self.collapsed.clear();
        self.selected = 0;
        self.top = 0;
        self.rebuild();
    }

    pub fn clear(&mut self) {
        self.set_profile(None);
    }

    pub fn row_count(&self) -> usize {
        self.rows.len()
    }

    /// Source line of the selected row, if any.
    pub fn selected_line(&self) -> Option<usize> {
        let p = self.profile.as_ref()?;
        let row = self.rows.get(self.selected)?;
        Some(p.nodes[row.node].line)
    }

    /// Drain the latest jump request (a 1-based source line).
    pub fn take_pending_jump(&mut self) -> Option<usize> {
        self.pending_jump.take()
    }

    fn rebuild(&mut self) {
        self.rows = match &self.profile {
            Some(p) => flatten_tree(p, &self.collapsed),
            None => Vec::new(),
        };
        if self.selected >= self.rows.len() {
            self.selected = self.rows.len().saturating_sub(1);
        }
    }

    fn toggle_selected(&mut self, expand: bool) {
        let Some(row) = self.rows.get(self.selected).cloned() else {
            return;
        };
        if !row.expandable {
            return;
        }
        if expand {
            self.collapsed.remove(&row.node);
        } else {
            self.collapsed.insert(row.node);
        }
        self.rebuild();
    }

    fn ensure_visible(&mut self) {
        let h = self.extent().height_clamped() as usize;
        if h == 0 {
            return;
        }
        if self.selected < self.top {
            self.top = self.selected;
        } else if self.selected >= self.top + h {
            self.top = self.selected + 1 - h;
        }
    }

    fn request_jump(&mut self) {
        if let Some(line) = self.selected_line() {
            self.pending_jump = Some(line);
        }
    }
}

impl View for ProfilePanel {
    fn core(&self) -> &ViewCore {
        &self.core
    }
    fn core_mut(&mut self) -> &mut ViewCore {
        &mut self.core
    }
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
    fn as_any_mut(&mut self) -> &mut dyn std::any::Any {
        self
    }

    fn draw(&mut self, terminal: &mut Terminal) {
        self.ensure_visible();
        let extent = self.extent();
        let width = extent.width_clamped() as usize;
        let height = extent.height_clamped() as usize;
        let total = self.profile.as_ref().map(|p| p.elapsed_ns.max(1)).unwrap_or(1);

        for r in 0..height {
            let mut buf = DrawBuffer::new(width);
            let idx = self.top + r;
            let Some(row) = self.rows.get(idx) else {
                buf.move_char(0, ' ', BG_ATTR, width);
                if r == 0 && self.rows.is_empty() {
                    buf.move_str(0, "No profile yet. Use Build > Profile.", TEXT_ATTR);
                }
                write_line_to_terminal(terminal, 0, r as i16, &buf);
                continue;
            };
            let p = self.profile.as_ref().unwrap();
            let node = &p.nodes[row.node];
            let selected = idx == self.selected;
            let (bg, text, num) = if selected {
                (HL_BG_ATTR, HL_TEXT_ATTR, HL_NUM_ATTR)
            } else {
                (BG_ATTR, TEXT_ATTR, NUM_ATTR)
            };
            buf.move_char(0, ' ', bg, width);

            let marker = if row.expandable {
                if row.expanded { "▾ " } else { "▸ " }
            } else {
                "  "
            };
            let label = match node.kind {
                ProfileKind::Routine => node.name.clone(),
                ProfileKind::Line => format!("line {}", node.line),
            };
            let left = format!("{}{}{}", " ".repeat(row.depth * 2), marker, label);
            buf.move_str(0, &left, text);

            let pct = node.total_ns as f64 * 100.0 / total as f64;
            let right = format!(
                "{pct:5.1}%  {:>8}  {:>8}  {:>6}",
                fmt_ns(node.total_ns),
                fmt_ns(node.self_ns),
                node.calls
            );
            let rlen = right.chars().count();
            if rlen + 1 < width {
                buf.move_str(width - rlen, &right, num);
            }
            write_line_to_terminal(terminal, 0, r as i16, &buf);
        }
    }

    fn handle_event(&mut self, event: &mut Event) {
        match event.what {
            EventType::Keyboard => {
                match event.key_code {
                    KB_UP => {
                        self.selected = self.selected.saturating_sub(1);
                    }
                    KB_DOWN => {
                        if self.selected + 1 < self.rows.len() {
                            self.selected += 1;
                        }
                    }
                    KB_RIGHT => self.toggle_selected(true),
                    KB_LEFT => self.toggle_selected(false),
                    KB_ENTER => self.request_jump(),
                    _ => return,
                }
                event.clear();
            }
            EventType::MouseDown if event.mouse.buttons & MB_LEFT_BUTTON != 0 => {
                if self.extent().contains(event.mouse.pos) {
                    let idx = self.top + event.mouse.pos.y as usize;
                    if idx < self.rows.len() {
                        self.selected = idx;
                        if event.mouse.double_click {
                            self.request_jump();
                        }
                        event.clear();
                    }
                }
            }
            _ => {}
        }
    }

    fn can_focus(&self) -> bool {
        true
    }

    fn get_palette(&self) -> Option<turbo_vision::core::palette::Palette> {
        None
    }
}
```

The `KB_ENTER` case delivers the jump; Space is intentionally not bound (the spec listed it as an alternative; Enter plus double-click covers it and avoids swallowing a printable key).

- [ ] **Step 4: Run tests to verify they pass**

Run: `LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-ide profile_window 2>&1 | grep -E "^test result|FAILED|panicked"`
Expected: `3 passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-ide
rustfmt --edition 2024 src/profile_window.rs src/lib.rs
git add src/profile_window.rs src/lib.rs
git commit --no-verify -m "feat: ProfilePanel call-tree window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Wire the Profile command, window and menus into the IDE

**Files:**
- Modify: `bruto-ide/src/ide.rs`
- Modify: `CHANGELOG.md` (parent repo)

**Interfaces:**
- Consumes: `CM_PROFILE`, `CM_SHOW_PROFILE`, `CM_TOGGLE_PROFILE_COLUMN`; `ProfilePanel`; `LineProfile`, `text_hash`; `Language::profile_job_at`, `load_profile`; `IdeEditorWindow::set_line_profile/has_line_profile/profile_column_visible/set_profile_column_visible`.

- [ ] **Step 1: State and imports**

In `bruto-ide/src/ide.rs` imports add:

```rust
use crate::heat::{LineProfile, text_hash};
use crate::profile_window::ProfilePanel;
```

Add to `IdeState`:

```rust
    /// Layout used to (re-)spawn the Profile window.
    profile_bounds: Rect,
    /// `Some(id)` while the Profile window is on the desktop.
    profile_win_id: Option<turbo_vision::views::view::ViewId>,
    /// Shared Profile model — survives close/re-open.
    profile_panel: Rc<RefCell<ProfilePanel>>,
    /// Editor whose buffer the last profile run measured; jumps from the
    /// Profile window land here.
    profile_editor: Option<Rc<RefCell<IdeEditorWindow>>>,
```

In `run_with_options`, after the call stack panel is created:

```rust
    // ── Profile window (hidden at start). Same slot as the call stack;
    // the user can drag either once shown.
    let profile_bounds = callstack_bounds;
    let profile_panel = Rc::new(RefCell::new(ProfilePanel::new(Rect::new(
        0,
        0,
        profile_bounds.width() - 2,
        profile_bounds.height() - 2,
    ))));
```

and in the `IdeState { .. }` literal:

```rust
        profile_bounds,
        profile_win_id: None,
        profile_panel: Rc::clone(&profile_panel),
        profile_editor: None,
```

- [ ] **Step 2: Window install helper**

After `install_callstack_window`, add:

```rust
/// Wrap a fresh "Profile" `Window` around the shared [`ProfilePanel`] and
/// add it to the desktop. Mirrors [`install_callstack_window`].
fn install_profile_window(
    app: &mut Application,
    bounds: Rect,
    panel: &Rc<RefCell<ProfilePanel>>,
) -> turbo_vision::views::view::ViewId {
    let interior_w = bounds.width() - 2;
    let interior_h = bounds.height() - 2;
    panel
        .borrow_mut()
        .set_bounds(Rect::new(0, 0, interior_w, interior_h));

    let mut win = turbo_vision::views::window::Window::new_with_type(
        bounds,
        "Profile",
        turbo_vision::views::window::WindowPaletteType::Gray,
    );
    win.add(Shared::new(Rc::clone(panel)));
    win.set_state_flag(State::SHADOW, false);
    app.desktop.add(win)
}
```

- [ ] **Step 3: Event loop hooks**

In the main loop, next to the `callstack_win_id` presence check, add:

```rust
                if let Some(id) = ide.profile_win_id
                    && !app.desktop.contains_id(id)
                {
                    ide.profile_win_id = None;
                }
```

Next to the `pending_jump` handling for the call stack, add:

```rust
                let profile_jump = profile_panel.borrow_mut().take_pending_jump();
                if let Some(line) = profile_jump {
                    handle_profile_jump(&mut app, &mut ide, line);
                }
```

In the keyboard pre-dispatch `match event.key_code`, change the `KB_F9` arm to distinguish Shift:

```rust
                        KB_F9 => {
                            let shift = event
                                .key_modifiers
                                .contains(crossterm::event::KeyModifiers::SHIFT);
                            event = Event::command(if shift { CM_PROFILE } else { CM_BUILD });
                        }
```

turbo-vision does not re-export `KeyModifiers`, so add the same crossterm version it uses to `bruto-ide/Cargo.toml` under `[dependencies]`:

```toml
crossterm = "0.29"
```

- [ ] **Step 4: Command handlers**

In `handle_command`, add arms:

```rust
        CM_PROFILE => {
            handle_profile(app, language, &mut output_rc.borrow_mut(), ide);
            true
        }
        CM_SHOW_PROFILE => {
            if ide.profile_win_id.is_none() {
                let id = install_profile_window(app, ide.profile_bounds, &ide.profile_panel);
                ide.profile_win_id = Some(id);
            }
            true
        }
        CM_TOGGLE_PROFILE_COLUMN => {
            if let Some(ed) = focused_editor(app) {
                let mut ed = ed.borrow_mut();
                let on = ed.profile_column_visible();
                ed.set_profile_column_visible(!on);
            }
            true
        }
```

In `handle_build`, right after `editor.borrow_mut().set_build_error(None);` add:

```rust
    // A new build makes the last profile stale.
    editor.borrow_mut().set_line_profile(None);
```

Add the profile handler after `handle_run`:

```rust
/// Build with instrumentation, run to completion, then load the profile
/// into the editor's heat column and the Profile window.
fn handle_profile(
    app: &mut Application,
    language: &Box<dyn Language>,
    output: &mut TerminalWidget,
    ide: &mut IdeState,
) {
    let Some(editor) = focused_editor(app) else {
        append_output_line(
            output,
            "No active editor — open or create a file first.",
            Some(CONSOLE_INFO),
        );
        return;
    };
    if ide.debugger.is_running() {
        append_output_line(output, "Stop the debugger before profiling.", Some(CONSOLE_INFO));
        return;
    }
    let source = editor.borrow().editor_rc().borrow().get_text();
    let file_path = editor.borrow().file_path().map(std::path::PathBuf::from);
    output.clear();
    append_output_line(output, "Building with profiler...", Some(CONSOLE_INFO));
    editor.borrow_mut().set_build_error(None);
    editor.borrow_mut().set_line_profile(None);

    let job = language.profile_job_at(&source, file_path.as_deref());
    let result = match run_build_with_progress(app, job) {
        Some(Ok(r)) => r,
        Some(Err(e)) => {
            if let Some(line) = extract_error_line(&e) {
                editor.borrow_mut().set_build_error(Some((line, e.clone())));
            }
            append_output_line(output, &format!("Build error: {e}"), Some(ERROR));
            use turbo_vision::views::msgbox::message_box_error;
            message_box_error(app, &e);
            return;
        }
        None => {
            append_output_line(output, "Build cancelled.", Some(CONSOLE_INFO));
            return;
        }
    };

    let Some(prof_path) = result.profile_path.clone() else {
        append_output_line(output, "Profiling is not available for this language.", Some(ERROR));
        return;
    };
    let _ = std::fs::remove_file(&prof_path);
    append_output_line(output, &format!("Running {} (profiled)...", result.exe_path), Some(CONSOLE_INFO));
    let capture = Some(result.console_capture_path.clone());
    if let Some(c) = &capture {
        let _ = std::fs::write(c, "");
    }
    let status = std::process::Command::new(&result.exe_path)
        .env("BRUTO_PROF_OUT", &prof_path)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    if let Some(c) = &capture
        && let Ok(contents) = std::fs::read_to_string(c)
    {
        for line in contents.lines() {
            output.append_line_colored(line.to_string(), OUTPUT_TEXT);
        }
    }
    let code = match status {
        Ok(s) => s.code().unwrap_or(-1),
        Err(e) => {
            output.append_line_colored(format!("Failed to run: {e}"), CONSOLE_ERR);
            return;
        }
    };
    if !std::path::Path::new(&prof_path).exists() {
        output.append_line_colored(
            format!("Program exited with code {code}; no profile written"),
            ERROR,
        );
        return;
    }
    output.append_line_colored(format!("Exit code: {code}"), if code == 0 { SUCCESS } else { ERROR });

    let profile = match language.load_profile(&result) {
        Ok(p) => p,
        Err(e) => {
            use turbo_vision::views::msgbox::message_box_error;
            message_box_error(app, &format!("Could not read profile:\n{e}"));
            return;
        }
    };
    if profile.truncated {
        output.append_line_colored(
            "Warning: profile truncated (too many call sites or recursion too deep)".to_string(),
            CONSOLE_INFO,
        );
    }
    output.append_line_colored(
        format!("Profile: {} nodes, {:.1} ms total", profile.nodes.len(), profile.elapsed_ns as f64 / 1e6),
        SUCCESS,
    );

    editor.borrow_mut().set_line_profile(Some(LineProfile {
        lines: profile.line_totals(),
        total_ns: profile.elapsed_ns.max(1),
        visible: true,
        text_hash: text_hash(&source),
    }));
    ide.profile_editor = Some(Rc::clone(&editor));
    ide.profile_panel.borrow_mut().set_profile(Some(profile));
    if ide.profile_win_id.is_none() {
        let id = install_profile_window(app, ide.profile_bounds, &ide.profile_panel);
        ide.profile_win_id = Some(id);
    }
}

/// Scroll the profiled editor to `line` (1-based) and focus it.
fn handle_profile_jump(app: &mut Application, ide: &mut IdeState, line: usize) {
    let Some(editor) = ide.profile_editor.clone() else {
        return;
    };
    for i in 0..app.desktop.child_count() {
        let is_target = app
            .desktop
            .child_at(i)
            .as_any()
            .downcast_ref::<SharedIdeEditorWindow>()
            .is_some_and(|s| Rc::ptr_eq(s.inner(), &editor));
        app.desktop.child_at_mut(i).set_focus(is_target);
    }
    editor
        .borrow()
        .editor_rc()
        .borrow_mut()
        .scroll_to_line(line.saturating_sub(1));
}
```

- [ ] **Step 5: Command states, menus, status line**

In `update_command_states`, add after `let callstack_open = ...`:

```rust
    let profile_open = ide.profile_win_id.is_some();
    let has_profile = focused.as_ref().is_some_and(|e| e.borrow().has_line_profile());
```

and after the existing toggles:

```rust
    toggle(CM_PROFILE, editor_focused && !dbg_running);
    toggle(CM_SHOW_PROFILE, !profile_open);
    toggle(CM_TOGGLE_PROFILE_COLUMN, has_profile);
```

In `build_menu_bar`, the build menu becomes:

```rust
    let build_menu = Menu::from_items(vec![
        item("~B~uild", CM_BUILD, KB_F9, "F9"),
        item("~R~un", CM_RUN, 0, "Ctrl-F9"),
        item("~P~rofile", CM_PROFILE, 0, "Shift-F9"),
    ]);
```

and the window menu gains two entries:

```rust
        item("~P~rofile", CM_SHOW_PROFILE, 0, ""),
        item("Profile Colu~m~n", CM_TOGGLE_PROFILE_COLUMN, 0, ""),
```

(`item` with key 0 is display-only; Shift-F9 is dispatched by the loop change in Step 3.)

- [ ] **Step 6: Build, clippy on touched crate, tests**

Run:
```bash
cd /Users/enzo/Code/bruto-pascal
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo build 2>&1 | grep -E "^(error|warning: unused)"
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo test -p bruto-ide 2>&1 | grep -E "^test result|FAILED"
LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 cargo clippy -p bruto-ide 2>&1 | grep -E "^error" | grep -c "profile_window\|heat\.rs\|handle_profile" 
```
Expected: no build errors, `30 passed`, and `0` clippy findings in the new code (pre-existing findings elsewhere are expected and out of scope).

- [ ] **Step 7: Manual verification in the real IDE**

```bash
cd /Users/enzo/Code/bruto-pascal && LLVM_SYS_181_PREFIX=/opt/homebrew/opt/llvm@18 ./target/debug/brutop
```

1. F3, open `demo.pas`.
2. Build > Profile. Expect the progress dialog to show "Compiling profiler runtime…" then "Linking…", the Output panel to show the program output and a green "Profile: N nodes" line, and a Profile window with `program` expanded and `Double` beneath it.
3. The editor shows a 7-column percentage column after the gutter; the `for` loop body rows are tinted.
4. Down/Enter in the Profile window scrolls the editor to that line.
5. Type a character in the editor: the column disappears immediately.
6. Build > Profile again, then F9: the column disappears (stale on build).
7. Windows > Profile Column toggles the column while data exists and is greyed out otherwise.
8. Alt-X to exit.

If anything fails, fix it in the file responsible (Task 5 for the column, Task 6 for the window, this task for wiring) and re-run the crate tests before committing.

- [ ] **Step 8: Changelog and commits**

Add under `## [Unreleased]` in `/Users/enzo/Code/bruto-pascal/CHANGELOG.md`, in a `### Added` section (create it above the existing `### Changed`):

```markdown
### Added
- **Line profiler.** `Build > Profile` (Shift-F9) compiles the program with
  timing hooks on every routine and statement, links a small C runtime,
  runs it, and shows the results two ways: a percentage column with heat
  tinting beside the gutter, and a Profile window with a collapsible
  routine > line call tree (Enter or double-click jumps to the line). The
  column appears only after a profile run and clears on the next build or
  edit. Normal builds are unaffected.
```

Commits:

```bash
cd /Users/enzo/Code/bruto-pascal/bruto-ide
rustfmt --edition 2024 src/ide.rs
git add src/ide.rs Cargo.toml
git commit --no-verify -m "feat: Build > Profile command, Profile window wiring, profile column toggle

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"

cd /Users/enzo/Code/bruto-pascal
git add CHANGELOG.md Cargo.lock bruto-ide bruto-lang bruto-pascal-lang
git commit --no-verify -m "feat: line profiler (Build > Profile) with heat column and Profile window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
