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
* `devenv.nix`'s two delivery tasks, `sdk:build` and `sdk:build-shared`, now
  pass `--prefix` to a subdirectory of the local cache the caller exported —
  `$ZIG_LOCAL_CACHE_DIR/predicates/static` and `$ZIG_LOCAL_CACHE_DIR/predicates/shared`.
  A default `zig build` installs: `build.zig:679` (the artifact), `:689-691` (the
  generated pkg-config file), `:703-705` (the three licence records) and `:722`
  (the smoke program's compilation) are all behind the install step, so a task
  that ran it with no prefix wrote a delivery tree into this checkout.
  `build.zig` still owns the entire installed layout; `--prefix` only says
  where that layout lands. Direct invocation of a generated task program can
  pass `--prefix P`, `-p P` or `--prefix=P` unchanged; devenv 2.4 `tasks run`
  cannot forward arguments. All eight Zig build routes now supply fixed `-j8`,
  explicit `--cache-dir "$ZIG_LOCAL_CACHE_DIR"` and `--summary all` before
  retained `"$@"` forwarding. The test, smoke, check and consumer
  steps still install nothing and carry no unnecessary prefix.
* Each Zig build task runs the same cache helper as `enterShell`, preserving
  exported `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LOCAL_CACHE_DIR` values and filling
  missing values from `$XDG_CACHE_HOME`, then `$TMPDIR`. Without an approved
  root it exits non-zero rather than allowing Zig's default caches.
  Every task, including provenance, locates this SDK independently of the
  caller's working directory. Source preparation only: `PENDING-VERIFICATION`.

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
* `test/raw_surface_test.zig`'s "the adaptive filter takes its branch from the
  error bound it is given" asserted that `orient2dadapt` with `detsum = 0.0`
  returns exactly `0.0` for the one-ulp cancellation, and that it agrees bit
  for bit with `orient2dfast`. Neither is the routine's contract. Read out of
  the pinned source, `src/predicates.c:1577-1579` returns `det` unchanged when
  `(det >= errbound) || (-det >= errbound)`, with no clamping step anywhere in
  `orient2dadapt`, and `det` is `estimate(4, B)` (`:1575`) over the expansion
  that `Two_Product` (`:213`) and `Two_Two_Diff` (`:265`) built. On that fixture
  both products round to `1.0` in binary64, which discards the `-2^-104` tail
  the filter exists to keep, so the filtered value is the exact determinant
  `-2^-104` and the non-robust `orient2dfast` (`:1443`) is the one that returns
  zero. The test now asserts that, with the source lines cited.
* The same test claimed to be the one that fails if `ccwerrboundB` were still
  zero, and it was not: on that fixture every branch returns the same negative
  number, so zeroing the global changed nothing observable. It now also runs a
  catastrophic-cancellation fixture, `pa = (0,0)`, `pb = (0,1)`,
  `pc = (2^54, 2^54)`, where the filtered expansion cancels to exactly `0.0` and
  the discarded determinant is `-2^54`. The two branches return different
  numbers there, and with `ccwerrboundB` zeroed the routine takes branch 1 for
  every input and returns that zero, so the sign assertions fail. The fixture
  in "the typed accessors and the raw route read the same provider storage",
  which was described as the one whose answer depends on `ccwerrboundB` being
  non-zero, was replaced with the same fixture for the same reason.
* The file header claimed the filter tests were sensitive to `resulterrbound`
  and `ccwerrboundC` having been written as well. They are not. The
  refinement at `src/predicates.c:1591` does read both, but on every fixture in
  that test the filtered `det` handed to it is exactly `0.0`, so
  `resulterrbound * |det|` contributes nothing and `ccwerrboundC` only scales a
  term far below the value in play; zeroing either global changed no answer.
  The header now claims only `ccwerrboundB` and records why the other two are
  unobserved, rather than asserting a sensitivity that does not exist.
* Every task body in `devenv.nix` failed as soon as the environment was entered
  from anywhere but this checkout. devenv materialises a task as a generated
  shell program that inherits the working directory it was started in, and that
  directory is the devenv project, which holds `.devenv/` and `devenv.lock` and
  none of `build.zig`, `consumer/` or `tools/`: `sdk:consumer` reported
  `line 3: cd: consumer: No such file or directory` and `sdk:provenance`
  reported `line 3: tools/check-provenance.sh: No such file or directory`.
  Each body now resolves `builtins.toString ./.` — this module's own directory,
  relative to the file that writes it, and quoted once with `lib.escapeShellArg`
  — before it runs anything: the build, test, smoke and check bodies change to
  that directory, the consumer body changes to `consumer/` inside it, and
  `sdk:provenance` hands that path straight to `tools/check-provenance.sh`,
  which resolves the repository from its own `$0`
  (`tools/check-provenance.sh:28`) and so needs no working directory at all.
  `$DEVENV_ROOT` is not used anywhere: it names the project directory, which is
  the thing that was already wrong. Task names, the
  `sdk:check` description that carries the POSIX `random()` boundary and its
  `FORK-NOTES.md` section 21 citation are unchanged. `PENDING-VERIFICATION`.

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
  process under an atomic once-guard. The original debug-mode predicate assertion
  is superseded by the all-mode panic recorded in the numerical review below.
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

## Zig API contract alignment — 2026-10-03

**Condition.** A completed initialization observer must acquire the winner's
release of the native constants. A monotonic completed-state read lacks that
publication edge. Finite coordinates alone do not guarantee an exact sign at
floating-point range extremes.

**Fix.** Acquire completion in both the init fast path and `isInitialized`.
Keep native `exactinit` unchanged. Initially documented the initialization
assert's optimize-mode split; the numerical review below replaces it with an
all-mode panic. Finite-coordinate rejection remains checked in all modes.
Correct determinant versus permanent wording and scope `.zero` to the
well-scaled exactness domain.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
tests in all four modes, smoke, package consumer and module example pass.
Separate four-mode consumers exercise eight concurrent initializers, completed
state and a correct well-scaled sign plus checked non-finite rejection.
The acquire/release edge is source-confirmed; this is not TSAN or weak-memory
hardware proof. Compile-only `check` builds five targets and fails Windows on
native POSIX `random()` and unprototyped C definitions. Native/header/generated
bytes, the numeric algorithm and the supported input domain are unchanged.

## Foundation contract migration — 2026-10-04

**Condition.** The SDK had to become standalone — canonical devenv, its own
Nix packages, no sibling import — while keeping its existing static linkage
policy and its one documented platform boundary. The native source is a single
1996 C file with a public-domain dedication, which is the fact that decides
the licence question for everything the fork writes on top of it.

**Fix.** Added `package.nix` (one source-only derivation), `flake.nix`
(`packages.<system>.static` and `.shared`, `default` still static),
`devenv.nix`, `devenv.yaml` and `.envrc`. Added `FORK-LICENSE.md`, which records
the owner's authorization, the actual grant for the fork-authored files, and
the `LicenseRef-PublicDomain` SPDX identifier used in their headers. Added
`tools/check-provenance.sh`, the digest and licence-notice integrity check, and
made it a devenv task. Restructured `README.md` into the canonical order:
current native-source deviations, current native-build deviations with dated
history, the current build/run/test matrix with pending work named as pending,
then consumption. Rewrote `NOTICE.md` and `UPSTREAM.md` to carry the complete
native metadata: the 40 exported functions and 15 mutable globals with their
line numbers, the four includes and six macros, the 13 `random()` call sites in
6 functions, and the statement that no upstream README exists.

**What the native build graph owns.** `build.zig` is the single owner of the
installed layout: the artifact, `include/predicates.h`, a generated
`lib/pkgconfig/predicates.pc`, and `NOTICE.md`, `FORK-LICENSE.md` and
`UPSTREAM.md` at `$prefix/share/licenses/predicates/`. `package.nix` installs
nothing by hand, so `nix build` and `zig build install` produce one layout by
construction rather than two kept in agreement by hand. `-Dlinkage` is typed
`std.builtin.LinkMode`, so its CLI values are exactly `static` and `dynamic`,
and the default stays `.static`. The `.pc` deliberately carries no floating-point
flags — they apply to `src/predicates.c`, which this build compiles with them —
and an empty `Libs.private`, because the only external call is POSIX
`random()` and nothing from libm is called. No `.version` is set, so there is no
soname series: the shared object is plain `libpredicates.so`, because upstream
has no version from which an ABI major could be derived.

**A second platform boundary, recorded rather than repaired.** The shared
variant fails for `x86_64-windows-gnu` for a second, independent reason: a
PE/COFF image exports a symbol only when that symbol is marked, and none of the
40 functions or 15 globals in the canonical file is. `zig build check
-Dlinkage=dynamic` attempts all six rows and reports what each one does.
Marking those symbols would mean editing the canonical file, so it was not done.

**Recorded, not fixed.** The 15 C globals are mutable state written by
`exactinit()`, not constants. `NOTICE.md` item 12 and `README.zig.md` now state
the rule that a runtime-loaded provider must address them through the provider
it resolved its functions from, and must run `exactinit()` through it as well.
Reaching them through a second copy of the library would read zeros while the
predicates compute against another copy's constants.

**Boundary, unchanged.** `x86_64-windows-gnu` still does not compile. The
canonical source calls POSIX `random()` at 13 sites in six published debug
helpers, which mingw-w64 and the UCRT do not provide, and reports old-style
function definitions as errors. The helpers were not dropped, `random()` was
not shimmed, the source was not edited, and the target was not removed from the
matrix. `flake.nix` exposes no Windows system and `package.nix` declares
`platforms = lib.platforms.unix` for the same reason.

**Numerical review, source-only.** Made the translated `c` module private;
the supported raw route remains `predicates.c`. Forwarded consumer `b.args`
so `--provider` reaches the program. Corrected the Zig scratch/magnitude
contract with C source anchors; the discrepant native header comments are
preserved, not patched. Own CI installing builds now select external prefixes
and installed consumers follow them. Replaced the initialization assert with
an ordinary comparison and panic in every mode after the driver's before probes.

**OBSERVED guard probes, 2026-10-04.** On Zig 0.16.0/x86_64-linux-gnu,
`build -j8 --summary all -Dtarget=x86_64-linux-gnu -Doptimize=<mode>
-Dprobe=<uninitialized|initialized>` with explicit per-case caches/prefix
(full command in each receipt) built with exit `0` in ReleaseFast and
ReleaseSmall. The resulting uninitialized binaries exited `-6` with the required
panic; initialized controls exited `0` with determinant `6` and reversed `-6`.
Receipts: `/home/tmp2/gertullj/scratch/foundation-libs/numerical-contract-probes/receipts/relative-path-repair/after/{predicates-init-guard,predicates-init-control}/{ReleaseFast,ReleaseSmall}/receipt.json`.
This does not establish the permanent four-mode suite; see `FORK-NOTES.md`
for the exact command family.

**Verification and bound.** Other migration gates remain pending.
`PENDING-VERIFICATION` for: `zig build`, `zig build -Dlinkage=dynamic`,
`zig build test` in Debug and ReleaseSafe, `zig build smoke`, `zig build check`,
`zig build check -Dlinkage=dynamic`, the installed C consumer against the
archive and against the shared object, the materialised package consumer, the
static and shared Nix derivations with their output and dependency records, the
canonical devenv shell, and `tools/check-provenance.sh`. The driver owns every
one of those fields.
`src/predicates.c`, `include/predicates.h`, the numeric algorithm, the compile
flags and the supported input domain are unchanged; the digest recorded in
`UPSTREAM.md` still hashes to the file in this tree.

## Packaging corrections — 2026-10-04

**Fixed.** `package.nix` now sets `dontBuild` alongside `dontConfigure` for its
single explicit install-only phase (`dontInstall` deliberately not set, since it
would disable that phase); exports `ZIG_LOCAL_CACHE_DIR` and
`ZIG_GLOBAL_CACHE_DIR` under Nix's `TMPDIR`, outside the unpacked tree; passes
`-j NIX_BUILD_CORES`, one `-Doptimize`, `-Dcpu=baseline`, `-Dlinkage` and
`--prefix $out` to one `zig build install`; and filters `.devenv.flake.nix`,
`zig-cache`, `zig-pkg` and `result-*` from the source in addition to what it
already excluded. It asserts `stdenv.hostPlatform.system ==
stdenv.buildPlatform.system` and throws otherwise, because no `-Dtarget` is
passed and a Nix cross package would build for the wrong host;
`builtins.currentSystem` is impure and unusable in evaluation.

`devenv.nix` replaces the bare task keys (`build`, `test`, `test.release-safe`)
and the echo-only packaging tasks with `sdk:`-namespaced tasks that run real
commands, plus lazy `outputs.static`, `outputs.shared` and `outputs.default`
calling the same `package.nix`. Entering the shell still builds nothing.
`flake.nix` drops an unrequested overlay and keeps `static`, `shared` and a
static `default`; its devShell stays tools-only.

**Prose.** `FORK-LICENSE.md` and `NOTICE.md` no longer argue that a public-domain
grant is the only legally available licence for fork-authored work, or that a
fork grant is bounded by what it can change about the original file. Both now
state only the owner's authorization, the grant actually made, the
`LicenseRef-PublicDomain` identifier, the native text and the file paths.
Process narration and repeated grant essays were removed throughout.

**Verification and bound.** Still `PENDING-VERIFICATION`; unchanged from the
section above. No build, test, lint, formatter, git, nix or devenv command was
run for these corrections. Native source, header, algorithm, flags, tests and
the documented platform boundary are untouched.

## Upstream byte baseline — 2026-10-04

**Condition.** The contract asks for a machine-checkable record of every upstream
byte an SDK carries, not of the one file a reader happens to remember. For this
SDK the upstream scope is one file, so the record is one line long, and a
one-line record cannot say whether the tree still carries anything else.

**Fix.** Added `UPSTREAM-BASELINE.sha256`: the SHA-256 of `src/predicates.c`, the
pin it was derived from, the fetch it was derived by, the counts of every
category of upstream material this SDK does *not* have, the path that must not
exist, and the 39 fork-owned paths carried alongside. Extended
`tools/check-provenance.sh` to verify the manifest, the counts, coverage in both
directions and the agreement with `UPSTREAM.md`; the `provenance` CI job now
calls that script instead of carrying a second copy of its two greps. Added the
record to `build.zig.zon`'s `.paths`, and gave `UPSTREAM.md` a section for it.

**Two compile errors fixed.** `test/raw_surface_test.zig` put a second `comptime`
on an already-comptime parameter, and handed a runtime string to a `comptime`
parameter from a runtime `for`. The first is a plain `name ++ "Addr"`; the second
is an `inline for`, which specializes the five-row table instead of weakening
the assertion — all fifteen constants are still read live through the raw route.

**Verification and bound.** `tools/check-provenance.sh` passes on this tree: one
carried upstream path, 39 fork-owned paths accounted for. Every value in the
record was re-derived from a fresh fetch of the canonical URL on 2026-10-04 and
not from this tree: SHA-256 `f8662c3f…`, MD5 `4f199d02…`, 171536 bytes, 4262
lines, and `cmp` reports the fetched file byte-identical to the carried one. Nine
mutations were applied to a scratch copy of this tree and every one of them
failed the gate, while an untouched copy passed: a changed canonical file, an
unrecorded file under `src/`, a manufactured `README.upstream.md`, a tampered
count, a dropped fork declaration, a stale fork declaration, a drifted pin, a
rewritten manifest digest, and a removed public-domain grant. No build, test,
lint, formatter, nix or devenv command was run, and `src/predicates.c` is
untouched.

## The current matrix is observed, and its red cells are one refusal — 2026-10-05

**Scope.** Documentation only. No build file, no source file, no upstream byte
and no licence record changed, and no gate was run for this entry; the numbers are
read out of four existing driver receipts.

**Observed.**

- Native eight cells, `zig build test smoke install -Doptimize=<mode>
  -Dlinkage=<l> -Druntime=false`, static × dynamic crossed with Debug,
  ReleaseSafe, ReleaseFast and ReleaseSmall: exit 0 in all eight and status
  `skipped-tests` in all eight — `Build Summary: 16/16 steps succeeded; 46/47 tests
  passed (1 skipped)`. The skipped test is the declared guard at
  `test/raw_surface_test.zig:563`, `if (comptime !predicates.runtime_loaded) return
  error.SkipZigTest;`, which fires on a linked native cell and does not under the
  runtime route. Exit 0 with a skip is not a green cell and is not written as one.
- Own-loaded eight cells, the same eight configurations with `-Druntime=true` and
  `PREDICATES_TEST_PROVIDER` naming this tree's own `libpredicates.so`
  (`provider.kind: "own"`): exit 0 in all eight,
  `Build Summary: 17/17 steps succeeded; 47/47 tests passed` in every cell.
- The 53-cell cohort, receipt `20261004T221720228710Z-45046/predicates-53-target-8.json`,
  `source_stamp_before == source_stamp_after` (`66b6f5df…`), `target_jobs 8`,
  `jobs_per_build 8`: **exit 1**, `pass=20 fail=4 build_only=29 partial=0`, every
  executed cell reporting `tests=46`. The four failures are `aarch64-windows`,
  `thumb-windows`, `x86-windows` and `x86_64-windows`.
- The compile-only `zig build check` baseline, row `baseline-predicates-check`:
  exit 0, `Build Summary: 26/26 steps succeeded`, `declared_target_count 6`,
  `failing_step_lines 0`, `test_pass_lines: []`, and `steps_by_target` naming five
  triples with `x86_64-windows-gnu` at zero.

**The four red cells are this package's own refusal, not a compiler failure.**
Each ends at `refuseTarget` (`build.zig:601` → `:227`) and prints
`error: predicates: <target>: no buildable configuration for this target: the
canonical source calls POSIX random(), which Windows does not provide.` The
53-cell driver passes an explicit `-Dtarget` per cell and therefore reaches that
gate; `zig build check` walks `supported_check_targets`, so it refuses the same
row by name and exits 0, which is what the baseline receipt shows from outside.
`README.md`'s cross-target table previously described the Windows row as
attempted-and-failing and said `check` "exits non-zero on the sixth"; that is
corrected there to the refused shape the graph and the receipts show.

**Bound.** The cohort's counts describe the source it stamped and nothing later.
Twenty-nine `build_only` cells compiled and ran nothing and are not passes. The
`check` baseline is compile-only by construction and by the receipt's
`runtime_pass_claimed: false`. The installed C consumer, the materialised package
consumer, both Nix derivations, the devenv shell, `tools/check-provenance.sh` and
the `-Dlinkage=dynamic` / `-Druntime=true` `check` rows remain
`PENDING-VERIFICATION`.
