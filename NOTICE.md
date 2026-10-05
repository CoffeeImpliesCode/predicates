# Notice

Two separate things are recorded here: what the canonical native source is and
what rights it carries, and what this fork added on top of it. They have
different terms and are not merged into one label. `FORK-LICENSE.md` carries the
full licence argument; `UPSTREAM.md` carries the fetch, digest and re-sync
procedure.

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

That text is the grant. The file is redistributed here unmodified.
`UPSTREAM.md` has the canonical URL, the revision date and the SHA256 of the
copy in this repository.

Upstream ships no `LICENSE` file and none is manufactured here;
`UPSTREAM.md` reproduces the notice so a reader does not have to open C source.

## The native source, in full

Everything below was read out of the file in this tree, not from a description
of it. Line numbers are of `src/predicates.c` as imported.

| | |
|---|---|
| Canonical URL | `https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c` |
| Revision | May 18, 1996, the date in the file header. No tag, no commit: the file is served from an AFS directory, not a repository. |
| SHA256 | `f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029` |
| MD5 | `4f199d0294b91b89f2decff591ffa305` |
| Size | 171536 bytes, 4262 lines, ASCII |
| Project page | `http://www.cs.cmu.edu/~quake/robust.html` |
| Technical report | CMU-CS-96-140 |
| Language | C, old-style (K&R) function definitions throughout |

The file's whole configuration is four included headers and six macros:

* `<stdio.h>`, `<stdlib.h>`, `<math.h>`, `<sys/time.h>` at
  `src/predicates.c:116`–`119`. `<sys/time.h>` is included and never used:
  there is no `gettimeofday`, `struct timeval`, `time` or `clock` call anywhere
  in the file. That include is upstream's, left as written.
* `#define REAL double` at `src/predicates.c:133`. The coordinate type is
  hard-coded, not configurable; a consumer that re-declares these prototypes has
  to say `double`.
* `#define INEXACT` with an empty replacement list at
  `src/predicates.c:130`, with upstream's alternative `#define INEXACT volatile`
  commented out on the next line. It is upstream's escape hatch for platforms
  that evaluate in excess precision, and it is deliberately left as upstream
  wrote it.
* Four further macros at `src/predicates.c:134`–`137` — `REALPRINT`, `REALRAND`,
  `NARROWRAND`, `UNIFORMRAND` — name `doubleprint`, `doublerand`,
  `narrowdoublerand` and `uniformdoublerand`. `REALPRINT` names a routine that
  upstream ships commented out and that this file therefore does not define.

The translation unit publishes **40 functions and 15 mutable globals**. The
count was obtained by scanning the file with block comments removed, so the
three debug printers that upstream ships commented out — `doubleprint`,
`floatprint` and `expansion_print` at `src/predicates.c:379`, `426` and `472` —
are correctly excluded: they are not compiled and the file links without them.

| Group | Count | Members |
|---|---|---|
| Initialization | 1 | `exactinit` (`src/predicates.c:643`) |
| Random-value debug helpers | 6 | `doublerand` (496), `narrowdoublerand` (522), `uniformdoublerand` (547), `floatrand` (565), `narrowfloatrand` (590), `uniformfloatrand` (614) |
| Expansion arithmetic | 13 | `grow_expansion` (698) … `estimate` (1392) |
| Geometric predicates | 20 | five variants each of `orient2d` (1432), `orient3d` (1684), `incircle` (2362), `insphere` (3298) |

The 15 globals are declared together at `src/predicates.c:361`–`368` and are
written only by `exactinit`, at `src/predicates.c:651`–`656` and `670`–`682`:
`splitter`, `epsilon`, `resulterrbound`, and the triples `ccwerrboundA/B/C`,
`o3derrboundA/B/C`, `iccerrboundA/B/C`, `isperrboundA/B/C`. Every one of them is
zero until `exactinit` runs.

`include/predicates.h` declares exactly those 40 functions and exactly those 15
globals. The comparison was made mechanically against the comment-stripped
definition list in both directions: nothing is defined and undeclared, and
nothing is declared and undefined. That is a statement about completeness of the
aggregate header, established by enumeration; the header's real gate is still
compilation and linking, not a name-set comparison.

**All 15 globals are mutable native state, not constants.** See item 12 below:
anything that reaches this library through a runtime loader has to address them
through the loaded provider, not through a second copy of the library.

### The declared `random()` dependency, exactly

`random()` is POSIX, not ISO C. It is called at **13 call sites in 6
functions**: `src/predicates.c:503`, `504`, `505` (`doublerand`), `529`, `530`,
`531` (`narrowdoublerand`), `552`, `553` (`uniformdoublerand`), `572`, `573`
(`floatrand`), `597`, `598` (`narrowfloatrand`), `619` (`uniformfloatrand`).
The six helpers share one translation unit with the predicates; no flag changes
that, and the predicates themselves never call it.

## Fork-specific notice

