# predicates

Shewchuk's adaptive-precision geometric predicates — `orient2d`, `orient3d`,
`incircle`, `insphere` — packaged for Zig 0.16, with the exact floating-point
route (`*exact`, `*slow`), the adaptive engines (`*adapt`), the expansion
arithmetic and the six random-value helpers all preserved and reachable.

What upstream guarantees is the **sign**, and only for finite coordinates whose
filtered products stay inside the double range; the range condition is real, is
spelled out under "Notes for every caller" below, and is not enforced by this
package. The magnitude is upstream's own adaptive determinant approximation —
its own comment calls it a rough approximation of twice the signed area, or of
six times the signed volume — and it is not guaranteed. It is not the permanent
either: that is the filtered term upstream multiplies an error bound by, and it
never leaves the C.

The preserved `predicates.h:153-161` comments misdescribe the magnitude and
caller scratch. `*exact`/`*slow` take only points and own local scratch; no
`expanarg` buffers are required. See `README.zig.md` for the C source anchors.

| | |
|---|---|
| Upstream | <https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c> |
| Revision | May 18, 1996, the date in the file header. There is no tag or commit: the file is served from an AFS directory, not a repository. |
| SHA256 | `f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029`, recomputed over the copy in this tree |
| Licence | Public domain, by the author's own dedication. See `NOTICE.md`. |

`UPSTREAM.md` has the full provenance, the complete exported surface and the
sync procedure. `FORK-NOTES.md` has the problems met while packaging this and
what was done about each. The Zig interface is documented separately, in
`README.zig.md`.

## Native-source deviations

**None.** `src/predicates.c` is byte-identical to the file at the canonical URL
and has never been patched. That is a deliberate constraint rather than an
accident: the SHA256 above is the complete statement of what was compiled, and
it is recomputed by `tools/check-provenance.sh` and by CI.
`UPSTREAM-BASELINE.sha256` is that digest as a per-file record, with the pin and
the fetch it was derived from, and the same gate checks that every carried path
is either in it or declared fork work.

There is no `README.upstream.md` in this repository, and its absence is not an
oversight. The upstream distribution is a single C file and ships no README, so
there are no upstream bytes to preserve separately. **This `README.md` is
fork-authored from end to end** and must not be described as upstream or copied
under another name to manufacture a record that does not exist.

Everything else in the repository — the header, the build, the facade, the
runtime-loading route under `runtime/`, the tests, the example, the consumer
package, the Nix packaging and this documentation — was written for this fork.
`NOTICE.md` has the full inventory.

## Native-build deviations

What the compiled package does that the bare upstream file does not. Each entry
is a fork decision with a stated reason; none of them changes an algorithm.

1. **Compile flags where upstream states none.** `-std=gnu17`,
   `-ffp-contract=off` and `-fno-fast-math`. These are correctness requirements
   documented by upstream in prose, not preferences, and `build.zig` applies
   them on every target. No `-Wno-`, no `-Werror` and no `-Wall` is passed for
   this file, so a diagnostic from the 1996 source is reported rather than
   silenced. The Nix derivation adds no flags of its own; the native build
   graph is the only place they appear.

2. **An aggregate declaration header.** `include/predicates.h` transcribes the
   prototypes upstream keeps in a comment block. It declares exactly the 40
   functions and 15 globals the translation unit defines — nothing invented,
   renamed, retyped or omitted — and it is installed with the artifact. The K&R
   definitions are **not** rewritten to match it.

3. **An initialization lifecycle.** `predicates.init()` runs upstream's
   `exactinit()` exactly once per process under an atomic once-guard, so two
   threads calling it at the same moment cannot race on the file-scope globals.
   The raw `exactinit()` remains reachable through `predicates.c`.

4. **A non-finite input contract.** Every facade predicate returns
   `error.NonFiniteCoordinate` for a NaN or infinite coordinate. Upstream has no
   contract here and does not detect the case. Callers using `predicates.c`
   directly get upstream behaviour.

5. **Typed entry points.** The four predicates take `Point2`/`Point3` by value,
   allocate nothing, and return either the determinant or an error, with `*Sign`
   wrappers and the non-robust `*Fast` variants exposed alongside. No algorithm
   was reimplemented, rounded or substituted.

