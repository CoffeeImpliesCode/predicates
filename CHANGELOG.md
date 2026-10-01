# Changelog

Fork-only history. Everything upstream did to `predicates.c` is upstream's and
is not recorded here; this file records what changed around it in this
repository. `NOTICE.md` has the numbered list of behavioural differences and
`UPSTREAM.md` has the source provenance.

The format follows Keep a Changelog. Versions are the package's own.

## [Unreleased]

Corrections landed after the first packaging pass and before any publication.
Nothing in this section is a gate result.

### Changed

* Every caller of `std.math.ldexp` uses Zig 0.16's shipped two-argument form,
  `std.math.ldexp(x: anytype, n: i32) @TypeOf(x)`, with the first argument typed:
  `std.math.ldexp(@as(f64, 1.0), -52)` for an `f64` fixture and
  `std.math.ldexp(@as(f32, 1.0), 100)` for an `f32` one. A bare `1.0` is a
  `comptime_float`, whose type has no `.float` field for the function body to
  read; the observed `zig build` diagnostic in `examples/smoke.zig` was exactly
  that. The same mistake was still present in `test/expansion_test.zig`,
  `test/predicates_test.zig` and `consumer/src/main.zig`, and
  `test/exact_oracle.zig` still used the obsolete three-argument
  `ldexp(f64, m, e)`. All of them now use the typed two-argument form.
  `PENDING-VERIFICATION`.
* `README.zig.md` documents the dependency as a relative path, which is what
  `consumer/build.zig.zon` uses and what works while this repository is
  private. The previous snippet named a remote URL and a placeholder hash for a
  revision that has not been published.
* `README.md`, `README.zig.md` and `FORK-NOTES.md` state the extreme-exponent
  limitation of the filtered first step as `SOURCE-CONFIRMED` arithmetic read
  out of `src/predicates.c`, with the value actually returned at those extremes
  left to a probe that has not been run.
* `zig build check` attempts all six requested targets rather than a subset of
  them: x86_64-linux-gnu, aarch64-linux-gnu, aarch64-macos-none,
  riscv64-linux-gnu and wasm32-wasi compile and link, and x86_64-windows-gnu
  fails with the 39 diagnostics in `FORK-NOTES.md` section 21, so the step
  exits non-zero. The target is not dropped from the matrix, and CI marks only
  that one `continue-on-error`, as the single target with evidence for being
  unbuildable. `FORK-NOTES.md` section 21 has the diagnostics, the toolchain
  headers that settle the question, and the options that were refused:
  supplying a `random()`, declaring one with no definition behind it,
  suppressing the non-prototype diagnostic, or editing the canonical source.
  None is taken, so no flag spoofs a platform this package does not support.
* `README.md`, `README.zig.md`, `UPSTREAM.md` and `NOTICE.md` state the
  x86_64-windows-gnu boundary for consumers and name it as upstream's POSIX
  `random()` dependency rather than as a policy of this package.

### Fixed

* The prose counted "twelve error bounds" where `exactinit()` writes thirteen
  (`resulterrbound`, `ccwerrbound` A/B/C, `o3derrbound` A/B/C, `iccerrbound`
  A/B/C and `isperrbound` A/B/C), alongside `splitter` and `epsilon`. The
  header declared all fifteen and the compiled archive defined all fifteen; only
  the count in prose was wrong. `FORK-NOTES.md` section 8 carried the same count
  and now names them and cites `src/predicates.c:361-368` for the declarations
  and `src/predicates.c:670-682` for the assignments.
* The changelog claimed the behavioural tests covered "the edges of the double
  range including subnormals". The wide-range fixtures deliberately stay inside
  the range where the filtered products are normal; the only subnormal fixture
  is a collinear case whose exact determinant is zero. The entry below now says
  what the tests do.
* `test/exact_oracle.zig` rebuilt each decomposed coordinate and compared the
  result with `@bitCast`, so `-0.0` could never round-trip: `decompose` maps it
  to `m = 0, e = 0`, which rebuilds `+0.0`, and `+0.0` and `-0.0` have different
  bit patterns. The oracle never looks at the sign of a zero, so the comparison
  is now on the value, with the discarded sign stated in a comment.
