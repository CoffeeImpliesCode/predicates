# Using predicates from Zig

Requires Zig 0.16.0. See `README.md` for what the library is and `UPSTREAM.md`
for where the C came from.

## Adding the dependency

This package is a private downstream and has no published revision, so the form
that works today is a relative path, which is what `consumer/build.zig.zon`
uses:

```zig
// build.zig.zon
.dependencies = .{
    .predicates = .{ .path = "../predicates" },
},
```

Once a revision is published and a real `zig fetch` hash exists, a consumer can
switch to

```zig
.predicates = .{
    .url = "<the published remote URL>",
    .hash = "<the hash `zig fetch` prints for a real commit>",
},
```

and should pin a commit rather than a branch: this is a geometric kernel, and a
moved sign is not a thing you want to discover downstream. No concrete hash is
written here because none has been printed for a published revision.

Then, in `build.zig`:

```zig
const dep = b.dependency("predicates", .{ .target = target, .optimize = optimize });

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true, // the C includes <stdio.h> and calls POSIX random()
});
exe_mod.addImport("predicates", dep.module("predicates"));
```

`dep.module("predicates")` is enough. It carries the compiled C with it, so
there is nothing to install and nothing to find on the system.

For a C consumer, `dep.artifact("predicates")` is the native artifact — the
static archive by default, or a shared object under `-Dlinkage=dynamic` — and
`predicates.h` is already on its include path because the artifact installs the
header. The install also writes a generated `lib/pkgconfig/predicates.pc`, so a
C consumer's build system can ask where the library is instead of guessing
`-lpredicates`. It carries `Cflags: -I${includedir}` and
`Libs: -L${libdir} -lpredicates`, and an empty `Libs.private`: the only external
call this library makes is POSIX `random()`, which is libc and is implicit for a
C consumer, and nothing from libm is called.

### With Nix

`package.nix` is a source-only derivation that builds this repository and
nothing else, and both `flake.nix` and `devenv.nix` call it, so the two entry
points cannot describe different builds.

```nix
# flake.nix
inputs.predicates.url = "path:/path/to/predicates";

# or, from a checkout, without adding an input:
nix build .#static   # the SDK's existing linkage policy, also the default
nix build .#shared   # the same derivation with -Dlinkage=dynamic
```

The output installs the native artifact under `$out/lib`, the public header at
`$out/include/predicates.h`, the generated `lib/pkgconfig/predicates.pc`, and
`NOTICE.md`, `FORK-LICENSE.md` and `UPSTREAM.md` under
`$out/share/licenses/predicates/`. `build.zig` owns that whole layout and the
derivation adds nothing by hand, so `nix build` and `zig build install` produce
one layout by construction.

The derivation adds no C flags of its own: `build.zig` owns those, and restating
them in Nix would create a second place where the floating-point requirements
could disagree.

There is no promise of a statically linked closure here. The variant names say
which artifact this build produced; what a consumer ends up linking is a
property of the consumer, not of this package.

There is no soname series. The build deliberately sets no `.version`, so the
shared object is plain `libpredicates.so` rather than `libpredicates.so.0` with
a symlink: upstream has no version, tag or release series to derive an ABI major
from, and `0.1.0` in `build.zig.zon` is this fork's own number. A consumer
linking the shared variant gets `-lpredicates` and the generated `.pc`; neither
needs a major number, and one `.pc` is correct for both linkage variants
because it takes no linkage argument.

`devenv shell` is the canonical development environment. It installs tools
only, so entering the shell does not build this SDK; the package is reached
through the lazy outputs `devenv build outputs.static` and `outputs.shared`,
which call the same `package.nix`. Its `sdk:`-namespaced tasks run the commands
listed at the end of this file, and each one changes to this repository first,
so a task behaves the same whichever directory it is started in. The two that
install, `sdk:build` and `sdk:build-shared`, install under
`$ZIG_LOCAL_CACHE_DIR` rather than into the working tree.

## Platform support

The library links libc, and one of its dependencies is POSIX `random()`, called
by the six routines `predicates.c` exposes for generating random floating-point
values. Every C library in the supported target set provides it.

`x86_64-windows-gnu` is not a supported target. mingw-w64 and the UCRT have no
`random()`, so `src/predicates.c` does not compile there, and this fork does not
patch the canonical source or ship a substitute generator to make it. If you
are targeting Windows, `zig build check -Dtarget=x86_64-windows-gnu` refuses that
target and prints the reason without invoking a compiler on it, and
`FORK-NOTES.md` section 21 records what the compile produced when the attempt was
made. The obstacle is upstream's source, so a project that compiles
`predicates.c` directly meets the same one.