6. **The whole upstream surface stays reachable.** The expansion arithmetic, the
   `*exact` and `*slow` reference implementations, the `*adapt` engines, and all
   six random-value helpers — `doublerand`, `narrowdoublerand`,
   `uniformdoublerand`, `floatrand`, `narrowfloatrand`, `uniformfloatrand` — are
   exported and declared. They are exposed, not silently dropped, and the
   `*fast` and `*adapt` routines are *not* presented as if they were robust.

7. **One target is a documented boundary, not a build.**
   `x86_64-windows-gnu` does not compile. See the matrix below; the reason is
   upstream's, the failure is not repaired here, and the target is not dropped
   from the matrix either.

### History of these deviations

The deviations above are the current state, not the whole story.
`FORK-NOTES.md` records each one with the evidence that forced it, and
`CHANGELOG.md` carries the dated entries. Two are worth naming here because
they changed what this package claims:

* **2026-10-03 — "Zig API contract alignment".** The initialization observer had
  to acquire the winner's release of the native constants rather than read a
  monotonic flag, and the prose about the range extremes was corrected to the
  branch structure actually in `src/predicates.c`. The full entry is in
  `CHANGELOG.md`; the acquire/release edge is source-confirmed, not TSAN or
  weak-memory hardware proof.
* **This migration.** Standalone Nix packaging and a licence record for the
  fork-authored files were added, and this README was restructured into the
  canonical order. No native source, header, algorithm, flag or test changed.
  Entries are under `[Unreleased]` in `CHANGELOG.md`.

## Build, run and test matrix

### What was observed, and when

These rows are historical evidence from gates that ran on this host with the
pinned Zig 0.16.0. They are kept as evidence of what was true then, not as a
claim about the current tree.

| Gate | Observed |
|---|---|
| `zig build` | compiled the C archive and the translated header; the run stopped in `examples/smoke.zig` on `std.math.ldexp` receiving a `comptime_float` |
| `zig build` (second run) | got past that call, stopped at `examples/smoke.zig:136` formatting an error value with `@tagName` |
| `zig build test` (Debug) | 39 tests passed |
| `zig build test -Doptimize=ReleaseSafe` | 39 tests passed |
| `zig build smoke` | ran to completion and printed its deterministic output, including `orient2d one-ulp cancellation, robust negative` against `orient2d one-ulp cancellation, fast zero` — the configuration where the robust filter falls through to exact arithmetic and the non-robust variant rounds to zero |
| `zig build check` | attempted all six targets: five compiled and linked, x86_64-windows-gnu failed with the 39 diagnostics in `FORK-NOTES.md` section 21, and the step exited non-zero |
| `consumer/` (`zig build run`) | not run at that point |
| `.github/workflows/verify.yml` | not run locally; CI executes it |

Later, dated 2026-10-03, the same host and compiler ran install, tests in all
four optimize modes, the smoke run, the package consumer and the module example
and recorded them as passing. That receipt is the `CHANGELOG.md` entry of that
date, including its own bound: the acquire/release edge is source-confirmed and
the cross-target `check` result is compile-only.

The two `zig build` rows above are history: both diagnostics were in the example
rather than in the library, because the C archive and the translated header had
compiled by the time each run stopped.

Nothing in that table is a claim that a cross-built binary executed. No target
other than the host was run.

### Observed on this tree, 2026-10-04/05

Four driver gates ran against this graph after the migration, and each names its
own receipt. The 53-cell cohort is the source-bound one: its receipt records
`source_stamp_before == source_stamp_after` (`66b6f5df…`), with `target_jobs 8`
and `jobs_per_build 8` over the profile's own deadlines.

| Gate | Result |
| --- | --- |
| native eight cells — `zig build test smoke install`, static × dynamic crossed with Debug, ReleaseSafe, ReleaseFast, ReleaseSmall, `-Druntime=false` | **exit 0 in all eight, and none of them is green.** Each cell's own status is `skipped-tests`: `Build Summary: 16/16 steps succeeded; 46/47 tests passed (1 skipped)` |
| own-loaded eight cells — the same eight configurations with `-Druntime=true` and `PREDICATES_TEST_PROVIDER` naming this tree's own `libpredicates.so` (`provider.kind: "own"`) | observed pass, exit 0 in all eight — `Build Summary: 17/17 steps succeeded; 47/47 tests passed` in every cell |
| 53-cell `cross-test` cohort | **observed, exit 1** — raw `pass=20 fail=4 build_only=29 partial=0`; every executed cell reports `tests=46`, and the four failures are the four Windows cells |
| compile-only `zig build check` baseline | observed pass, exit 0 — `Build Summary: 26/26 steps succeeded`, `declared_target_count 6`, `failing_step_lines 0`, `test_pass_lines: []`, and `steps_by_target` names five triples with `x86_64-windows-gnu` at zero |