* `consumer/src/main.zig` grew the expansion `[1.0]` by `2^-52` and asserted that
  the residual it recovered was `2^-53`. That expectation was wrong in its own
  favour: `1 + 2^-52` is itself a double, so `Two_Sum` is exact, the error term
  is zero, and `grow_expansion_zeroelim` returns the single component
  `1 + 2^-52` — a residual of `2^-52`, not `2^-53`. The fixture now grows by
  `2^-53`, which binary64 genuinely rounds away, and requires the two-component
  expansion `[2^-53, 1.0]` back while also asserting that plain arithmetic
  returned exactly `1.0`. That is an independent known answer derived from
  round-to-nearest-even, not a restatement of what the library returned.
* `include/predicates.h` claimed that the CI provenance gate fails if the header
  no longer matches the C source. That gate compared declaration names and has
  been removed; the header's real coverage is the native job, which compiles and
  links a C translation unit against the installed header and archive. The
  comment now says that.
* The prose said `orient2d` "returns `inf - inf`, which is NaN" for coordinates
  near `floatMax`. Reading the branch at `src/predicates.c:1631-1652` shows
  otherwise: when only one product overflows, the other is `<= 0.0` and the
  routine returns a saturated infinity whose sign is still correct. Only when
  both products overflow with the same sign does `det` become NaN and get passed
  to `orient2dadapt`. `src/root.zig`, `README.md`, `README.zig.md` and
  `FORK-NOTES.md` section 19 now state the branch as read, and say that what the
  adaptive engine does with that NaN has not been probed.
* The fixture behind "the documented sign conventions hold" only compared the
  routine against itself, which a predicate answering zero every time would also
  satisfy. It now asserts the independently worked-out sign first: for
  `a = (0.3, 0.7)`, `b = (5.5, -2.25)`, `c = (-1.5, 4.75)` the determinant
  relative to `c` is `1.8*(-7) - (-4.05)*7 = 15.75`, so the sign is positive.
  All of these are `PENDING-VERIFICATION`.
* `FORK-NOTES.md` section 4 asserted, as an explicitly unverified hypothesis,
  that `random()` exists in glibc, musl, wasi-libc *and* mingw-w32's headers,
  "which is every C library in the six-target matrix". `zig build check`
  refuted it: the toolchain's Windows `stdlib.h` declares `rand_s` and no
  `random`, so the six-target claim behind the matrix was wrong. The
  hypothesis is replaced with the observation, and the matrix it supported no
  longer claims six buildable targets.

### Removed

* `.github/workflows/verify.yml` no longer compares the declaration names in
  `include/predicates.h` with the definition names in `src/predicates.c`. A
  name-set comparison is a source-text test: a reindent or a retyped
  declaration defeats it, and it never showed that a consumer can call the
  header. In its place the native job compiles a C translation unit that
  includes the installed header, calls every routine and reads every global it
  declares, links it against `zig-out/lib/libpredicates.a`, and runs it. The
  source digest and licence-notice checks are unchanged.

## [0.1.0] - 2026-09-30

First release of this fork. There is no earlier release to chain from: a
previously completed fork was recorded in the project inventory, but no copy of
it was readable on this host and `CoffeeImpliesCode/foundation-predicates`
returned HTTP 404 when it was looked up during the import, so nothing could be
carried forward. `UPSTREAM.md` records that in full and states plainly that this
is a fresh import from canonical source, not a continuation.

### Added

* Import of the canonical `predicates.c`, dated May 18, 1996, fetched from
  <https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c> and
  unmodified since, SHA256
  `f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029` (171536
  bytes, 4262 lines, ASCII). CI recomputes that digest from the file in this
  repository on every run; it is a statement about this tree, not about what
  the remote serves later.
* `build.zig` and `build.zig.zon` for Zig 0.16, exposing the `predicates`
  module and the `predicates` static-library artifact.
* Compilation flags `-std=gnu17`, `-ffp-contract=off` and `-fno-fast-math`, which
  are correctness requirements for this source rather than preferences.