The shared variant has a second, independent reason for the same target. Even
if the source did compile for a PE/COFF target, `-Dlinkage=dynamic` would
produce a DLL that exports nothing: a PE/COFF image exports a symbol only when
that symbol is marked, and all forty externally visible definitions and all
fifteen globals in `src/predicates.c` carry external linkage with no export
decoration. `zig build check -Dlinkage=dynamic` compiles the same five buildable
rows against that shared object and refuses the sixth by name, exactly as the
static configuration does. Marking those symbols would mean editing the
canonical file, which is the one thing this fork does not do for a target.

## Initialization

```zig
predicates.init();
```

Call it once per process, before any predicate, at start-up. It runs upstream's
`exactinit()` exactly once under an atomic once-guard, so calling it from two
threads at the same moment is safe: one runs it, the other waits. Completion is
published with a release store, and every path that observes it — the fast path
in `init()`, the spin loop, and `isInitialized()` — reads that store with an
acquire load, so a thread that finds the work already done also sees the
constants `exactinit` wrote.

Do not skip it. Before `exactinit()` runs, `splitter` and the roundoff error
bounds are zero and the robust C predicates have no sign guarantee. Missing
`init()` is a programmer precondition: an ordinary comparison panics before
any native call or constant read in Debug, ReleaseSafe, ReleaseFast and
ReleaseSmall. Non-finite coordinates instead produce a checked return in
every mode.

The `*fast` routines require initialization too, even though the C functions
behind them read none of these globals. That is a stricter facade precondition
than upstream needs, chosen so one rule covers the whole surface.

`predicates.isInitialized()` reports whether it has happened, reading the same
acquire load. A `false` answer says only that this caller did not observe
completion; another thread may be inside `exactinit()` right now.

## Predicates

```zig
const predicates = @import("predicates");

const Point2 = predicates.Point2;
const Point3 = predicates.Point3;
```

Each takes its points by value, allocates nothing, and returns an error union.

| Function | Arguments | Positive means |
|---|---|---|
| `orient2d` | three `Point2` | counterclockwise |
| `orient3d` | four `Point3` | the fourth point is below the plane of the first three |
| `incircle` | four `Point2` | the fourth point is inside the circle, given the first three counterclockwise |
| `insphere` | five `Point3` | the fifth point is inside the sphere, given the first four ordered so `orient3d` on them is positive |

Each has a `*Sign` wrapper returning `Sign{ .negative, .zero, .positive }`, and a
`*fast` counterpart. Use the `*Sign` wrappers: the unsuffixed routines guarantee
the sign and nothing else, and only inside the range described below.

```zig
switch (try predicates.incircleSign(a, b, c, d)) {
    .positive => inside = true,
    .negative => inside = false,
    .zero => return error.Degenerate, // see the range note below
}
```

`incircle` and `insphere` are oriented predicates, not membership tests: reverse
the order of the first three points and the answer flips. A membership test
needs the points in counterclockwise order, which is the usual Delaunay
convention.

### Non-finite input

Every facade predicate returns `error.NonFiniteCoordinate` if any coordinate is
NaN or infinite, in every optimize mode, because that check is an ordinary
comparison rather than an assertion. Upstream has no such contract and does not
detect the case; a NaN propagates through its filter comparisons and the result
is not the determinant of anything. The contract is a facade addition and does
not apply to the `c` escape hatch, and it says nothing about scale: finite
coordinates can still form products outside the double range.

### The range where the guarantee holds

The exact sign is guaranteed for well-scaled input. It is not guaranteed at the
ends of the double range, because the predicates decide *whether* to use exact
arithmetic with an ordinary floating-point expression, and that expression dies
first. Read out of `src/predicates.c` — `orient2d` begins

```c
  detleft = (pa[0] - pc[0]) * (pb[1] - pc[1]);
  detright = (pa[1] - pc[1]) * (pb[0] - pc[0]);
  det = detleft - detright;
```

and only afterwards compares `det` against `ccwerrboundA * detsum`:

* With `pa = (2^-1074, 0)`, `pb = (0, 2^-1074)`, `pc = (0, 0)`, `detleft` is
  `2^-2148`. The smallest binary64 subnormal is `2^-1074`, so that product is
  below the representable range and `detleft` is neither greater nor less than
  zero, which is the branch that returns `det` directly. `det` is then zero,
  and the exact determinant of that configuration is `2^-2148`, positive.