Receipts: `native-final-evidence/20261004T233628757747Z-69351/run.json`,
`loaded-final-evidence/20261004T232823091897Z-23133/run.json`,
`20261004T221720228710Z-45046/predicates-53-target-8.json`, and row
`baseline-predicates-check` of `baselines-and-configs/20261005T014547Z-797a73f2`.
The cohort's counts are bounded to that epoch and cover nothing that landed after
it.

**The native eight cells are not a pass, and are not read as one.** One test skips
in each of them. The receipts name both guards: `test/predicates_test.zig:209`,
`if (comptime builtin.os.tag == .wasi) return error.SkipZigTest;`, and
`test/raw_surface_test.zig:563`, `if (comptime !predicates.runtime_loaded) return
error.SkipZigTest;`. On a native Linux cell built with `-Druntime=false` the
second is the one that fires, which is why the same suite reports `47/47` under
the runtime route and `46/47` linked. That is a declared guard, not a failure, and
it is also not evidence that the runtime-loaded route works: only the
own-loaded row above is that evidence.

**`build_only` is not a pass either.** Twenty-nine of the 53 cells compiled and
ran nothing because no executor was available.

**The four build failures are one refusal, on four triples.** `aarch64-windows`,
`thumb-windows`, `x86-windows` and `x86_64-windows` each end at this package's
own `refuseTarget` (`build.zig:601` → `:227`) and print
`error: predicates: <target>: no buildable configuration for this target: the
canonical source calls POSIX random(), which Windows does not provide.`
No compiler is invoked on any of them. The 53-cell driver passes an explicit
`-Dtarget`, so it reaches `refuseTarget` on each; that is why these four are
`build=fail` in that table while `zig build check`, which walks
`supported_check_targets`, refuses the same row by name and exits 0.

### Still pending for this migration

Everything below is **PENDING-VERIFICATION** and has not been run here; the
driver owns every result field.

* the installed C consumer and the materialised package consumer;
* the static and shared Nix derivations, their output layouts and their
  dependency records;
* the canonical devenv shell, and `tools/check-provenance.sh`;
* `zig build check -Dlinkage=dynamic` and `zig build check -Druntime=true`, both
  linkages — the `check` step's own six-row evidence above is the default static,
  non-runtime configuration only;
* the runtime-loaded smoke run with an explicitly named provider, and the
  materialised package consumer loaded from one. The runtime route is observed
  above only through `zig build test smoke install`, against this tree's own
  shared object.

Nothing in this section is a result. It is the list of what still has to be run.

### The cross-target matrix

`zig build check` compiles and links the C source, the facade, the tests and
the example without running any of them. A green `check` for a target is compile
evidence, not a claim that a cross-built binary executed.

| Target | `zig build check` (default static linkage) |
|---|---|
| x86_64-linux-gnu | compiles and links |
| aarch64-linux-gnu | compiles and links |
| aarch64-macos-none | compiles and links |
| riscv64-linux-gnu | compiles and links |
| wasm32-wasi | compiles and links |
| x86_64-windows-gnu | **refused, not attempted** — `refused_check_targets` names it and `refuseTarget` prints the reason |

That column is the default **static** linkage only. `zig build check
-Dlinkage=dynamic` attempts the same rows against a shared object and reports
what each one does; those results are not in this table, and nothing in this
repository asserts that a shared object builds for every row above. In particular
the `wasm32-wasi` row says the source compiles and links as an archive; whether it
does so as a shared object is an open question the driver has not answered.