The files listed below were written for this fork. They carry no upstream
copyright, no upstream permission is claimed over them, and they are released
into the public domain: see `FORK-LICENSE.md`, which also records the owner
authorization that is the basis for that grant and the
`LicenseRef-PublicDomain` identifier used in their SPDX headers.

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build: C artifact, translated header, facade module, tests, example, cross-target check |
| `build.zig.zon` | Package manifest |
| `include/predicates.h` | Aggregate machine-readable declaration header transcribed from the prototypes in `src/predicates.c` |
| `src/root.zig` | Zig facade: typed points, initialization lifecycle, non-finite input contract |
| `runtime/graph.zig` | Build half of the runtime-loading route: the dispatch module a `-Druntime=true` build gives the facade as its `c`, and the loader core a linked build gives it as `rt`. Nothing in it links the native library |
| `runtime/library.zig` | This SDK's loader descriptor: the namespaced synchronization binding, the provider record (required symbols, ABI families, boundaries) and the one load-time arithmetic check |
| `runtime/loader.zig` | The reusable loader core: `LoadSource`, `LoadError`, the readiness flag and the panic a call before readiness triggers, the process-lifetime attempt state machine, and the `dlopen`/`LoadLibraryExW` platform layer |
| `runtime/generate.zig` | Build-time generator that reads this build's own `translate-c` output and writes the dispatch module plus a patched copy of that translation; no part of the native API is written by hand |
| `runtime/sync.c` | The loader's process-global mutex, condition variable and thread identity, compiled with `-DRT_SYNC_PREFIX=predicates_rt` so its symbols cannot collide with another SDK's |
| `runtime/sync.h` | The declarations `runtime/sync.c` implements |
| `test/support.zig` | What a test binary must do before it touches the library, in either published configuration: `init()` when linked, an explicitly named provider through `PREDICATES_TEST_PROVIDER` when runtime-loaded |
| `test/all.zig` | Test root |
| `test/exact_oracle.zig` | Exact integer/rational sign oracle, used only by tests |
| `test/predicates_test.zig` | Behavioural tests for the facade |
| `test/expansion_test.zig` | Behavioural tests for the expansion arithmetic |
| `test/raw_surface_test.zig` | Behavioural tests for the raw `predicates.c` surface reached through `pub const c`: the `*exact`, `*slow` and adaptive implementations against the oracle, both branches of each `*adapt` filter, and the fifteen file-scope constants against values this file re-derives from `src/predicates.c` |
| `examples/smoke.zig` | Deterministic runnable example |
| `consumer/build.zig` | A separate package that consumes this one |
| `consumer/build.zig.zon` | Manifest for that package |
| `consumer/src/main.zig` | That package's program |
| `package.nix` | Source-only Nix derivation, shared by `flake.nix` and `devenv.nix`; it runs `build.zig` with `--prefix $out` and installs nothing by hand |
| `flake.nix` | Flake interface: `packages.<system>.static` and `.shared` |
| `flake.lock` | The flake's resolved inputs: one `nixpkgs` node pinned to the revision `flake.nix` already names in its input URL. Written by a lock operation; `flake.nix` itself writes no lock |
| `devenv.nix` | Canonical development environment: tools-only shell, lazy `outputs.static` / `outputs.shared`, `sdk:`-namespaced tasks |
| `devenv.yaml` | The devenv nixpkgs input pin |
| `.envrc` | direnv entry point for devenv |
| `tools/check-provenance.sh` | The provenance gate: the digest, the licence notice, and the per-file upstream baseline with its coverage check |
| `UPSTREAM-BASELINE.sha256` | The per-file SHA-256 baseline for every upstream byte this package carries, with its pin, derivation and counts |
| `cross-test.profile.sh` | Settings-only cross-test profile at the package root; it narrows neither the matrix nor the targets |
| `tools/c_surface_gate.c` | The public-C-surface gate, extracted from what was a CI heredoc so the static and shared jobs link one program instead of two drifting copies |
| `FORK-LICENSE.md` | The licence record for everything in this table |
| `.github/workflows/verify.yml` | This fork's verification workflow |
| `README.md`, `README.zig.md` | Fork documentation |
| `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md` | Fork documentation |

`README.upstream.md` is **deliberately absent**: the canonical distribution is
one C file and ships no README, so there are no upstream bytes to preserve and
`README.md` is this fork's own document from first line to last.

## Numbered modifications

