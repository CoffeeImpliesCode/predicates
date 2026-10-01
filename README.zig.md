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

For a C consumer, `dep.artifact("predicates")` is the static library, and
`predicates.h` is already on its include path because the artifact installs the
header.

## Platform support

The library links libc, and one of its dependencies is POSIX `random()`, called
by the six routines `predicates.c` exposes for generating random floating-point
values. Every C library in the supported target set provides it.

`x86_64-windows-gnu` is not a supported target. mingw-w64 and the UCRT have no
`random()`, so `src/predicates.c` does not compile there, and this fork does not
patch the canonical source or ship a substitute generator to make it. If you
are targeting Windows, `zig build check` reproduces the failure and
`FORK-NOTES.md` section 21 explains it; the obstacle is upstream's source, so a
project that compiles `predicates.c` directly meets the same one.

## Initialization

```zig
predicates.init();
```

Call it once per process, before any predicate, at start-up. It runs upstream's
`exactinit()` exactly once under an atomic once-guard, so calling it from two
threads at the same moment is safe: one runs it, the other waits.

Do not skip it. Before `exactinit()` runs, `splitter` and the roundoff error
bounds are zero and every robust predicate returns a wrong answer. In Debug and
ReleaseSafe a missed initialization trips an assertion at the call site; in
ReleaseFast the assertion is compiled out, as assertions are everywhere in Zig.

`predicates.isInitialized()` reports whether it has happened.

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
    .zero => return error.Degenerate, // exactly on the circle
}
```

`incircle` and `insphere` are oriented predicates, not membership tests: reverse
the order of the first three points and the answer flips. A membership test
needs the points in counterclockwise order, which is the usual Delaunay
convention.

### Non-finite input

Every facade predicate returns `error.NonFiniteCoordinate` if any coordinate is
NaN or infinite. Upstream has no such contract and does not detect the case; a
NaN propagates through its filter comparisons and the result is not the
determinant of anything. The contract is a facade addition and does not apply to
the `c` escape hatch.


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

Everything is there: the expansion arithmetic, the `*exact` and `*slow`
reference implementations, the `*adapt` engines (helpers that take a
caller-computed error bound), the random-value helpers, and the C globals
`splitter`, `epsilon` and the thirteen error bounds. This is the unmodified
upstream ABI; nothing in it is wrapped, renamed or reinterpreted.

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
by `exactinit()`, which `init()` runs exactly once.

## Building this package's own gates

```
zig build            # compile the C library and the example
zig build test       # run the tests
zig build smoke      # run examples/smoke.zig
zig build check      # attempt all six targets; five build, x86_64-windows-gnu fails
cd consumer && zig build run
```

`consumer/` is a separate package that consumes this one through
`dep.module("predicates")` and checks hand-computed answers. It exists to catch
the failure this package's own tests cannot see: a module that builds from the
inside and does not resolve from the outside.

`.github/workflows/verify.yml` runs the four jobs — provenance, native, cross,
consumer. The provenance job recomputes the SHA-256 of `src/predicates.c`
against the value in `UPSTREAM.md` and checks that the public-domain notice
survives in the source, the notice file and the README. It deliberately does not
compare declaration names between `include/predicates.h` and the C source: a
name-set comparison is a source-text test that fails when either side is
reformatted and passes when a declaration is retyped, so the header's real
coverage comes from the compile and link gates instead — `zig build test` links
the translated declarations and calls them, and the consumer job links and runs
them from a package that did not write the header.

The cross job makes those per-target attempts too, and marks only
x86_64-windows-gnu `continue-on-error`, as the one target this fork has
evidence for being unbuildable. No other target is tolerated, and no target is
removed from the matrix.