* `include/predicates.h`, an aggregate declaration header transcribed from the
  prototypes in the C source, translated by `addTranslateC` into the module
  reachable as `predicates.c`.
* `src/root.zig`, a facade providing allocation-free `orient2d`, `orient3d`,
  `incircle` and `insphere` over `Point2` and `Point3`, with `*Sign` wrappers,
  the non-robust `*Fast` variants, and the raw `c` escape hatch.
* `init()`: an initialization lifecycle that runs `exactinit()` exactly once per
  process under an atomic once-guard, with a debug-mode assertion on every
  predicate so a missed initialization is reported at the call site.
* An input contract the C does not have: every facade predicate returns
  `error.NonFiniteCoordinate` for a NaN or infinite coordinate.
* `test/exact_oracle.zig`, an exact integer/rational sign oracle that evaluates
  each determinant in arbitrary-precision integers after clearing denominators
  with a common power of two, used as the independent witness in the tests.
* Behavioural tests covering all four predicates against that oracle, including
  exact-degenerate configurations, configurations whose exact determinant is
  zero by construction, ulp-scale perturbations of near-degenerate input,
  coordinate spreads of 200 to 800 octaves chosen so every filtered product
  stays inside the double range, one subnormal collinear case whose exact
  determinant is zero, the non-finite input contract, and concurrent
  initialization. The ends of the double range are deliberately excluded from
  the wide-range fixtures; see the "Extreme inputs" entry in `FORK-NOTES.md`.
* Tests for the expansion arithmetic reached through `predicates.c`.
* `examples/smoke.zig`, a deterministic runnable example; `zig build smoke`.
* `consumer/`, a separate package that consumes this one through
  `dep.module("predicates")` and checks hand-computed answers;
  `zig build run` inside it.
* `zig build check`, which compiles the full C source, the facade, the tests and
  the example for x86_64-linux-gnu, aarch64-linux-gnu, aarch64-macos-none,
  x86_64-windows-gnu, riscv64-linux-gnu and wasm32-wasi without running them.
* `.github/workflows/verify.yml`, running the native build, tests and smoke, the
  six-target check, and a source licence and provenance gate.
* `UPSTREAM.md`, `NOTICE.md` and `FORK-NOTES.md`.

### Changed

Nothing upstream was changed. `src/predicates.c` is unmodified and its checksum
is verified in CI.

### Fixed

* `build.zig.zon` carried a package fingerprint that Zig 0.16.0 rejects, which
  stopped `zig build` in the manifest before any C was compiled. It is now the
  value the compiler reported for this package. No released copy ever carried
  the rejected value, so this belongs to the first release rather than to a
  shipped one. `FORK-NOTES.md` section 20 has the receipt.

### Gate status at the time of writing

Not a changelog item so much as a statement of what the entries above rest on.
Observed on this host, with the pinned Zig 0.16.0: `zig fmt` over the build
files, `src`, `test`, `examples` and `consumer` produced no output; `zig build`
compiled the C archive and the translated header, then stopped while compiling
`examples/smoke.zig` because `std.math.ldexp` was handed a `comptime_float`.
`zig build test`, `zig build smoke`, `zig build check` and `consumer/ zig build
run` have not been observed for this repository, and no test result is claimed
here. The corrections in `[Unreleased]` are `PENDING-VERIFICATION`.

### Not included

* A system-library build option. `predicates.c` has no canonical installed form,
  and pointing a build option at an installed library would mean guessing at an
  ABI and a header version that do not exist. `FORK-NOTES.md` records the
  reasoning.
* A range check on the predicates. Upstream's filtered first step underflows on
  subnormal coordinates and overflows near `floatMax`, so the exact sign is not
  guaranteed at the ends of the double range. That limitation is documented in
  `src/root.zig`, `README.zig.md` and `FORK-NOTES.md` rather than turned into a
  second error condition, because upstream states no threshold and a guessed one
  would reject inputs the C handles correctly.
* Any upstream CI. The canonical distribution ships none, so there was no
  upstream workflow to retarget; `.github/workflows/verify.yml` is written for
  this fork.