What the list records is every behavioural difference between "the canonical
`predicates.c`" and "what this package compiles and hands a caller", so that a
reader can tell which parts are Shewchuk's and which are ours.

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
   a build.** `zig build check` walks `supported_check_targets` and compiles five
   targets: x86_64-linux-gnu, aarch64-linux-gnu, aarch64-macos-none,
   riscv64-linux-gnu and wasm32-wasi. It is green over all five.
   `x86_64-windows-gnu` is not one of them and is not attempted:
   `refused_check_targets` names it, and `zig build check
   -Dtarget=x86_64-windows-gnu` ends at `refuseTarget` with the printed reason,
   before any compiler is invoked. That reason is that `src/predicates.c` calls
   POSIX `random()` at the 13 call sites listed above, which mingw-w64 and the
   UCRT do not provide, and that the same compile reports old-style function
   definitions as errors; CI asks for the refused target by name and marks that
   one cell `continue-on-error` rather than dropping it from the matrix. No
   substitute generator is supplied and the canonical file is not edited, so a
   Windows consumer gets neither a library with a quietly different random source
   nor a patched arithmetic kernel — it gets a target this fork states it does
   not support. `FORK-NOTES.md` section 21 has the diagnostics, the toolchain
   headers that settle the question, and the options that were refused.

   **A second, independent boundary applies to the shared variant.** Even if the
   source did compile for a PE/COFF target, `-Dlinkage=dynamic` would produce a
   DLL that exports nothing: a PE/COFF image exports a symbol only when that
   symbol is marked, and all forty externally visible definitions and all
   fifteen globals in `src/predicates.c` have external linkage with no
   visibility or export decoration. `zig build check -Dlinkage=dynamic` compiles
   the same five buildable rows against that shared object and refuses the sixth
   by name, rather than narrowing the matrix to the convenient ones. This is
   recorded as a property of the toolchain and the source format, not as a
   reason to mark symbols: marking any of them would be an edit to the canonical
   file.

10. **Standalone Nix packaging is added.** `package.nix` builds this repository
    and nothing else: no upstream fetch, no sibling `../` import, no host path,
    no username and no store path in any committed file. It installs nothing by
    hand: `build.zig` owns the whole installed layout, so `nix build` and
    `zig build install` produce one layout by construction rather than two kept
    in agreement by hand. `flake.nix` exposes `.static` and `.shared` as two
    variants of that one derivation and keeps `default` on the SDK's existing
    static policy. `devenv.nix` and `devenv.yaml` are the canonical development
    environment, and it installs tools only: no shell entry requires building
    this SDK.

11. **A licence is now asserted for the fork-authored files.** Earlier records
    in this file described the fork-authored material as asserting no licence.
    That described the state before the owner authorized one. The grant, its
    basis and its SPDX identifier are in `FORK-LICENSE.md`. The terms recorded
    for `src/predicates.c` above are unchanged.

12. **The mutable native globals are load-bearing state, not constants.**
    `splitter`, `epsilon` and the thirteen error bounds are written by
    `exactinit()` and read by every robust predicate, and all fifteen are
    exported. A runtime-loaded provider must reach them **through the loaded
    provider**, and must call `exactinit()` through that same table: the symbols
    collide in one process, so a loaded function computing against a second
    copy's globals would read that copy's zeros until its own `exactinit()` ran.
    The dispatch produced by `runtime/graph.zig` routes both the functions and
    the globals through the one resolved table.

13. **There is no upstream README, and no `README.upstream.md`.** The canonical
    distribution is one C file and ships no README, so there are no upstream
    bytes to preserve. `README.md` is this fork's own document.

14. **The installed output carries the terms, and `build.zig` is where they
    come from.** The three files are named in `build.zig:113`-`117`
    (`licence_material`) and land at the path in `build.zig:123`
    (`licence_dest_dir`), which is `$prefix/share/licenses/predicates/`. They are
    copied byte for byte from this repository; nothing is rewritten on the way
    out. The Nix derivation does not name them and does not copy them: it runs
    `zig build install --prefix $out` and gets that path from the same graph.

    This matters more here than it would for a project with a `LICENSE` file,
    because upstream has none — the public-domain dedication lives in the header
    of `src/predicates.c`, and `NOTICE.md` is where a recipient finds it. A
    binary without the notice is a binary whose grant cannot be located.

15. **A generated pkg-config file, and no soname series.** `build.zig` writes
    `$prefix/lib/pkgconfig/predicates.pc` from the sources, with
    `prefix=${pcfiledir}/../..` so the metadata is correct wherever the prefix
    lands, `Cflags: -I${includedir}` and nothing else, and
    `Libs: -L${libdir} -lpredicates`. The floating-point flags are deliberately
    absent from it: they apply to `src/predicates.c`, which this build compiles
    with them, not to a consumer's own objects. `Libs.private:` is empty on
    purpose — the only external call the library makes is POSIX `random()`,
    which is libc and is implicit for a C consumer, and nothing from libm is
    called, so `-lm` would name a dependency this library does not have.

    The same file deliberately sets no `.version`, so there is no soname series:
    the shared object is plain `libpredicates.so`, not `libpredicates.so.0` with
    a symlink. Upstream has no version, tag or release series, and `0.1.0` in
    `build.zig.zon` is this fork's own; publishing `libpredicates.so.0` would
    assert an ABI major number that no source record supports. `-lpredicates`
    and the generated `.pc` both resolve the plain name, and one `.pc` is
    correct for both variants because the file takes no linkage argument.