* With coordinates near `floatMax` that product overflows to infinity. If only
  one of the two products overflows, the other is `<= 0.0`, so the routine takes
  the early `return det` with an infinite magnitude whose sign is still the
  correct one. If both overflow with the same sign, `detsum` is infinite,
  `errbound` is infinite, and `det` is `inf - inf`. NaN compares false in both
  directions, so the filter cannot resolve it and `orient2dadapt` is entered
  with that NaN and an infinite `detsum`.

`incircle` and `insphere` reach the same edge through their lift terms, which
are sums of squares of differences.

Both are `SOURCE-CONFIRMED` arithmetic read out of the C file and the branch
structure around it; neither is an executed result. The first is settled by the
branch. For the second, what the adaptive engine does with the NaN has not been
probed on this host, so no outcome is claimed for it, and `FORK-NOTES.md` keeps
the derivation rather than a run.

That is also where the sign channel stops being informative. `Sign.zero` means
the returned value was neither greater nor less than zero: inside the domain
above that is exact degeneracy, and outside it the same answer covers the
underflowed zero and an overflowed NaN. A `.zero` establishes exact degeneracy
only for well-scaled input.

Scale the geometry so the products stay normal. This package does not add a
range check for it, because upstream states no threshold and a guess that is
too aggressive rejects inputs the C handles correctly; `FORK-NOTES.md` has the
full argument.

### The non-robust variants

`orient2dfast`, `orient3dfast`, `incirclefast` and `inspherefast` are upstream's
deliberately non-robust versions: no error analysis. On near-degenerate input
they return a wrong sign, and the test suite contains a configuration where they
provably do. They are exposed because knowing when they fail is useful, not
because they are safe.

## The raw C

```zig
const c = predicates.c;
```

Use this facade route, not `dep.module("c")`: the translated module is private
and the facade carries its native linkage or runtime dispatch.

Everything is there: the expansion arithmetic, the `*exact` and `*slow`
reference implementations, the `*adapt` engines (helpers that take a
caller-computed error bound), the random-value helpers, and the C globals
`splitter`, `epsilon` and the thirteen error bounds. This is the unmodified
upstream ABI; nothing in it is wrapped, renamed or reinterpreted.

Going through `predicates.c` gives up everything the facade adds: no
non-finite rejection, no initialization check, and upstream's own habit of
needing `exactinit()` before anything else, with a data race if two threads
make that call at once.

The raw `*exact` and `*slow` predicates take only points and own their local
scratch (`src/predicates.c:1446-1456,1491-1503,1802-1809,2502-2513,3617-3639`);
there are no caller-owned `expanarg` arrays. The returned magnitude is a rough
determinant approximation, not a permanent scaled down: `detsum` and the
permanent scale error bounds (`src/predicates.c:1575-1578,1627-1652`).
The contrary comments in `include/predicates.h:153-161` remain unchanged under
the public-native-header preservation constraint.

```zig
var e = [2]f64{ std.math.ldexp(@as(f64, 1.0), -60), 1.0 };
var out: [4]f64 = undefined;
const n = c.grow_expansion_zeroelim(2, &e, 2.0, &out);
```

The `@as(f64, 1.0)` is required, not decoration. Zig 0.16 ships
`std.math.ldexp(x: anytype, n: i32) @TypeOf(x)`: two arguments, and the body
reads `@typeInfo(T).float.bits` from the first one. A bare `1.0` is a
`comptime_float`, which has no `.float` union field to read, and the call fails
to compile. Call it as `std.math.ldexp(@as(f64, 1.0), -60)` and the result is
the exact power of two, which `std.math.pow` does not promise for these
exponents.

## Threading

The predicates themselves allocate nothing and keep no state, so they are safe to
call from any thread once `init()` has returned. The C globals are written only
by `exactinit()`, which `init()` runs exactly once, and the release store that
publishes that work is read with an acquire load on every path, so a thread that
sees initialization done also sees the constants. A caller that reaches the C
through `predicates.c` gets no such guard: `exactinit()` there is upstream's own
and two threads calling it at once is a data race.

That ordering is a source-level guarantee. No weak-memory or thread-sanitizer
run has been made for this package, and this README claims none.

## Linked, and loaded at runtime