`x86_64-windows-gnu` does not build, and the reason is the canonical source
rather than this package's. Six published routines — `doublerand`,
`narrowdoublerand`, `uniformdoublerand`, `floatrand`, `narrowfloatrand` and
`uniformfloatrand` — call `random()` at thirteen call sites, which is POSIX rather
than ISO C and which neither mingw-w64 nor the UCRT provide; the refusal text
cites `lib/libc/include/any-windows-any/stdlib.h:365`, which declares `rand_s` and
no `random`. `refusalFor` keys on the operating system rather than the triple
(`build.zig:163-164`), so any Windows target this package has never built refuses
with the same explanation instead of compiling and reporting what the compiler
says. The earlier record of this boundary — that the same compile also reports
every old-style function definition in the 1996 source as an error — stays in
`FORK-NOTES.md` section 21 with its 39 diagnostics. Supplying a `random()`, or
rewriting those definitions, would both mean editing the canonical file whose
SHA256 is the reason to trust this package, so the target is documented rather
than faked.

It is not dropped from the matrix, and it is not attempted either. `zig build
check` walks `supported_check_targets` and names the refused row in its own step
description (`build.zig:747-759`), so a green `check` is green over every target
this package supports; `checkMatrixPartition` (`build.zig:250-267`) re-derives
both lists through the same `refusalFor` on every invocation, so a target that
moves between them fails any build rather than quietly changing what `check`
proves. The baseline row above shows the same shape from outside: five triples
with step lines, `x86_64-windows-gnu` at zero steps, exit 0. Naming the refused row
on the command line ends at `refuseTarget` with the printed reason
(`build.zig:601`), which is also where the four Windows cells of the 53-cell table
end. A consumer that needs this library on Windows is blocked by upstream's
source, not by a policy here: compiling `predicates.c` itself against a C library
without POSIX `random()` meets the same wall.

**The shared variant has a second, independent reason.** Even if the source did
compile for a PE/COFF target, `-Dlinkage=dynamic` would produce a DLL that
exports nothing: a PE/COFF image exports a symbol only when that symbol is
marked, and all forty externally visible definitions and all fifteen globals in
`src/predicates.c` have external linkage with no export decoration.
`refusalFor` holds both reasons in one `Refusal`, so no linkage option reaches
past either one and the refusal text names the row. Marking any of those symbols
would be an edit to the canonical file, which is the one option this fork does not
take.

## Consumption

### From Zig

```zig
const predicates = @import("predicates");

pub fn main() !void {
    predicates.init(); // once per process, before any predicate

    const a = predicates.Point2{ .x = 0, .y = 0 };
    const b = predicates.Point2{ .x = 1, .y = 0 };
    const c = predicates.Point2{ .x = 0, .y = 1 };

    switch (try predicates.orient2dSign(a, b, c)) {
        .positive => {}, // counterclockwise
        .negative => {},
        .zero => {},     // collinear
    }
}
```

`dep.module("predicates")` carries the compiled C with it, so there is nothing
to install and nothing to find on the system. The dependency line, the build
snippet, the initialization contract, the range where the guarantee holds and
the whole facade are in **`README.zig.md`**.

### Runtime-loaded natives

`-Druntime=true` publishes the same module from the same file with the natives
reached through the platform loader instead of the link line. It is orthogonal
to `-Dlinkage`: the native artifact is compiled and installed either way, and
the flag decides only how the facade gets at it. Linked calls stay direct.

`predicates.runtime_loaded` is `true` in that build and `false` in a linked one,
so a consumer that supports both writes `if (comptime
predicates.runtime_loaded)` and only the branch it chose is analysed.
`predicates.load(source)` takes a `predicates.LoadSource` — an absolute
`.{ .path = ... }`, or a `.{ .system = ... }` basename the platform loader
searches — and fills one table that lives as long as the process. Before a
successful `load`, reaching any routed function or any of the fifteen globals
stops the program with a message naming the symbol: no implicit load, no
fallback to a linked copy, no reset. On a linked build `load` is a misuse that
stops the program and names the option that produces the other configuration.

`load` is also where a provider is checked rather than trusted. The candidate
is not published until its own `exactinit()` has run and the constants it wrote
match IEEE 754 binary64 — `epsilon == 2^-53`, `splitter == 2^27 + 1` and
`resulterrbound` equal to what that epsilon derives — so a provider whose
symbols resolve but whose globals are not its own writable storage is refused
instead of loaded.

A test run in this configuration names its provider in the environment,
`PREDICATES_TEST_PROVIDER`, because Zig's test runner owns the command line and
a test binary has no `main` to parse. `zig build smoke` and the consumer
program do have one and accept `--provider <path>`. There is no default path
and no search: an unnamed provider in a runtime-loading build is an error, not
a fallback.

