# polibfyaml - an Oberon binding to libfyaml for poc

An Oberon-2 binding to [libfyaml](https://github.com/pantoniou/libfyaml),
the YAML 1.2 parser and emitter, for poc, the
[Peaseblossom](https://github.com/tkurtbond/peaseblossom) Oberon compiler.
It is a port of olibfyaml, the same binding for the
[Vishap Oberon](https://github.com/vishapoberon/compiler) compiler
(`voc`), with the same API, tests and examples; olibfyaml is in turn a
port of the Ada binding alibfyaml, adapted to a garbage-collected
language without exceptions.

It covers parsing (strings, files, standard input, multi-document
streams), navigation,
typed values with YAML 1.2 core-schema resolution, building and changing
documents, emitting YAML or JSON, anchors and aliases, tags, styles, and
source locations. Errors in the input come back as values with
gcc-style messages (`file:line:column: error: text`); programming
mistakes halt the program with a failed `ASSERT` naming a distinct code.

## Requirements

- poc 0.1.0 or later, with its runtime library (`poc-rtl`), on `PATH`;
  override with `make POC=/path/to/poc`.
- clang, which poc runs.
- libfyaml with its header, found through `pkg-config libfyaml`.
- Optional: valgrind (`make valgrind`), python3 and perf (`make bench`).

## Building and testing

```sh
make            # the tests and examples, into build/
make test       # every test, halt test and example
make valgrind   # the tests under valgrind, with strict leak checks
make bench      # benchmarks; see bench/
make clean
```

## Using it

**Compile everything with `-OC`.** Under `-OC`, `INTEGER` is 32 bits,
`LONGINT` 64, and `SET` 32, the sizes the binding's thick layer was
written for (its C boundary uses explicit sizes). Symbol files differ
between poc's size models, so a program using this binding must be
compiled with `-OC` too.

Give poc your main module, with `src/` on the import path; it finds and
compiles `Fyaml`, `FyamlStreams` and `FyThin` there, and `FyThin.c`
beside `FyThin.Mod` (`FyThin`'s part in C). Pass it libfyaml's flags:

```sh
poc -OC -import-path polibfyaml/src -output-dir build \
    $(for f in $(pkg-config --cflags libfyaml); do echo -c-flag $f; done) \
    $(for f in $(pkg-config --libs libfyaml); do echo -link $f; done) \
    -o MyProgram MyProgram.Mod
```

(On Linux `pkg-config --cflags` is empty and `--libs` is `-lfyaml`, so
`-link -lfyaml` is enough.)

Or install it once as a poc library and link it compiled: `make install`
builds the library `polibfyaml` (under `-OC`, with `FyThin.c`'s object
in it) in `polibfyaml/` under `POC_OBERON_LIBRARIES` (default `/usr/local/sw/versions/oberon/poc/lib`).
A program then needs no sources and no `-c-flag`, only the library
path and libfyaml's link flags:

```sh
poc -OC -library-path /usr/local/sw/versions/oberon/poc/lib/polibfyaml \
    -link -lfyaml -o MyProgram MyProgram.Mod
```

A library records the poc that built it, and another poc refuses it:
run `make install` again after upgrading poc. `make uninstall` removes
it.

Modules: `Fyaml` is the API; `FyamlStreams` reads several `---`
separated documents from one input; `FyThin` is the raw libfyaml layer
underneath, not meant for direct use.

## Example

This is `examples/ExampleConfig.Mod`, which `make test` builds and runs
against its expected output:

```oberon
MODULE ExampleConfig; (* The README's example: read, check, change, emit *)

(* Reads config.yaml, takes typed values from it with gcc-style error
   reports, changes a setting, and prints the result. Built and run by
   `make test`, so the README's copy of it stays correct.

   Run: ExampleConfig [file]   (default config.yaml) *)

IMPORT Modules, Out, Fyaml;

PROCEDURE Run;
  VAR path: ARRAY 256 OF CHAR;
    d: Fyaml.Document; err: Fyaml.Error;
    root, server, origins, origin, patch: Fyaml.Node; it: Fyaml.ItemIter;
    host, text, yaml: Fyaml.String; port, timeout: INTEGER; ssl: BOOLEAN;
BEGIN
  path := "config.yaml";
  IF Modules.ArgCount > 1 THEN Modules.GetArg(1, path) END;

  d := Fyaml.ParseFile(path, err);
  IF d = NIL THEN Out.String(err.msg^); RETURN END;   (* gcc-style, one line per error *)

  root := d.Root();
  server := root.Value("server");                     (* NIL if absent *)
  IF (server = NIL)
     OR ~server.StringField("host", host, err)        (* required *)
     OR ~server.IntegerField("port", port, err)
     OR ~server.BooleanFieldOr("ssl", FALSE, ssl, err) (* optional, with a default *)
  THEN
    IF err # NIL THEN Out.String(err.msg^) ELSE Out.String("no server section"); Out.Ln END;
    d.Close; RETURN
  END;
  Out.String("server: "); Out.String(host^); Out.String(":"); Out.Int(port, 0);
  IF ssl THEN Out.String(" (ssl)") END; Out.Ln;

  origins := root.ByPath("/allowed_origins");
  origins.Items(it);
  WHILE it.Next(origin) DO text := origin.Scalar(); Out.String("origin: "); Out.String(text^); Out.Ln END;

  (* Merge {timeout: 45} into /server. InsertAt consumes patch and
     makes every Node taken from d before it invalid: look them up
     again afterwards. *)
  patch := d.CreateMapping();
  IF ~patch.AppendPair(d.CreateScalar("timeout"), d.CreateScalar("45"), err)
     OR ~d.InsertAt("/server", patch, err) THEN
    Out.String(err.msg^); d.Close; RETURN
  END;
  root := d.Root(); server := root.Value("server");
  IF server.IntegerField("timeout", timeout, err) THEN
    Out.String("timeout now "); Out.Int(timeout, 0); Out.Ln
  END;

  yaml := d.ToYAML(Fyaml.emitModeFlowOneline, err);
  IF yaml # NIL THEN Out.String(yaml^) END;
  d.Close
END Run;

BEGIN Run
END ExampleConfig.
```

Its output, on `examples/config.yaml`:

```
server: localhost:8080 (ssl)
origin: https://example.com
origin: https://www.example.com
origin: https://app.example.com
timeout now 45
{server: {host: localhost, port: 8080, ssl: true, max_connections: 100, timeout: 45}, database: ...}
```

## Concepts

**Documents.** `ParseString`, `ParseFile` and `NewDocument` give a
`Document`, which owns libfyaml's tree. `Close` it when done. `Close` is
idempotent, and a GC finalizer closes a document that becomes unreachable
without it. But poc's collector runs only when Oberon code allocates, and
can't see libfyaml's C memory, so close documents parsed in a loop.
`ParseString` copies its text; parsing reads only the first document of
a multi-document input (use `FyamlStreams` for all of them).

**Standard input.** `ParseStdin(err)` (or `ParseStdinWith(options,
err)`) parses standard input, and `FyamlStreams.OpenStdin(err)` reads
all its documents; errors name the file `<stdin>`. `ParseStdin` reads
stdin to its end, so call it once. libfyaml reads stdin through C's
stdio, so don't also read it with poc's `In` module.

**Nodes.** `Root`, `Value`, `Item`, `ByPath` and the iterators return
`Node`s: small heap objects that keep their document alive. A `Node`
dies when its document is closed, and also when `InsertAt`, `Resolve`,
or `SetRoot` replacing an existing root is called on its document.
libfyaml frees the nodes those calls replace, so the binding invalidates
every earlier `Node` of that document. Look nodes up again afterwards.
Using a dead `Node` halts; `Fyaml.Valid(n)` tests without halting.

**Errors and halts.** A call that can fail on its input (bad YAML, a
missing file, a missing key, a malformed value) returns NIL or FALSE and
hands back an `Error` in a `VAR err` parameter, NIL on success:

| kind | from |
|---|---|
| `ParseError` | malformed YAML (also a cyclic alias, with resolving on) |
| `FileError` | a file that can't be opened; the message gives the OS reason |
| `EmitError` | `ToYAML`/`ToFile` failures, e.g. an empty document |
| `PathError` | `InsertAt`: no node at the path, or it can't take the insert |
| `DuplicateKey` | `AppendPair` with a key the mapping already has |
| `MissingKey` | `Required` and the `...Field` accessors |
| `DataError` | typed accessors: not a scalar, malformed, or out of range |
| `ResolveError` | `Resolve`, e.g. a cyclic reference |

`err.msg` is ready to print: one `file:line:column: error: text` line
per error. `err.file`, `err.line`, `err.column` and `err.path` hold the
same facts separately. See `examples/` for syntax errors, malformed
values and missing keys.

A programming mistake is an `ASSERT` failure, which poc reports as
`assertion failed (61)` on standard error, with the code, and exit
status 10:

| code | constant | cause |
|---|---|---|
| 61 | `AssertInvalid` | a closed document or stream, or a dead `Node` |
| 62 | `AssertKind` | an operation on the wrong kind of node |
| 63 | `AssertIndex` | `Item` index out of range |
| 64 | `AssertAttach` | attaching a node twice, or into another document |

A method call on a NIL `Node` halts with poc's "NIL pointer dereference"
(exit status 4).

**Strings.** `Fyaml.String` is `POINTER TO ARRAY OF CHAR`, 0X-terminated.
A YAML scalar may contain 0X; `Scalar` copies every byte, and
`ScalarLen` gives the real length. **Indexes are 0-based**, as in paths
(`/tags/0`).

**Typed values.** `LongIntValue`, `IntegerValue`, `RealValue`,
`LongRealValue` and `BooleanValue` resolve a scalar as YAML 1.2's core
schema does: integers in decimal, `0x`, `0o` and (an extension) `0b`,
with `_` allowed between digits; floats including `.5` and `5.`;
`true`/`True`/`TRUE`/`false`/`False`/`FALSE`. `.inf`, `.nan` and
timestamps are not supported. The `...Field` forms look a key up in a
mapping first (missing: `MissingKey`); the `...FieldOr` forms take a
default for a missing key, but a present, malformed value is still a
`DataError`. `IsNullValue` accepts an empty plain scalar and plain `~`,
`null`, `Null`, `NULL`.

**Building and changing.** `NewDocument`, then `CreateScalar`,
`CreateSequence`, `CreateMapping`, `Append`, `AppendPair` and
`SetRoot`. `InsertAt(path, n, err)` merges `n` into the node at `path`
(mapping into mapping, sequence into sequence, or replacing a scalar)
and always consumes `n`, setting it to NIL. Nodes created but never
attached are freed by `Close`.

**Emitting.** `ToYAML(flags, err)` and `ToFile(path, flags, err)`, with
`flags` a sum of `emitDefault`, `emitSortKeys` and one of
`emitModeOriginal`, `emitModeBlock`, `emitModeFlow`,
`emitModeFlowOneline` or `emitModeJson`.

**Anchors, tags, styles, locations.** Aliases and merge keys are
resolved while parsing unless `ParseStringWith`/`ParseFileWith` get
`{Fyaml.NoResolve}`; then `IsAlias`, and later `Resolve`. `Tag`,
`Style` (`StylePlain`, `StyleDoubleQuoted`, ...) and
`Location(line, column)` (1-based, scalars only) describe the source.

**Streams.**

```oberon
s := FyamlStreams.OpenFile("many.yaml", err);
IF s # NIL THEN
  WHILE s.HasNext(err) DO d := s.Next(err); (* ... *) d.Close END;
  IF err # NIL THEN Out.String(err.msg^) END;  (* a malformed document *)
  s.Close
END
```

`Next` alone also works: NIL with `err = NIL` is the end. After a parse
error the stream is finished (libfyaml can't resync). Documents stay
usable after their stream is closed.

## Oberon-2 notes

- There is no call chaining: `d.Root().Value("k")` doesn't compile,
  since a call's result isn't a designator. Use a variable per step,
  or `ByPath` for several levels at once.
- Don't pass `err` in the same call that sets it
  (`Report(Fyaml.ParseFile(p, err), err)`): the report leaves the order
  of evaluating arguments open, so a program must not depend on it.

## Performance

`make bench` runs alibfyaml's benchmarks on the same generated inputs
(same checksums). On the machine used for development: one 200,000-entry
document read with the typed accessors takes about 0.83 s (0.66 s of it
libfyaml's parse), as with olibfyaml and a little faster than alibfyaml;
20,000 small documents from a stream take 0.06 s, as alibfyaml's. See
PLAN.md, Phase 6 and "Port to poc".

## Layout

- `src/`: `FyThin` (with `FyThin.c`), `Fyaml`, `FyamlStreams`.
- `test/`: one program per concern, halt tests, fixtures.
- `examples/`: the programs above, with fixtures and expected output.
- `bench/`: benchmarks and input generators.
- `AGENTS.md`: working notes for developing the binding.
- `PLAN.md`: design, decisions, and confirmed libfyaml behaviour
  (olibfyaml's, with a section on the port to poc).
