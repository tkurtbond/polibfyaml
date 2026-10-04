# AGENTS.md

Oberon-2 binding to libfyaml's core parser/emitter/document API,
compiled with poc, the Peaseblossom Oberon Compiler. It is a port of
olibfyaml (`~/Repos/Oberon/olibfyaml`), the same binding for Vishap
Oberon (`voc`), and keeps its API, tests, examples and benchmarks; only
the parts that depend on the compiler differ (see "What the port
changed"). PLAN.md is olibfyaml's design and roadmap, with a section on
the port; this file is operational notes for an agent working in this
repo, not a design doc.

olibfyaml is in turn a port of the Ada binding in `~/Repos/Ada/alibfyaml`
(and borrows from the Chicken Scheme binding in
`~/Repos/Scheme/Chicken/5/slibfyaml`). Read their `AGENTS.md`/`PLAN.md`
before redesigning anything: most of their text is hard-won, confirmed
behavior of libfyaml itself, and applies here unchanged. Keep this repo
and olibfyaml in step: a change to the API or to a test belongs in both.

## Reference material

| What | Where |
|---|---|
| libfyaml source (v1.0.0-beta1) | `/usr/local/sw/src/lang/C/libfyaml/` (`include/libfyaml.h`, `src/lib/`) |
| Installed libfyaml | system package `libfyaml-devel-0.8-9.fc44`; `/usr/include/libfyaml.h`, `pkg-config --libs libfyaml` = `-lfyaml` |
| poc | installed from the Peaseblossom RPM: `/usr/bin/poc`, its runtime library `poc-rtl` under `/usr/lib/poc`; `poc(1)`, `/usr/share/doc/peaseblossom/` |
| poc source | `~/Repos/Oberon/Peaseblossom` (`doc/users-guide.md`, `doc/reference-guide.md`, `doc/language-extensions.md`; the runtime in `rtl/llvm/`) |
| olibfyaml (voc) | `~/Repos/Oberon/olibfyaml/` |
| Oberon-2 report | `~/Reference/Computer/Languages/Oberon/Oberon2.pdf`; plain text: `Oberon2-layout.text` and `Oberon2-no-layout.text` |
| Ada binding | `~/Repos/Ada/alibfyaml/` |
| Scheme binding | `~/Repos/Scheme/Chicken/5/slibfyaml/` |

As with alibfyaml: the system package's `0.8` version label is
misleading. It already exposes the 1.0-beta1 API. Confirm a symbol
before assuming it's missing, e.g.
`nm -D $(pkg-config --variable=libdir libfyaml)/libfyaml.so | grep fy_document_build_from_string`.

## Build

Use the `Makefile`; it runs `poc` from `PATH` (`make POC=/path/to/poc`
for another, e.g. `~/Repos/Oberon/Peaseblossom/build/bin/poc`):

```sh
make            # test programs and examples, into build/
make test       # every test (from test/), halt test, and example (from examples/)
make valgrind   # the test programs, each under valgrind
make bench      # benchmarks (bench/); not part of `make` or `make test`
make clean      # rm -rf build
```

What it wraps: poc builds a program from its main module's source,
finding the modules it imports on the import path (`-import-path src`,
plus `test` or `bench`), and compiles every one of them again on each
build, so there is no import order to keep and no per-module rule: a
new library module needs only adding to `LIBSRC` (for the dependency),
a new test only its name in `TESTS`. **`src/FyThin.c`, beside
`FyThin.Mod`, is compiled with clang and linked as FyThin's part in C**
whenever FyThin is compiled. `pkg-config --cflags libfyaml` reaches
that compile through `-c-flag`, and `--libs` the link through `-link`.
Output (`.sym`, `.ll`, `.o`, `FyThin.c.o`, the programs) goes into
`build/` (`-output-dir`). Each program rewrites the library modules'
files there, so the Makefile is `.NOTPARALLEL`. Add `-verbose` to a poc
command to see the clang commands it runs.

Integer size model: **build every module with `-OC`**, as olibfyaml
does (PLAN.md, "Integer model"): `SHORTINT`/`INTEGER`/`LONGINT` are
16/32/64 bits, `SET` 32. Code using the binding must be compiled with
`-OC` too; a `.sym` from one model is refused under the other. In
`FyThin`, write the explicit-size types (`SYSTEM.INT32` for `int` and
enums, `SYSTEM.ADDRESS` for pointers and `size_t`) so every C-boundary
signature says what it means whatever the model; the thick layer
(`Fyaml`, `FyamlStreams`) uses plain `INTEGER`/`LONGINT`.

## Test

Each test is its own main module in `test/` (`TestThin`,
`TestParseErrors`, `TestQuickstart`, `TestNavigate`, `TestPath`,
`TestLiveness`, `TestBuild`, `TestMutate`, `TestScalars`,
`TestAnchors`, `TestLocation`, `TestStreams`, `TestStdin`,
`TestStdinError`, `TestStdinStream`), printing `ok   - <label>` / `FAIL - <label>` per check through the
shared `test/Check.Mod`, and ending with `All checks passed.` or
`<N> check(s) failed.` A failing run exits 1, so `make test` fails. To
judge a run, grep for `FAIL` or read the last line. **Adding a test
means adding its name to `TESTS` in the Makefile.** YAML fixtures go
in `test/` (tests run with `test/` as their working directory), the
same files as olibfyaml's.

**Stdin tests.** `make test` and `make valgrind` run each test with
stdin redirected from `test/<name>.stdin` if that file exists, else
from `/dev/null`. A process can read stdin only once, so each stdin
case (`TestStdin`, `TestStdinError`, `TestStdinStream`) is its own
program with its own `.stdin` file. To run one by hand, from `test/`:
`../build/TestStdin < TestStdin.stdin`.

**Halt tests.** A programmer error must halt with the right `Fyaml.Assert*`
code, and a program can't catch its own halt. So each such case is a
separate small main module, `test/Halt*.Mod` (`HaltClosed`,
`HaltKind`, `HaltIndex`, `HaltStale`, `HaltAttach`, `HaltAttached`,
`HaltTyped`, `HaltResolved`, `HaltStream`), listed in the Makefile's
`HALTTESTS` as `name:code`. **poc's `ASSERT(x, n)` does not exit with
`n`**: it prints `assertion failed (n)` on standard error and exits with
status 10 (voc exits with `n`), so `make test` requires status 10 and
that message, with the right code. A method call on a NIL pointer
prints `NIL pointer dereference` and exits with 4. poc refuses to
compile an `ASSERT` whose condition is a constant FALSE, so a probe
needs a condition that is false only at run time.

Expected stderr noise: libfyaml prints some failures itself,
bypassing the collected diagnostics. `ParseFile` and `OpenFile` check
for an unopenable file or a directory first, so those cases are quiet,
but a cyclic reference found while parsing with resolve on
(`TestAnchors`) prints `[ERR]: fy_parse_load_document() failed`, and so
does `TestStdin`. Neither is a test failure.

### Valgrind: necessary, but NOT sufficient here

Run anything that touches ownership or lifetime under

```sh
make valgrind
# or, for one test, from test/:
valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=99 --suppressions=poc-gc.supp --suppressions=libfyaml.supp ../build/TestWhatever
```

before calling it done, the same rule as alibfyaml. `libfyaml.supp`
covers one known bug in the installed libfyaml: `realloc(buf, 0)` on
empty stream input, which Memcheck reports as `ReallocZero` and which
doesn't leak (PLAN.md, "Standard input"). Keep its entries narrow, and
add one only after confirming the bug is in libfyaml. Two poc-specific
things to know when reading the output:

- **`test/poc-gc.supp` is required** for any program where a collection
  runs. poc's collector scans the machine stack conservatively, reading
  words that were never written: `TestLiveness` and `TestStreams` show
  20 and 24 "uninitialised value" errors, all "Conditional jump" in
  `GarbageCollectedHeap.MarkCandidate`. The file suppresses only that
  error kind, and only when that function is the top frame.
- **Check "still reachable", not just "definitely lost".** A libfyaml
  document that is never freed is pointed to from inside poc's heap,
  which stays reachable, so valgrind classifies the leak as "still
  reachable" rather than "definitely lost". The only expected
  still-reachable memory is the collector's own, which it never frees:
  its heap chunks (one of 262,160 bytes to start, more as the heap
  grows) and its tables (chunk index, finalizers, marking), 2 to 5
  blocks per test. Unlike voc's single fixed block, the total varies
  with the test, so `make valgrind` checks *who allocated* each
  still-reachable block instead: `test/vg-reachable.sh` requires the
  first frame after `malloc`/`calloc`/`realloc` to be in
  `GarbageCollectedHeap`, and prints any other record. As a control,
  disabling the orphan-node free at `Close` grew `TestBuild`'s
  still-reachable memory to 16 blocks with nothing "lost", and the
  script listed the libfyaml blocks (`fy_node_create_scalar_internal`,
  `fy_token_prepare_text`, ...).

**But valgrind cannot see one bug class, which olibfyaml hit in its
Phase 0 spike and which applies to poc unchanged:** a value `ARRAY OF
CHAR` parameter is copied into the procedure's frame on entry, which is
released when the procedure returns. A string handed to
`fy_document_build_from_string` this way leaves the document holding
zero-copy spans into a dead stack frame. `fy_node_get_scalar` then
silently returns garbage or empty text, and valgrind reports **0
errors**, because this is stack memory, not heap. The only defence is
design plus tests that check actual values (`TestThin`,
`TestLiveness`): never pass memory to libfyaml that doesn't outlive the
libfyaml object which may keep pointing into it. See PLAN.md, "Buffer
lifetime".

## Layout

- `src/FyThin.Mod`: low-level libfyaml calls. No ownership or error
  policy. `src/FyThin.c`: its part in C (below).
- `src/Fyaml.Mod`: `Document`, `Node`, `Error`, iterators (Phase 1);
  emit, build and mutate (Phase 2); typed scalar accessors and
  mapping fields (Phase 3); parse options, `Resolve`, aliases, tags,
  styles and locations (Phase 4).
- `src/FyamlStreams.Mod`: multi-document streams (Phase 5). It
  builds `Fyaml.Document`s through `Fyaml`'s exported "For
  FyamlStreams" hooks (`Adopt`, `DiagErrors`, `Unreadable`), which
  exist only because Oberon has no friend modules; keep other code
  off them.
- `Makefile`: build and test; see Build above.
- `test/`: one main module per concern, plus `Check.Mod`, the YAML
  fixtures, the valgrind suppressions and `vg-reachable.sh`.
- `examples/`: example programs with fixtures and `<name>.expected`
  output. `make test` requires each one's exit status (listed as
  `name:status` in the Makefile's `EXAMPLES`) and exact output, so a
  changed message fails there. `ExampleConfig` is the README's example;
  keep the README's copy in step with it. After changing an example
  or a message, check the new output by hand, then regenerate its
  `.expected` from the program.
- `bench/`: `BenchWide`, `BenchStreams`, the shared `Timing` module,
  alibfyaml's input generators, and `run_stats.sh`. `make bench`
  generates the (large) inputs into `build/`, prints checksums (which
  must match alibfyaml's: 55002038890 and 200158890), then 10-run
  timing stats (`RUNS=n` to change). Record numbers in PLAN.md when
  a change touches a hot path.
- `README.md`: the user-facing guide.
- `build/`: poc/clang output (gitignored).
- `PLAN.md`: design, decisions, confirmed findings, and open
  questions, organized by section. Append to the relevant section
  rather than starting a new document. Mark a finished section
  `[done]`, and strike through an open question once it's decided.

## What the port changed

Everything else is olibfyaml's code, unchanged.

- **`FyThin`**. voc binds C with "code procedures", inline C text
  expanded where they are called; poc has none. Instead:
  - A libfyaml or libc function that takes and returns only pointers,
    sizes and ints is an external procedure,
    `PROCEDURE ["C", "fy_document_root"] CDocumentRoot(fyd: Document): Node;`,
    wrapped in an exported Oberon procedure (see "poc 0.1.0 problems"
    for why the wrapper).
  - Everything else is in `src/FyThin.c`, compiled against the installed
    header: libfyaml's static inline helpers (`fy_node_is_mapping` and
    friends, `fy_node_is_alias`), `struct fy_parse_cfg` (built there),
    the fields of `struct fy_diag_error` and `struct fy_mark` (read
    there), enum and `#define` values (`FYNS_*`, `FYECF_*`,
    `FYNWF_DONT_FOLLOW`), C's `stdin`, `errno` and `fstat`. So, as in
    olibfyaml, **no C struct is mirrored as an Oberon record**. Its
    functions are named `FyThin.-<name>` (`__asm__` labels; `-` can't be
    in an Oberon name, as in poc's own `Platform.c`) and use only
    `int32_t` and `intptr_t`; a truth value is an `int32_t` 0 or 1,
    which `FyThin` turns into a `BOOLEAN` (`Truth`, `# 0`). Don't pass
    a `BOOLEAN` across: its C type is poc's business.
- **The runtime.** voc's `Heap` is poc's `GarbageCollectedHeap`
  (`RegisterFinalizer`; `Heap.GC(TRUE)` is `Collect`). `Modules.ArgCount`/
  `GetArg`, `Platform.Exit`/`GetTimeOfDay`, `Out` and `Strings` are
  voc's interfaces in poc's runtime too.
- **`SYSTEM.ADDRESS` is its own type** in poc, not `LONGINT`: an
  `ADDRESS` (a scalar's length) given to a `LONGINT` needs
  `SYSTEM.VAL(LONGINT, len)` (`Fyaml.ScalarLen`, `Fyaml.GetText`,
  `BenchWide.Len`).
- **Halt tests** check status 10 and the code in the message (Test,
  above).
- **`TestScalars`** builds one long document from pieces with
  `Strings.Append`: a poc string literal holds at most 255 characters
  (voc's 1024).
- **Valgrind**: `poc-gc.supp` in place of `voc-gc.supp`, and the
  still-reachable check by allocator (Valgrind, above).
- Comments that described voc's behavior now describe poc's.

## poc 0.1.0 problems

Found while porting (2026-10-03, poc 0.1.0 from the RPM, and the same
at Peaseblossom's HEAD then), worked around here; remove a workaround
once a released poc fixes its problem:

- **An exported external procedure can't be called from another
  module.** `FyThin.sym` keeps `PROCEDURE ["C", "fy_document_destroy"]
  DocumentDestroy*(...)` as plain `PROCEDURE^ DocumentDestroy*(...)`,
  so an importer calls `@FyThin.DocumentDestroy`, which nothing
  defines, and clang fails: "use of undefined value
  '@FyThin.DocumentDestroy'". Hence every external procedure here is
  unexported and wrapped.
- **`poc -check` uses the wrong word size**: under `-OC` on x86-64 it
  rejects `a := l` (`a: SYSTEM.ADDRESS; l: LONGINT`), "assignment is
  not type-compatible: LONGINT to SYSTEM.ADDRESS", which a real build
  (`-emit-llvm-ir`, or building a program) accepts. Build, don't
  `-check`.
- A string literal holds at most 255 characters (voc: 1024).

## poc / Oberon-2 facts this binding depends on (confirmed)

- **Oberon-2 has no call chaining.** A function call's result isn't a
  designator (report §8.1), so `d.Root().Value("k")` doesn't compile.
  Assign each step to a variable, or use `ByPath` to go several levels
  in one call.
- **libfyaml's `*_iterate` ends by resetting the cursor to NULL, which
  also means "start over".** A naive `Next` after the end silently
  restarts from the first item (confirmed live). `ItemIter`/`PairIter`
  keep a `done` flag for this reason.
- **`*)` ends a comment anywhere inside it**, including in text like
  `fy_node_is_*)`. Write "and friends" rather than a C wildcard ending
  in `*` before a `)`.
- **`(*` inside a comment opens a nested one** (Oberon comments
  nest), so text like "an alias (*name)" swallows the rest of the
  module. Quote it: `("*name")`.
- **`ORD` takes a `CHAR` or a `SET`, not a `BOOLEAN`** (the report's
  rule, which poc enforces): `FyThin.Truth` turns one into C's 0 or 1.
- **poc's GC** (`GarbageCollectedHeap`) is non-moving mark-sweep. It
  scans the stack conservatively and module globals precisely, and
  **cannot see pointers stored only in C memory**. Anything libfyaml
  points into must also be reachable from an Oberon pointer, e.g. a
  field of the owning `Document`.
- **Finalizers**: `GarbageCollectedHeap.RegisterFinalizer(obj, proc)`.
  After marking, each unreachable finalizable object is marked again
  *with everything it references*, so a `Document`'s buffer field is
  still valid while that `Document`'s finalizer runs. Every pending or
  registered finalizer also runs when the program ends - returning
  from the main module, `HALT`, `ASSERT`, a trap or `Platform.Exit`
  (voc skips them at `Platform.Exit`) - so valgrind's end-of-run leak
  report is meaningful on every path. The GC only runs on Oberon
  allocation and cannot see libfyaml's C-side memory pressure, which
  is why explicit `Close` is the primary cleanup path and finalizers
  are only a backstop.
- **Real literals are `REAL` unless suffixed `D`**: `1234.56` is a
  32-bit `REAL` and never equals the `LONGREAL` 1234.56, but
  `1234.56D0` does, bit for bit with glibc's `strtod`. Write `D`
  literals when comparing `LONGREAL` results.
- **poc's `Out` writes at once**: it buffers nothing, and `Out.Flush`
  does nothing. olibfyaml's `Out.Flush` before `Platform.Exit` (voc
  buffers) is kept, harmless.
- **Don't depend on argument evaluation order**: olibfyaml's rule
  (voc compiles to C, where it is unspecified) is kept, so
  `Report(Fyaml.ParseFile(p, err), err)` stays forbidden; assign the
  result first.
- **Allocation is what makes Oberon programs slow here.** Each
  collection scans the whole stack and marks the heap. On hot paths
  inside the binding, don't allocate objects the caller never sees:
  use `FyThin` handles rather than `Node`s, and stack buffers rather
  than `String`s (see `Fyaml.GetText`). PLAN.md, Phase 6, has
  olibfyaml's measurements; the port's are within a few percent of
  them (PLAN.md, "Port to poc").
- **Oberon-2 has no exceptions**, no generics, no closures, and
  function procedures can't return arrays or records. That shapes the
  API: results come back as `BOOLEAN` plus `VAR` out parameters or
  an error object, strings are `POINTER TO ARRAY OF CHAR`, and
  iteration uses explicit iterator records. See PLAN.md.
  `ASSERT`/`HALT` end the program, so reserve them for programmer
  errors (a closed document, a NIL node), never for bad input data.

## Conventions

- **Comments explain *why*, and only claim what has been verified.**
  Where a comment or a decision depends on how libfyaml or poc
  actually behaves, test it: write a throwaway program in the
  scratchpad, run it (under valgrind if lifetime is in question, and
  check the actual *values* too, per the buffer-lifetime note above),
  then write the result down as a confirmed fact. libfyaml's header
  comments have been wrong or misleading several times (see
  alibfyaml's PLAN.md: `fy_node_get_path` on the root, the
  `fy_document_insert_at` unref, the `fy_parser_set_input_file`
  filename lifetime).
- **Bind only what the thick layer calls.** Before adding a new entry
  point to `FyThin`, confirm it exists (in the header for inline
  helpers, which go in `FyThin.c`, or with `nm -D` for exported
  symbols, which can be external procedures).
- **Document what every mutating operation does to each
  `Node`/`Document` argument, on success and on failure.** libfyaml
  itself can consume or invalidate handles; `fy_document_insert_at`
  always unrefs its node, whatever the outcome, and `fy_node_insert`/
  `fy_document_set_root` free the nodes they replace. That's why
  `InsertAt`, `Resolve` and a replacing `SetRoot` bump the document's
  generation count and so kill every earlier Node (see PLAN.md, "Node
  validity"); a new mutating call that can free nodes must do the
  same. A node made by `Create*` must go through the orphan list
  (`AddOrphan`/`DropOrphan`), since `fy_document_destroy` doesn't
  free unattached nodes.
- **Cleanup must be idempotent.** An explicit `Close` and the GC
  finalizer can both run on the same object, so `Close` must set the
  handle to 0 before or when it frees, and do nothing if it's already
  0. That rules out double frees.
- Record decisions and findings in PLAN.md as they happen, the same
  way alibfyaml does.