**Observed 2026-10-04/05.** The option, its default, the two configurations,
the load-time check and the provider contract above are read out of `build.zig`,
`runtime/` and `src/root.zig`; the configuration itself was then run. The
own-loaded eight-cell row above is that run — this tree's own
`libpredicates.so` reached through `-Druntime=true`, exit 0 in all eight at
`47/47` — receipt
`loaded-final-evidence/20261004T232823091897Z-23133/run.json`. What that receipt
does not reach is listed under "Still pending for this migration" above.

### From C

`dep.artifact("predicates")` is the compiled library and `predicates.h` is
already on its include path, because the artifact installs the header. From a
Nix output the same two files are at `$out/include/predicates.h` and
`$out/lib`.

The install also writes a pkg-config file, generated by the build graph from
these sources: `$prefix/lib/pkgconfig/predicates.pc`, with
`Cflags: -I${includedir}`, `Libs: -L${libdir} -lpredicates` and an empty
`Libs.private`. The floating-point flags are deliberately absent from it — they
apply to `src/predicates.c`, which this build compiles with them, not to a
consumer's own objects — and nothing from libm is called, so `-lm` is not named
as a dependency this library does not have.

There is no soname series. The shared object is plain `libpredicates.so`, not
`libpredicates.so.0` with a symlink, because the build sets no `.version`:
upstream has no version, tag or release series, and `0.1.0` in `build.zig.zon`
is this fork's own. One `.pc` is therefore correct for both linkage variants,
because it takes no linkage argument.

The header documents the compile requirements it applies to. A C consumer that
compiles its own translation unit against this library must not fuse multiply
and add, for the reason in the next section.

### With Nix

`package.nix` is the single source-only derivation; `flake.nix` and `devenv.nix`
both call it, so they cannot describe different packages.

```
nix build .#static    # the SDK's existing linkage policy, also the default
nix build .#shared    # the same derivation built with -Dlinkage=dynamic
```

The output installs the native artifact, the public header, the generated
pkg-config file, and `NOTICE.md`, `FORK-LICENSE.md` and `UPSTREAM.md` under
`$out/share/licenses/predicates/`. `build.zig` owns that whole layout and the
Nix derivation adds nothing by hand, so `nix build` and `zig build install`
produce one layout by construction rather than two kept in agreement by hand.

Nothing is downloaded at build time, no sibling checkout is referenced, and no
host path, user name or store path appears in any committed file.

The flake's inputs are locked. `flake.lock` ships with the package and pins
`nixpkgs` to `c7def046b9a883d46974757852106483d741586f`, the same revision
`flake.nix` already names in its `inputs.nixpkgs.url`. It is fork work, not
upstream bytes — the canonical distribution is one C file and ships no flake at
all — so `UPSTREAM-BASELINE.sha256` declares it as a fork-owned path rather
than listing it among the carried upstream digests. There is no `devenv.lock`:
`devenv.yaml` states its own pin, and naming an absent lock would make a
fetched package hash a missing entry.

`devenv shell` is the canonical development environment. It installs tools
only, so entering the shell does not build this SDK; the package is reached
through the lazy outputs `devenv build outputs.static` and
`outputs.shared`, which call the same `package.nix`. Its `sdk:`-namespaced tasks
run the commands below, from this directory whatever directory they are started
in: every task body changes here first, because devenv runs a task with the
working directory the environment was entered from, and that is the devenv
project rather than this checkout.

## Commands

```
zig build            # compile the C library and the example
zig build test       # run the tests
zig build smoke      # run the deterministic example
zig build check      # compile the five buildable targets; x86_64-windows-gnu is refused by name
cd consumer && zig build run
tools/check-provenance.sh   # upstream digest, licence notice and byte baseline

zig build -Druntime=true     # reach the natives through the platform loader
zig build test -Druntime=true        # needs PREDICATES_TEST_PROVIDER
zig build smoke -Druntime=true -- --provider /abs/path/libpredicates.so
```

