# polibfyaml bugs

Bugs in polibfyaml's own code, numbered, newest last. Problems in
libfyaml itself go in `LIBFYAML-ISSUES.md` instead; numbers like
"libfyaml 2" refer to that file.

When one is fixed, replace its "Status" with "Fix" and "Verified". When
one turns out not to be a bug, say so in its section rather than
deleting it.


## 1. A stream ends quietly at a document whose aliases can't be resolved

**Symptom.** With resolving on (the default: no `Fyaml.NoResolve`), a
`FyamlStreams.Stream` reaching a document with an undefined alias or a
cyclic reference returns NIL from `Next` (or FALSE from `HasNext`) with
`err` NIL, the same as a clean end of stream. The document is not
reported, and nothing after it is read. Found 2026-11-15 through
pobesm2_fmt2, which prints nothing for such a file and exits with status
0.

**Repro** (pobesm2_fmt2 at 78a0fe6, libfyaml 0.8-9.fc44):

```sh
printf -- '- name: *nope\n' > alias.yaml
pobesm2_fmt2 alias.yaml; echo "rc=$?"     # prints only rc=0
```

`Fyaml.ParseFile` on the same file gives a ParseError, `alias.yaml:1:10:
error: invalid alias`.

**Cause.** `Fetch` (`src/FyamlStreams.Mod:156`) treats a NULL from
`fy_parse_load_document` as an error only if `fy_diag_got_error` is set,
and libfyaml doesn't set it for a resolve failure (libfyaml 2), although
it does collect the error and `fy_parser_get_stream_error` returns true.
No test reads such a document through a stream: `TestAnchors` checks a
cycle only through `ParseFile` and `Resolve`.

**Fix.** `Fetch` also checks `fy_parser_get_stream_error`
(`FyThin.ParserGetStreamError`), which libfyaml sets for a syntax error
and a resolve failure alike and not at a clean end, so a resolve
failure is a `ParseError` with libfyaml's located message. The same
fix is in polibfyaml and olibfyaml (PLAN.md, "A resolve failure in a
stream").

**Verified** 2026-11-15. `TestStreams` checks an undefined alias after a
good document (`HasNext` FALSE and `(string-in-memory):4:4: error:
invalid alias`, then the end), a cycle through `Next`, and an undefined
alias with `NoResolve` (no error). `make test` and `make valgrind` pass
in both repos; with the old check, the undefined-alias check failed.
