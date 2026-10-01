# predicates

Shewchuk's adaptive-precision geometric predicates, packaged for Zig 0.16.

`orient2d`, `orient3d`, `incircle` and `insphere`, in the versions that use
exact arithmetic when the floating-point filter cannot decide. What upstream
guarantees is the **sign**, and only for finite coordinates whose filtered
products stay inside the double range; the range condition is real, is spelled
out under "Three things that bite" below, and is not enforced by this package.
The magnitude is a scaled approximation of the permanent and should not be
read as a determinant.

## What is here

The library is one C file, `src/predicates.c`, fetched from the Carnegie Mellon
URL below and unmodified since. Everything else in this repository is the
packaging: a Zig build, a declaration header, a small facade, tests, and a
runnable example.

| | |
|---|---|
| Upstream | <https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c> |
| Revision | May 18, 1996, the date in the file header. There is no tag or commit: the file is served from an AFS directory, not a repository. |
| SHA256 | `f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029`, recomputed over the copy in this tree |
| Licence | Public domain, by the author's own dedication. See `NOTICE.md`. |

The digest in that table is the one CI recomputes on every run against
`src/predicates.c`, so the table and the compiled file cannot drift apart
unnoticed. It is not a claim about what the remote serves at any later moment.

`UPSTREAM.md` has the full provenance and the sync procedure. `FORK-NOTES.md`
has the problems met while packaging this and what was done about each.

## Using it from Zig

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

`README.zig.md` has the build snippet, the dependency line, and the rest of the
facade.

## Three things that bite

**Call `init()` first.** Upstream's `exactinit()` computes constants that every
predicate depends on, and before it runs they are zero. Calling it from two
threads at once is a data race. `init()` runs it exactly once and is safe from
any thread.

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

## Platform support

`zig build check` compiles and links the C source, the facade, the tests and
the example for x86_64-linux-gnu, aarch64-linux-gnu, aarch64-macos-none,
riscv64-linux-gnu and wasm32-wasi, and runs none of them. A green `check` is
compile evidence, not a claim that a cross-built binary executed. The step
also attempts x86_64-windows-gnu, which fails; that target is below.

`x86_64-windows-gnu` does not build, and the reason is upstream's rather than
this package's. Six published routines — `doublerand`, `narrowdoublerand`,
`uniformdoublerand`, `floatrand`, `narrowfloatrand` and `uniformfloatrand` —
call `random()`, which is POSIX rather than ISO C and which neither mingw-w64
nor the UCRT provides. The same compile also reports every old-style function
definition in the 1996 source as an error, which the five targets above do
not. Supplying a `random()`, or rewriting those definitions, would both mean
editing the canonical file whose SHA256 is the reason to trust this package,
so the target is documented rather than faked.

It is not dropped from the matrix: `zig build check` attempts all six and exits
non-zero on the sixth, and CI makes the same per-target attempts, marking only
x86_64-windows-gnu `continue-on-error` because it is the one target for which
this fork has evidence that the source cannot build.
`FORK-NOTES.md` section 21 has the diagnostics, the toolchain headers that
settle the question, and the options that were refused. A consumer that needs
this library on Windows is blocked by upstream's source, not by a policy here:
compiling `predicates.c` itself against a C library without POSIX `random()`
meets the same wall.

## Commands

```
zig build            # compile the C library and the example
zig build test       # run the tests
zig build smoke      # run the deterministic example
zig build check      # attempt all six targets; five build, x86_64-windows-gnu fails
```

The `check` step exits non-zero today because of that sixth target.
`FORK-NOTES.md` section 21 records exactly how it fails and why the failure is
not repaired here.

## What has actually been run

The commands above are this package's interface, not a record of results. What
has been observed so far, on this host and with the pinned compiler:

| Gate | Result |
|---|---|
| `zig fmt` over the build, source, test, example and consumer files | clean, no output |
| `zig build`, first observed run | stopped while compiling `examples/smoke.zig`: `std.math.ldexp` was handed a `comptime_float`, which its body cannot reflect on |
| `zig build`, second observed run | got past that call and stopped at `examples/smoke.zig:136`, where an error value was being formatted with `@tagName`, which applies to a type rather than to a value |
| `zig build test` (Debug) | 39 tests passed |
| `zig build test -Doptimize=ReleaseSafe` | 39 tests passed |
| `zig build smoke` | ran to completion and printed its deterministic output, including `orient2d one-ulp cancellation, robust negative` against `orient2d one-ulp cancellation, fast zero`: the same configuration where the robust filter falls through to exact arithmetic and the non-robust variant rounds to zero |
| `zig build check` | attempted all six targets: five compiled and linked, x86_64-windows-gnu failed with the 39 diagnostics in `FORK-NOTES.md` section 21, and the step exited non-zero |
| `consumer/` (`zig build run`) | not run |
| `.github/workflows/verify.yml` | not run locally; CI executes it |

The two `zig build` rows are history: they record what the first two runs in
this workspace reported, and both diagnostics were in the example rather than
in the library, because the C archive and the translated header had compiled
by the time each run stopped.

Nothing above is a claim about a cross-built binary. No target other than the
host has been executed here, and the `check` row is compile and link evidence
only.

## What the tests compare against

Not the library itself. `test/exact_oracle.zig` evaluates each determinant in
exact integer arithmetic, after clearing denominators with a common power of two.
It shares no code, no error bound and no filtering with the C, so a sign it
disagrees with is a real fault. `FORK-NOTES.md` has the derivation.

## Licence

Public domain, as dedicated by the author in the file header. There is no
`LICENSE` file because there is no licence to grant; `NOTICE.md` reproduces the
notice and lists every modification this fork makes. The C is redistributed
unmodified.