Calls made through `dep.module("predicates")` are **linked**: the facade calls
the compiled C directly, and every symbol resolves at link time. That is the
route everything above describes.

This SDK also has a runtime-loading route, where the native library is opened
from an explicit source — an absolute file path, or a system basename, chosen
by the caller, with no fallback from one to the other — and the calls go
through a table resolved from that handle. Selection is explicit and happens
once; a failed open closes and never publishes, an explicit retry is allowed
and an automatic one is not, and the same request repeated is idempotent while
a different request after a successful load is rejected.

**Observed, in eight configurations and against this tree's own shared object.**
`zig build test smoke install -Druntime=true`, static × dynamic crossed with
Debug, ReleaseSafe, ReleaseFast and ReleaseSmall, with `PREDICATES_TEST_PROVIDER`
naming an own `libpredicates.so` the same tree installed (`provider.kind: "own"`):
exit 0 in all eight, `Build Summary: 17/17 steps succeeded; 47/47 tests passed` in
every cell. Receipt `loaded-final-evidence/20261004T232823091897Z-23133/run.json`,
2026-10-04. The linked route over the same eight configurations reports
`46/47 tests passed (1 skipped)`, because one test declares
`if (comptime !predicates.runtime_loaded) return error.SkipZigTest;`
(`test/raw_surface_test.zig:563`) and that is the test the loaded cells run.

What that does **not** cover is named in `README.md`: a system basename source, a
runtime-loaded `smoke` run driven by an explicitly named `--provider`, the
installed C consumer, the materialised package consumer loaded from a fetched
copy, and the `-Druntime=true` / `-Dlinkage=dynamic` `check` rows. All four are
`PENDING-VERIFICATION`. The provider used above is this repository's own shared
object named by absolute path; it is not an independent external provider and the
two are never merged into one claim.

### The fifteen globals are the reason this library is a special case

`splitter`, `epsilon` and the thirteen error bounds are not constants. They are
file-scope mutable data that `exactinit()` writes and that every robust
predicate reads. They are also part of the exported surface, so a loaded
provider can see them.

The rule that follows is narrow and not negotiable: **a loaded call must
address those globals through the same provider it resolved its functions
from, and initialization must go through that provider too.** If the functions
come from a loaded library and the globals come from a linked one, the
predicates run against a second copy's constants — and before that copy's
`exactinit()` has run, those constants are zero, which is the failure mode
`init()` exists to prevent. The two sets of symbols would also collide in one
process, so one of the two initialization contracts would silently be the one
that applies.

This is recorded in `NOTICE.md` item 12 as well, because it is the property
most likely to be broken by a later, unrelated-looking change to the loader.

## Building this package's own gates

```
zig build            # compile the C library and the example
zig build test       # run the tests
zig build smoke      # run examples/smoke.zig
zig build check      # compile the five buildable targets; x86_64-windows-gnu is refused by name
zig build -Dlinkage=dynamic   # the same graph, producing a shared object
zig build check -Dlinkage=dynamic   # the same five buildable targets against that shared object
cd consumer && zig build run
tools/check-provenance.sh   # upstream digest and licence notice
```

`consumer/` is a separate package that consumes this one through
`dep.module("predicates")` and checks hand-computed answers. It exists to catch
the failure this package's own tests cannot see: a module that builds from the
inside and does not resolve from the outside.

`tools/check-provenance.sh` is the provenance gate: it recomputes the SHA-256 of
`src/predicates.c` against the value in `UPSTREAM.md` and checks that the
public-domain notice survives in the source, in `NOTICE.md` and in the README.
It compiles nothing and runs nothing.

`.github/workflows/verify.yml` runs the four jobs — provenance, native, cross,
consumer. Its provenance job carries its own copy of the same two checks rather
than calling the script; the script is the implementation of record, and the
duplication is a drift risk with nothing to detect the drift, so collapsing the
job onto the script is the first thing to change when that file is next edited.
Neither gate deliberately compares declaration names between
`include/predicates.h` and the C source: a name-set comparison is a source-text
test that fails when either side is
reformatted and passes when a declaration is retyped, so the header's real
coverage comes from the compile and link gates instead — `zig build test` links
the translated declarations and calls them, and the consumer job links and runs
them from a package that did not write the header.

The cross job makes those per-target attempts too, and marks only
x86_64-windows-gnu `continue-on-error`, as the one target this fork has
evidence for being unbuildable. No other target is tolerated, and no target is
removed from the matrix.