The `sdk:`-namespaced Zig build tasks supply `-j8`,
`--cache-dir "$ZIG_LOCAL_CACHE_DIR"` and `--summary all`. They initialize missing
cache variables themselves; `devenv tasks run` does not source `enterShell`.
Exported cache values win. Missing values use `$XDG_CACHE_HOME`, then `$TMPDIR`;
if neither can supply them, the command refuses rather than use Zig's defaults.
`sdk:build` and `sdk:build-shared` install to
`$ZIG_LOCAL_CACHE_DIR/predicates/static` and `…/shared`, not `./zig-out`.
The test, smoke, check and consumer steps install nothing and need no prefix.
Generated task programs retain `"$@"` forwarding, including caller prefixes,
but devenv 2.4 `tasks run` cannot forward arguments to them. Direct invocation
can supply `--prefix P`, `-p P` or `--prefix=P`, which the delivery helper honours.

`zig build check` walks `supported_check_targets` and is green over all five of
them; `x86_64-windows-gnu` is not one of them. `refused_check_targets` names it,
and asking for it by name — `zig build check -Dtarget=x86_64-windows-gnu` — ends
at `refuseTarget` with the printed reason, before any graph is configured and
with no compiler invoked. CI is the one place that still runs the refused row:
its cross job passes an explicit `-Dtarget` per cell and marks that cell
`continue-on-error`. `FORK-NOTES.md` section 21 records what the canonical source
cannot compile there and why the failure is not repaired here.

## Notes for every caller

**Call `init()` first.** Upstream's `exactinit()` computes constants that every
robust predicate depends on, and before it runs they are zero. Calling it from
two threads at once is a data race. `init()` runs it exactly once, is safe from
any thread, and publishes that work so a thread finding it already done still
sees the constants. A missed initialization is a programmer precondition:
an ordinary comparison panics at the call site in Debug, ReleaseSafe,
ReleaseFast and ReleaseSmall before any native call or constant read.
The `*fast` routines answer to the same rule even though the C behind them
reads none of those globals.

**Do not let the compiler fuse multiply and add.** `Two_Product` is an
error-free transformation that assumes each operation rounds separately; an FMA
breaks it and the predicates start returning wrong signs with no diagnostic.
This package passes `-ffp-contract=off` for you. If you compile `predicates.c`
yourself, pass it too.

**Keep the geometry in a normal range.** The predicates decide whether to fall
through to exact arithmetic using an ordinary floating-point expression, and
that expression underflows on subnormal coordinates and overflows near
`floatMax`. This is read out of `src/predicates.c` (`orient2d` computes
`detleft = (pa[0] - pc[0]) * (pb[1] - pc[1])` before it decides anything) and
is recorded as `SOURCE-CONFIRMED`; the returned value at those extremes has
not been probed on this host, so treat the specific numbers as arithmetic
derived from the source rather than as an observed run. `FORK-NOTES.md` has
the derivation, and the argument for not adding a guessed range check.

Outside that range a zero answer is not proof of exact degeneracy. A product
below the smallest subnormal returns zero, and a filter whose two products
overflow takes `inf - inf`; the sign channel maps both, plus any NaN, to
`Sign.zero`.

**The fifteen C globals are state, not constants.** `splitter`, `epsilon` and
the thirteen error bounds are written by `exactinit()` and read by every robust
predicate. Anything that reaches this library through a runtime loader must
address them through that same loaded provider; addressing them against another
copy of the library would read one translation unit's zeros while the
predicates compute with another's constants. `NOTICE.md` item 12 records this
as a requirement on the loading contract.

## What the tests compare against

Not the library itself. `test/exact_oracle.zig` evaluates each determinant in
exact integer arithmetic, after clearing denominators with a common power of two.
It shares no code, no error bound and no filtering with the C, so a sign it
disagrees with is a real fault. `FORK-NOTES.md` has the derivation.

## Licence

`src/predicates.c` is **Public domain**, as dedicated by the author in the file
header. There is no `LICENSE` file because there is no licence to grant;
`NOTICE.md` reproduces the notice and lists every modification this fork makes.
The C is redistributed unmodified.

The files this fork wrote — everything listed in `NOTICE.md` other than
`src/predicates.c`, including this README, the build, the facade, the header,
the tests and the Nix packaging — are also released into the public domain,
matching the primary upstream term. The owner authorized that choice for this
project's fork-authored additions; the grant, its basis and its
`LicenseRef-PublicDomain` SPDX identifier are in `FORK-LICENSE.md`. No upstream
copyright attaches to that material and no upstream permission is claimed over
it.