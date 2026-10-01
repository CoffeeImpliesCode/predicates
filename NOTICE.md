# Notice

## Upstream

`src/predicates.c` is the work of Jonathan Richard Shewchuk, School of Computer
Science, Carnegie Mellon University. Its own header states the terms:

```
  May 18, 1996

  Placed in the public domain by
  Jonathan Richard Shewchuk
  School of Computer Science
  Carnegie Mellon University
  5000 Forbes Avenue
  Pittsburgh, Pennsylvania  15213-3891
  jrs@cs.cmu.edu
```

That notice is public domain dedication, not a licence to be re-licensed. The
file is redistributed here unmodified, under the same terms, with no warranty of
any kind. See `UPSTREAM.md` for the canonical URL, the revision date and the
SHA256 of the copy in this repository.

Public domain dedication is why there is no `LICENSE` file. Adding one would be
adding a term the author did not grant, and omitting it here is not an omission:
the notice is the grant. `UPSTREAM.md` records it in full so a downstream
auditor does not have to read C source to find it.

## Fork-specific notice

The files listed below were written for this fork and are not upstream's. They
carry no upstream copyright and no upstream permission is claimed over them.

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build: C artifact, translated header, facade module, tests, example, cross-target check |
| `build.zig.zon` | Package manifest |
| `include/predicates.h` | Aggregate machine-readable declaration header transcribed from the prototypes in `src/predicates.c` |
| `src/root.zig` | Zig facade: typed points, initialization lifecycle, non-finite input contract |
| `test/all.zig` | Test root |
| `test/exact_oracle.zig` | Exact integer/rational sign oracle, used only by tests |
| `test/predicates_test.zig` | Behavioural tests for the facade |
| `test/expansion_test.zig` | Behavioural tests for the expansion arithmetic |
| `examples/smoke.zig` | Deterministic runnable example |
| `consumer/build.zig` | A separate package that consumes this one |
| `consumer/build.zig.zon` | Manifest for that package |
| `consumer/src/main.zig` | That package's program |
| `.github/workflows/verify.yml` | This fork's verification workflow |
| `README.md`, `README.zig.md` | Fork documentation |
| `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md` | Fork documentation |

## Numbered modifications

Upstream obligations are unaffected by anything below, because there are none:
public domain dedication cannot be narrowed, but it also cannot be widened by
this fork. What the list records is every behavioural difference between "the
canonical `predicates.c`" and "what this package compiles and hands a caller",
so that a reader can tell which parts are Shewchuk's and which are ours.

1. **Compilation flags are added where upstream states none.**
   `-std=gnu17`, `-ffp-contract=off`, `-fno-fast-math`, applied in `build.zig`.
   Upstream documents these as requirements in prose and leaves them to the
   caller. Compiling without `-ffp-contract=off` is the difference between a
   correct predicate and a wrong one, silently.
   No warning is suppressed for this file. The compile line carries no `-Wno-`,
   no `-Werror` and no `-Wall`, so a diagnostic from the 1996 source is
   reported rather than hidden. That is deliberate: a target the compiler
   refuses outright is documented below instead of being silenced.

2. **A declaration header is added.** `include/predicates.h` transcribes the
   prototypes upstream keeps in a comment block. No declaration is invented,
   renamed, retyped or omitted. Upstream's K&R definitions are not rewritten to
   match it; the header is for consumers and for `translate-c`. Its correctness
   is established by compiling and linking rather than by comparing names:
   `translate-c` reads the whole header, `zig build test` links the translated
   declarations and calls them, and the consumer package links and runs the
   public calls from outside this repository. An earlier revision of the CI
   workflow also compared declaration names in the header with definition names
   in the C source; that check was removed because a name-set comparison is a
   source-text test that a reindentation or a retyped declaration can defeat in
   either direction.

3. **An initialization lifecycle is added.** `src/root.zig` exposes
   `init()`, which runs upstream's `exactinit()` exactly once per process under
   an atomic once-guard. Upstream's contract is "call exactinit() once, before
   anything else" and its hazard is that a second concurrent call is a data race
   on file-scope globals even though the values written are identical. The
   facade removes that hazard; the raw `exactinit()` remains reachable through
   `predicates.c` for anyone who wants upstream's semantics exactly.

4. **A non-finite input contract is added.** Every facade predicate returns
   `error.NonFiniteCoordinate` for a NaN or infinite coordinate instead of
   returning a number that is not the determinant of anything. Upstream has no
   contract here and does not detect this case. This is an addition at the
   facade, not a change to the C: callers using `predicates.c` directly get
   upstream behaviour.

5. **Typed entry points are added.** `orient2d`, `orient3d`, `incircle` and
   `insphere` take `Point2`/`Point3` by value, allocate nothing, and return
   either the upstream determinant or an error. The non-robust `*Fast` variants
   are exposed alongside them, unchanged, because knowing when they fail is
   useful. No algorithm was reimplemented, rounded or substituted.

6. **Non-robust and reference variants are exposed, not exercised as if they
   were robust.** `*fast`, `*exact`, `*slow` and `*adapt` are all reachable
   through `predicates.c`. `*adapt` takes a caller-computed error bound and is a
   helper of the routine above it, not an entry point; it is declared because it
   is externally visible, and the header says so.

7. **A build, tests, an example and a consumer package are added.** None of
   these change upstream's behaviour.

8. **No source file of upstream was edited.** `src/predicates.c` is
   byte-identical to the copy at the canonical URL, and CI recomputes its
   SHA256 on every run.

9. **One requested target is delivered as a documented boundary rather than as
   a build.** `zig build check` attempts all six targets. Five compile and link:
   x86_64-linux-gnu, aarch64-linux-gnu, aarch64-macos-none,
   riscv64-linux-gnu and wasm32-wasi. x86_64-windows-gnu fails, because
   `src/predicates.c` calls POSIX `random()`, which mingw-w64 and the UCRT do
   not provide, and because the same compile reports every old-style function
   definition as an error; the step exits non-zero, and CI marks that one
   target `continue-on-error` rather than dropping it from the matrix. No
   substitute generator is supplied and the canonical file is not edited, so a
   Windows consumer gets neither a library with a quietly different random
   source nor a patched arithmetic kernel — it gets a target this fork states
   it does not support. `FORK-NOTES.md` section 21 has the diagnostics, the
   toolchain headers that settle the question, and the options that were
   refused.