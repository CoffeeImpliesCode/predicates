# Fork notes

Problems actually met while importing and packaging this library, and what was
done about each. Ordered roughly by how much damage they would have done if
missed.

Source facts are things read out of `src/predicates.c`, Zig 0.16's `lib/std`, or
observed on this host. Anything that has not been run here is marked as a
hypothesis, because a design that has only been reasoned about is not a verified
result.

---

## 1. Upstream has no header, so nothing can be translated

**Fact.** `predicates.c` contains no `#include` of a local header. Its first
four includes are `<stdio.h>`, `<stdlib.h>`, `<math.h>` and `<sys/time.h>`. Every
prototype lives in a comment block between lines 32 and 114. A consumer cannot
call these functions, and `addTranslateC` cannot translate them, without a
machine-readable header.

**Decision.** Added `include/predicates.h`, transcribed from the comment block
and cross-checked against the K&R definitions. Two choices were available:

* Rewrite the forty K&R definitions as ANSI prototypes. Correct, and it makes
  the header and the source agree by construction.
* Leave the C alone and add a header beside it.

The second was taken. The reason is not conservatism for its own sake: the whole
value of this package is that `src/predicates.c` is byte-identical to upstream,
so a checksum states exactly what was compiled and a sync is a file copy. Paying
for that with a 400-line diff to the upstream file would trade a hard guarantee
for a soft one.

The cost is real and is accepted knowingly: the header is a second place that
can drift from the C, and no checksum covers it because upstream has no header
to hash. An earlier revision of CI compared declaration names between the two
files, and that comparison was removed as a source-text test. What stands in
its place is the native job, which compiles and links a translation unit
against the installed header and the installed archive and calls every routine
the header declares: a retyped declaration fails to compile, and a declaration
the archive does not define fails to link.

## 2. K&R definitions versus the language standard

**Fact.** Every function in the file is defined in old style: `int
fast_expansion_sum(elen, e, flen, f, h)` followed by separate parameter type
declarations. Zig passes no `-std` to clang, so the standard is clang's default.
C23 removed old-style definitions.

**Decision.** `-std=gnu17` on every compile of the C. Pinning the standard
upstream was written for is the conservative move and it is what lets the file
stay unmodified. If a future clang drops the default to C23, this flag keeps the
build working; if upstream is ever refreshed with ANSI definitions, the flag is
harmless.

**Risk, unresolved.** The flag is applied through `addCSourceFile`'s `flags`,
which has no per-architecture variant in Zig 0.16. All six targets are covered by
the same flag list, which is correct here because every target's clang accepts
it, but there is no per-target tuning hook if one ever needs it.

## 3. Contraction silently breaks the predicates

**Fact.** `Two_Product_Presplit` computes `ab = a * b`, splits `ab`, and then
reconstructs the exact residual from `abhi`. `Two_Two_Diff` and `Fast_Two_Sum`
likewise assume each operation rounds separately. Clang contracts a multiply and
an add into an FMA by default. Upstream says so in the header comment and in
paper CMU-CS-96-140.

**Decision.** `-ffp-contract=off` on every compile, with the reasoning written at
the point where the flag is applied rather than left in a changelog.

`-fno-fast-math` is passed even though it is already the default, for the same
reason: the failure mode is a silently wrong sign, and a flag that names the
failure is cheaper than a bisect.

**Not applicable.** Excess precision. All six targets evaluate `double` in
binary64 with no x87 registers, so upstream's `#define INEXACT volatile`
escape hatch stays exactly as written, unused.

## 4. The library needs libc, and one of its published routines wants a non-ISO function

**Fact.** `<stdio.h>` and `<stdlib.h>` are included. More concretely,
`doublerand`, `narrowdoublerand`, `uniformdoublerand`, `floatrand`,
`narrowfloatrand` and `uniformfloatrand` each call `random()` three times per
call. `random()` is POSIX, not ISO C.

**Consequence.** The `predicates` artifact links libc, and so does the Zig
facade module. That is a real dependency of the published surface, not a
convenience: the random helpers are externally visible and upstream does not
document them as debug-only.

**Hypothesis, and it was wrong.** This note first asserted that `random()`
exists in glibc, musl, wasi-libc *and mingw-w32's headers*, "which is every C
library in the six-target matrix". Section 21 records what `zig build check`
actually reported: mingw-w32 does not declare it, that target does not build,
and the matrix is five targets plus one documented boundary. The claim was
written down as unverified because it had not been run, and running it
refuted it. It is replaced here rather than left for the next reader to
rediscover.

## 5. `<sys/time.h>` is included and never used

**Fact.** There is no `gettimeofday`, `struct timeval`, `time` or `clock` call
anywhere in the 4262 lines. The include is vestigial, left over from the timing
harness upstream ships commented out.

**Decision.** Left in place. It is upstream's line, it costs nothing on any of
the six targets, and removing it would be the first edit to the file that the
checksum is supposed to forbid.

## 6. A module registered by name is global to the build

**Fact.** `Build.addModule(name, ...)` writes into `b.modules`, a table keyed by
name across the whole build. There is no per-target module set.

**Consequence for the six-target check.** Creating the facade module six times
through `addModule("predicates", ...)` would leave one entry in the table, and
the last target written would silently become the only one a dependent could
reach. A `check` step that looked like it covered six targets would in practice
cover one, and it would still be green.

**Decision.** `addGraph` in `build.zig` takes a `public` flag. The native graph
registers `predicates` in the package module set, which is what
`dep.module("predicates")` reads; every cross-target graph uses
`createModule`, which is private. A public module would be a lie in a
multi-target graph.

## 7. Compiling an archive would have analysed none of the facade

**Fact.** Zig analyses a function body when something calls it. A `pub fn` in a
library root that nothing references is never compiled. So
`zig build check` compiling only `libpredicates.a`, or even a static library
built from `src/root.zig`, would prove that the C compiles and that nothing else
does. The facade, which is the part most likely to break, would go unchecked.

**Decision.** The cross-target check builds the *test binary* for each target,
not just an archive. Every public facade function is called from a test, so
building the test binary for a target analyses all of them for that target. The
example is built too, and the full C source is compiled by the same graph. This
is also why `refAllDeclsRecursive` was not used: it enumerates declarations, it
does not instantiate bodies, and an enumeration is not the property being
claimed.

**Cost.** Every cross target is linked, not just compiled. That needs Zig's
bundled libc and linker for each target. It is the honest reading of "compile
without running", but it is also the part most likely to need a target-specific
exception if one of the six turns out to lack something.

One of them did. `x86_64-windows-gnu` turned out to lack POSIX `random()`, and
that is section 21.

## 8. The `exactinit` contract is a promise, and promises need enforcement

**Fact.** `exactinit()` writes `splitter`, `epsilon` and thirteen error bounds
(`resulterrbound`, `ccwerrboundA/B/C`, `o3derrboundA/B/C`, `iccerrboundA/B/C`
and `isperrboundA/B/C`, declared together at `src/predicates.c:364` and written
at `src/predicates.c:670-682`): ordinary mutable file-scope doubles with
external linkage. Until it runs, they are all zero, and every robust predicate
returns a wrong answer. Upstream's instruction is "call exactinit() once, before
calling any of the arithmetic functions or geometric predicates".

**Problem.** That instruction has three failure modes. Not calling it. Calling it
twice, which happens by accident whenever two subsystems both think they own
initialization. And calling it from two threads, which is a data race on
non-atomic objects *even though both threads write identical values*; a
concurrent write is undefined behaviour regardless of what it writes.

**Decision.** `src/root.zig` keeps an atomic state word and `init()` runs
`exactinit()` under a compare-and-swap, with losers spinning on an acquire load
against the winner's release store. Exactly one thread ever executes it. Every
facade predicate and constant accessor calls `requireInit()`, whose ordinary
comparison panics on a missed initialization in every optimize mode before
reaching the C. `exactinit` itself stays reachable through `predicates.c`
for anyone who wants upstream's semantics exactly, including its hazard.

**Not chosen.** `std.Thread.Once` does not exist in Zig 0.16's std, and
`std.Thread.Futex` does not either. The state word is ten lines and has no
dependency on std internals that could move.

## 9. wasm32-wasi has no threads, and the test that needs them is in the same file

**Problem.** The concurrency test spawns eight threads. Linking a test binary
for wasm32-wasi would either fail to compile or fail to link.

**Decision.** The thread spawning lives in its own function, `runConcurrentInits`,
called only from a `test` body that returns `error.SkipZigTest` on wasi before
reaching the call. The call is unreachable code on that target, so the function
is never analysed. Verified by construction from Zig's unreachable-code rule; not
verified by building for wasi on this host.

## 10. `std.testing.expectEqual` has no message argument

**Fact.** In Zig 0.16 it is `expectEqual(expected: anytype, actual: anytype)`.
There is no `expectEqualMsg` and no way to attach context.

**Consequence.** A predicate table of a hundred named cases reports
"expected enum{negative,zero,positive}.negative, found .zero" and nothing else.
In a suite whose entire point is exact-degenerate configurations, that is
close to useless.

**Decision.** Assertions compare a two-field `Report` struct carrying the case
name and the sign. Both fields print, so the failing fixture names itself. It
costs one struct per comparison and no API that might not exist.

## 11. `std.math.pow` is not exact, and these tests are about exactness

**Fact.** `std.math.pow(f64, 2, -53)` goes through `exp(y * ln(x))` for float
types. It is not guaranteed to return the exact power of two.

**Consequence.** Every fixture that needs `2^-52` exactly would have been built
from a value that might be one ulp off, which changes which configuration is
being tested and can turn an exact-degenerate case into a near-degenerate one.
The `2^27 + 1` comparison against `splitter` would fail intermittently.

**Decision.** `std.math.ldexp(@as(f64, 1.0), n)` everywhere, with the first
argument typed. Zig 0.16 takes the type from that argument and reads
`@typeInfo(T).float.bits` inside the body, so a bare `1.0` is a `comptime_float`
with no `.float` union field and the call does not compile; an `f32` fixture has
to say `@as(f32, 1.0)` and get an `f32` back. The function scales by a power of
two and is exact for every exponent a double can hold.

## 12. Three test expectations were wrong about upstream, and reading the code fixed them

**Source facts, all read out of `src/predicates.c` after the drafts were wrong.**

* `grow_expansion_zeroelim(1, [1.0], 2^-52)` returns length 1, not 2.
  `Two_Sum` is exact here because `1 + 2^-52` is itself a double, so the error
  term is zero and zero elimination has nothing to keep. The draft asserted 2
  and would have failed.
* `compress(3, [0.0, 1.0, 1.0], h)` returns length 1, not 2. The routine is
  documented as removing *zero components*, and the two `1.0` components merge
  into `2.0` along the way because `compress` also compresses. The value is
  still right; the length is not what "drops the zero" suggests.
* `doublerand` is documented as producing "a random exponent in [0, 511]", but
  the loop multiplies by `2^1, 2^2, 2^4, ... 2^512` cumulatively, so the result
  can reach `2^53 * 2^513`. The draft bounded it at `2^512`. The bound in the
  test now comes from the loop, not from the comment, and the sign is taken from
  `a - 1073741824` and can be negative, which the draft also got wrong.

**Note.** This is the argument for reading the source before writing the
fixture, and it is why the expansion tests assert values and exact lengths only
where both were derived rather than assumed.

## 13. The oracle had to be derived, not guessed

**Problem.** The tests need an independent witness. The obvious thing to compare
against is upstream's own `*exact` routines, and that would be worthless: they
share every assumption with the code under test, including any mistake in the
error analysis.

**Decision.** `test/exact_oracle.zig` evaluates each determinant in exact
integer arithmetic. Every coordinate is decomposed into an integer mantissa and
a power of two, all coordinates are scaled by a common power of two so they
become integers, and the determinant is evaluated in arbitrary-precision
integers. The oracle shares no code, no error bound and no filtering with the C.

**The algebra.** orient2d and orient3d use the textbook forms, verified by hand
against the C's own filtered expressions. incircle was checked by putting `d` at
the origin and collecting: `det = alift*bcdet + blift*cadet + clift*abdet`.
insphere was the awkward one, because upstream's `insphereexact` works in
absolute coordinates with squared-norm lifts and a recursively nested expansion
tree. Writing `e` as the origin makes `cde`, `dea`, `eab`, `bce`, `deb` and
`eac` all zero, and what remains collapses onto the standard relative form

```
det = lift_d * det3(A,B,C) - lift_c * det3(D,A,B)
    + lift_b * det3(C,D,A) - lift_a * det3(B,C,D)
```

term for term, using `D(u,v,w) = u.z*cross(v,w) - v.z*cross(u,w) + w.z*cross(u,v)`.
The oracle evaluates that form. The derivation is written down here so it can be
re-checked against the C by reading, without running anything.

**Cost.** It is exact but slow, O(n²) in bignum limbs, and it allocates. It
belongs in tests and never in a hot path.

## 14. Tests that pinned `exactinit`'s constants were removed

Removed on review instruction, and correctly. The suite had asserted
`epsilon == 2^-53`, `splitter == 2^27 + 1` and two error bounds. Those are
implementation details of a 1996 file, they break on every upstream refresh
without ever catching a fault, and the real question is not "did the constants
get computed" but "does the library compute the right sign".

The replacement asserts behaviour: after `init()`, a configuration whose exact
determinant is `-2^-104` comes back negative. If `exactinit` had not run,
`splitter` would be zero and the adaptive engine would have no way to produce
that. The provenance CI job checks the checksum instead, which is the right place
for "is this the right version".

## 15. No system-library mode, on purpose

**Constraint received.** A system-library mode must translate the headers of the
library it actually links, not the in-tree headers of a newer release, and must
not assume an installed library exports shim symbols this fork invented.

**Decision.** No `-Dsystem-*` option exists. `predicates.c` has no canonical
installed form: it is a single file meant to be compiled into its consumer, no
distribution ships a `libpredicates` with a versioned ABI, and there is no
header of ours that such a library could be expected to export. An option
pointing at a system library would therefore have to invent both the library
name and the header/ABI pairing, which is exactly the fabrication the constraint
forbids. The dependency is recorded in `CHANGELOG.md` under "Not included"
rather than left as a silent gap.

## 16. Zig 0.16 moved I/O behind an `Io` instance

**Fact.** `std.debug.print` still exists and still goes to stderr. Writing to
stdout means constructing an `Io`: `std.Io.Threaded.init(gpa, .{})`,
`threaded.io()`, then `std.Io.File.stdout().writerStreaming(io, &buffer)` and
`&writer.interface`.

**Why it matters here.** An example whose output is the evidence it produces
should not have its evidence land on stderr where a build system's error stream
already lives. The example and the consumer both write to stdout explicitly.

## 17. The previously completed fork was not there

**Fact.** The project inventory records a completed predicates fork at
`/home/janis/projects/foundation-predicates`. That path does not exist on this
host; nor does any copy under the account's home, `Downloads`, or project roots.
`CoffeeImpliesCode/foundation-predicates` returns HTTP 404, and an account-wide
repository scan finds no predicates repository under any name.

**Consequence.** This is a fresh import from canonical upstream, not a
continuation. There was no prior history to preserve, no prior test suite to
inherit, and no prior divergence list to carry forward. `UPSTREAM.md` says so
directly rather than implying a lineage that does not exist.

## 18. Packaging details worth not rediscovering

* There is no upstream Zig package, so the manifest fingerprint is generated
  for this package rather than inherited; there is no upstream identity to be
  hostile about. Section 20 records that the first generated value was one the
  compiler rejects, and which value replaced it.
* `.zig-cache/` and `zig-out/` are ignored in the repository root and in
  `consumer/`, and neither appears in `.paths`. A normal `zig build` therefore
  cannot dirty the tree or leak build output into a package published from it.
* `src/predicates.c` is deliberately not under `include/`. Keeping the C tree
  exactly as upstream and the fork's own header beside it is what makes "the C
  is unmodified" checkable by checksum rather than by argument.
* The `predicates` module name and the `predicates` artifact name are the same
  string in different namespaces, which is intentional: `dep.module("predicates")`
  for a Zig consumer and `dep.artifact("predicates")` for a C one, with no
  ambiguity about which is which.

## 19. Extreme inputs are not covered by upstream's guarantee

This is the most consequential thing found in the whole packaging job, and it
was found last, by tracing arithmetic rather than by reading documentation.
It belongs near the top of this list.

**Fact, read out of `src/predicates.c`.** `orient2d` begins by computing

```c
  detleft = (pa[0] - pc[0]) * (pb[1] - pc[1]);
  detright = (pa[1] - pc[1]) * (pb[0] - pc[0]);
  det = detleft - detright;
```

in ordinary doubles, and only falls through to exact arithmetic when the
filtered `det` is too small relative to `detleft + detright`. The same shape
appears in all four predicates.

**Failure 1: underflow.** For `pa = (2^-1074, 0)`, `pb = (0, 2^-1074)`,
`pc = (0, 0)`, `detleft` is `2^-2148`. The smallest binary64 subnormal is
`2^-1074`, so that product rounds to exactly zero. `detleft` is then neither
greater nor less than zero, and the routine takes the branch that returns
`det`. The answer is `0` for a configuration whose exact determinant is
`2^-2148 > 0`. `incircle` and `insphere` fail the same way through their lift
terms, which are sums of squares of differences.

**Failure 2: overflow.** With coordinates near `floatMax` the same product
overflows to infinity. When only one product overflows, the other is `<= 0.0`,
which is an early `return det` of a saturated infinity whose sign is still the
correct one. When both overflow with the same sign, `detsum` is infinite,
`errbound = ccwerrboundA * detsum` is infinite, and `det` is `inf - inf`, which
is NaN. NaN compares false in both directions, so the filter cannot resolve it
and `orient2dadapt` is entered with that NaN and an infinite `detsum`. What the
adaptive engine does from there is not settled by reading the branch and has not
been probed, so nothing is claimed past that call.

**Not a fork bug, and not repaired.** The adaptive machinery is exact; the
*filter* that decides whether to use it is plain floating point, and it dies
before the exact arithmetic is ever reached. Upstream states conditions for
the arithmetic being meaningful, not a guarantee over the whole double range,
and no scale threshold is stated anywhere in the file.

**What was done.** The wide-range tests were rewritten to stay inside a range
where the products are normal, and the limitation is documented in
`src/root.zig`, `README.zig.md` and here. It is deliberately *not* turned into
a second error condition:

* A range check would have to invent a threshold upstream does not state, and a
  threshold that is too aggressive rejects inputs the C handles correctly. A
  rejected input is a bug the caller has to diagnose; a wrong sign is a bug
  nobody diagnoses.
* The task this fork was given is to package the upstream algorithms and be
  honest about their conditions. Adding a range guard is a new behaviour, not
  a packaging decision, and it would put a fork-authored heuristic in front of
  Shewchuk's arithmetic.

**Deliberately not tested.** There is no test asserting that a subnormal input
returns the wrong answer. Pinning a defect as expected behaviour makes it
permanent and makes a future upstream fix look like a regression. The
limitation is prose, not a fixture.

## 20. The manifest fingerprint was rejected, and what the build did next

**Observed on this host, first run.** `zig build` exited with code 1 in 0.169 s,
printing only this:

    build.zig.zon:1:2: error: invalid fingerprint: 0x6fe542960e0a757f; if this is a new or forked package, use this value: 0xdce97c15e1aa9aa4

The diagnostic points at the manifest, not at `build.zig`, so the build system
never entered a step: `predicates.c` was not compiled and the translated header
was not produced.

**Correction.** `.fingerprint` in `build.zig.zon` is now `0xdce97c15e1aa9aa4`,
the value the compiler printed for this package. It is a number the tool
reported, not one derived or guessed here. The derivation itself is not in the
shipped `lib/std` — searching it for the fingerprint computation finds only
`HashMap`'s unrelated seven-bit slot fingerprint — so these notes state the
value and stop there. No second value was invented for any other package or
manifest; `consumer/build.zig.zon` is a different package and was not touched.

**Why the earlier note was wrong.** Section 18 said the fingerprint was newly
generated, which was true of where it came from and false of whether the
compiler accepts it. Generating a value and getting one the compiler will
accept are different acts, and only the second one makes the package usable.
Section 18 now points here.

**Observed on this host, second run.** With the manifest accepted the build
entered the graph and reached `examples/smoke.zig`, which means the C archive
was compiled and the aggregate header was translated. It stopped there, first
because `std.math.ldexp` was handed a `comptime_float`, and then, after that one
call was typed, at line 136, where an error value was being formatted with
`@tagName`, a builtin for a type rather than for a value.

**Not observed at that point.** `zig build test`, `zig build smoke`,
`zig build check` and the `consumer/` package had not run when this was written,
so no test result existed for this repository. Every correction in `test/`,
`consumer/` and the prose was found by reading the tree after those two runs.
What was observed later is recorded in the results table in `README.md` and, for
the cross check, in section 21.

## 21. x86_64-windows-gnu cannot compile the canonical source

**Observed on this host, `zig build check`, pinned Zig 0.16.0.** Five of the six
requested targets compile the C source, the facade, the test binary and the
example, and link them: x86_64-linux-gnu, aarch64-linux-gnu,
aarch64-macos-none, riscv64-linux-gnu and wasm32-wasi. The sixth,
x86_64-windows-gnu, fails with 39 diagnostics from the compile of
`src/predicates.c` and nothing else: six are one undeclared call and 33 are one
old-style definition each. `addTranslateC` of `include/predicates.h` succeeds
for that target, which locates the failure in the C source and not in this
package's header.

**The undeclared call, six times.** `random()` is called at
`src/predicates.c:503`, `504`, `505` (in `doublerand`), `529`, `530`, `531`
(in `narrowdoublerand`), `552`, `553` (in `uniformdoublerand`), `572`, `573` (in
`floatrand`), `597`, `598` (in `narrowfloatrand`) and `619` (in
`uniformfloatrand`). Each of those six functions is reported once, as
`call to undeclared function 'random'; ISO C99 and later do not support
implicit function declarations`.

The headers in the pinned toolchain settle what that means. In
`lib/libc/include/generic-glibc/stdlib.h:525` there is
`extern long int random (void) __THROW;`. In the Windows tree, the only
`stdlib.h` under `lib/libc/include` is `any-windows-any/stdlib.h`, and it
declares `rand_s` at line 365 and no `random`. POSIX `random()` is not in
mingw-w64 and not in the UCRT; it is simply absent. That is the whole of the
first blocker.

**The old-style definitions, 33 times.** The same compile reports every
remaining old-style definition as
`a function definition without a prototype is deprecated in all versions of C
and is not supported in C23`, from `src/predicates.c:698` (`grow_expansion`)
through `src/predicates.c:4157` (`insphere`). The file has forty old-style
definitions; six are the `random` helpers above and the fortieth is
`exactinit` at line 643, which reports nothing.

**Inference, not observation.** Forty minus six minus one is thirty-three, which
is consistent with clang reporting at most one diagnostic per function body:
each of the six helpers already reported the undeclared call, and
`void exactinit()` has an empty parameter list, which is a definition of a
function taking no arguments. Neither point was probed here; the count is
arithmetic over the diagnostics that were reported.

**Not established, and not needed.** The five supported targets compile this
same file with this same flag list, `-std=gnu17` included, and report no
non-prototype diagnostic at all. Why the same diagnostic is fatal on one target
and absent on five is not settled by anything read on this host, and the
decision below does not rest on the explanation. It rests on the two
diagnostics themselves, both of which are properties of the 1996 source.

**Options, and why each was refused.**

* **Supply a `random()`.** This is what makes the target compile, and it is
  what this fork will not do. The six helpers are published entry points: they
  are declared in `include/predicates.h`, reachable through `predicates.c`,
  called by the CI header gate and covered by a test. Replacing the generator
  upstream calls with one written here is a shim over a live part of the
  public surface, and a subtly wrong one changes what those routines return
  without changing a single bit of the arithmetic everyone else relies on.
  Note that the predicates themselves never call `random()`; the file does, in
  six debug helpers that share one translation unit with them. Dropping the
  helpers would keep the predicates and would require editing the canonical
  source to do it, which is the same refusal by another route.
* **Declare `random()` and leave the definition to the linker.** A declaration
  with no definition behind it converts a compile error into a link error. The
  `check` step links a test binary and an example, so the failure would move
  rather than go away, and a library that exports six routines which crash on
  call is worse than one that does not build.
* **Suppress the non-prototype diagnostic.** `-Wno-deprecated-non-prototype`
  would silence thirty-three of the thirty-nine and change nothing: with the
  declarations gone, `random()` is still undeclared, so the compile still
  fails. It would buy a smaller error message and a real diagnostic hidden, and
  this fork passes no `-Wno-` flag for the C at all.
* **Rewrite the K&R definitions, or wrap the random helpers in `#ifdef`.**
  Both edit `src/predicates.c`, which is the file whose SHA256 is the argument
  for trusting this fork. Section 1 records that trade already: a hard checksum
  was chosen over a cleaner diff, and it is not given up for one target.

**What was done instead.** The target stays in the matrix and is named, but it
is refused rather than attempted. `zig build check` walks
`supported_check_targets` — the five rows that compile and link — and is green
over all of them. `refused_check_targets` holds `x86_64-windows-gnu`, and asking
for it by name ends at `refuseTarget` with the reason printed, before any graph
is configured and with no compiler invoked. CI is where the refused row is still
run: its cross job passes an explicit `-Dtarget` per cell and marks only that one
`continue-on-error`, because it is the only target for which this fork has
evidence that the source cannot build. The failure stays a recorded fact about
the source rather than a hidden one.

**What this costs a consumer.** A project targeting windows-gnu cannot use this
package, and neither could it compile `predicates.c` itself against a C library
without POSIX `random()`. That is upstream's dependency rather than a policy of
this fork, and it is stated in `README.md`, `UPSTREAM.md` and `NOTICE.md`
rather than discovered at the first link error.

**No result is claimed for this target.** Nothing here ran a Windows binary.
The evidence is the compile diagnostics, the two header files cited above, and
the reading of `src/predicates.c`; every statement about behaviour on Windows
is a statement about what would fail to build.

## 22. The native surface is 40 functions and 15 globals, and the header matches

**Established by enumeration during this documentation pass.** The
comment-stripped source of `src/predicates.c` defines 40 externally visible
functions and declares 15 file-scope `REAL` globals at
`src/predicates.c:361`-`368`, which `exactinit` alone writes, at
`src/predicates.c:651`-`656` and `670`-`682`.

Stripping block comments matters. A plain scan finds 43 function definitions,
because `doubleprint`, `floatprint` and `expansion_print` sit inside `/* ... */`
blocks at `src/predicates.c:379`, `426` and `472`: upstream ships those three
debug printers commented out, they are not compiled, and the file links without
them. The macro `REALPRINT` at `src/predicates.c:134` still names
`doubleprint`, which is why a naive read of the macros suggests a symbol that
does not exist in the archive.

`include/predicates.h` declares exactly those 40 functions and exactly those 15
globals, checked in both directions: nothing defined and undeclared, nothing
declared and undefined. That is a completeness statement about the aggregate
header, and it is deliberately **not** a gate. Section 21 already rejected the
name-set comparison as a test, because a name-set comparison cannot tell a
reindented declaration from a retyped one. The enumeration here is a
cross-check on the record, not a replacement for compiling and linking against
the header.

**Why it is worth writing down.** Section 21 arrived at "forty old-style
definitions" by subtracting diagnostics: 40 minus the six that reported the
undeclared `random()`, minus `exactinit`, which reports nothing. This pass
counted the definitions in the source instead. Two different routes, the same
number, and neither derived from the other.

## 23. Fifteen mutable globals make the loader contract a correctness contract

**Fact.** `splitter`, `epsilon` and the thirteen error bounds are not constants.
`exactinit()` writes them; every robust predicate reads them; all of them are
zero until it runs. All fifteen are exported, so a runtime-loaded provider sees
them as data symbols.

**Why this is not a loader detail.** If the functions are resolved from a loaded
provider and the globals are addressed against anything else — a linked copy,
or another handle — then the predicates run against a set of constants that
`exactinit` may never have written. Before it runs, those constants are zero,
which is precisely the failure `init()` exists to prevent, and the sign
guarantee goes with them. The two copies also collide on the same symbol names
in one process, so whichever `exactinit` runs first decides for both.

**What follows.** A loaded call must resolve the globals through the same
provider as the functions, and the loaded route must run `exactinit` through
that provider too. `NOTICE.md` item 12 and `README.zig.md` state it, because
this is the kind of property that a later, apparently unrelated change to the
loader would break silently, and nothing in a sign test would look like the
cause.

## 24. Standalone packaging, and what it deliberately does not do

**`package.nix` is the only derivation.** `flake.nix` and `devenv.nix` both
`callPackage` it with an injected `zig` and a `linkage`, so the two entry points
cannot describe different builds and no second convention lives in the
derivation. It compiles this repository and nothing else: no upstream fetch, no
`../` sibling, no host path, no user name, no store path.

Decisions worth not rediscovering:

* **Variants belong to the entry points.** `linkage` is passed straight through
  as `-Dlinkage`, Zig's own `std.builtin.LinkMode` spelling; `default` stays
  static, which is this SDK's native policy.
* **`build.zig` is the single owner of the installed layout** — the artifact,
  `include/predicates.h`, the generated `lib/pkgconfig/predicates.pc` and the
  three licence files at `share/licenses/predicates/`. `package.nix` installs
  nothing by hand, so `nix build` and `zig build install` agree by construction.
* **One real phase.** `dontBuild` and `dontConfigure` are set because the
  derivation has an explicit install-only phase; `dontInstall` is deliberately
  not, since it would disable it. Leaving the hook's build phase enabled would
  compile the graph twice, once with default flags.
* **Caches live under Nix's `TMPDIR`**, both `ZIG_LOCAL_CACHE_DIR` and
  `ZIG_GLOBAL_CACHE_DIR`, outside the unpacked tree, alongside `-j
  NIX_BUILD_CORES`, one `-Doptimize`, `-Dcpu=baseline` and `--prefix $out`.
* **No soname series.** `build.zig` sets no `.version`, so the shared object is
  `libpredicates.so`, not `libpredicates.so.0` plus a symlink. Upstream has no
  version, tag or series; `0.1.0` in `build.zig.zon` is this fork's own and
  describes no ABI.
* **No C flags in Nix.** `-std=gnu17`, `-ffp-contract=off` and `-fno-fast-math`
  are correctness requirements of this source and live in `build.zig`.
* **No eager build.** The dev shell installs tools only; the SDK is reached
  through devenv's lazy `outputs.static` / `outputs.shared`, which call the same
  `package.nix`. Gates are `sdk:`-namespaced tasks running `zig build`.
* **No wholly-static-closure claim.** `static` and `shared` name the artifact
  this build produced; what a consumer links is the consumer's business. libc is
  propagated because the source calls POSIX `random()`, and nothing else.
* **Native build only.** No `-Dtarget` is passed, so a Nix cross package would
  build for the wrong host. `package.nix` compares `stdenv.hostPlatform.system`
  with `stdenv.buildPlatform.system` and throws; `builtins.currentSystem` is
  impure and unusable in evaluation.
* **Two provenance implementations.** `tools/check-provenance.sh` is the
  implementation of record; the `provenance` job in `.github/workflows/verify.yml`
  carries its own copy of the same greps. That file is CI wiring this role does
  not own, and collapsing the job onto the script is a one-line change.

**Not observed.** No `nix` or `devenv` command was run for this section. Whether
either derivation evaluates, builds or installs the layout described here is
unverified and belongs to the driver. `flake.lock` and `devenv.lock` are the
driver's; no hash in `flake.nix` or `devenv.yaml` was invented.

## 25. A PE/COFF DLL from this source would export nothing

**Separate cause, same target.** Section 21 records why
`x86_64-windows-gnu` cannot compile the canonical source: POSIX `random()` and
old-style definitions. That is a compile failure. This is a different one, and
it would still be there if the compile were fixed.

**Fact.** All 40 externally visible definitions and all 15 globals in
`src/predicates.c` have external linkage, and none carries a visibility
attribute, an `__declspec(dllexport)`, or anything else a PE/COFF linker needs
in order to put a name in the DLL export table. On ELF and Mach-O that is
enough — everything with external linkage is exported, with no export list and
no version script — but a PE/COFF image exports a symbol only when that symbol
is marked. A shared build for that target would therefore link, and would hand
back a library that exports nothing a consumer could call.

**Why nothing was done about it.** Marking any of those 55 symbols is an edit to
the canonical file, which section 1 already refused for a smaller reason. The
other available answers are worse: a linker `.def` file or `--export-all-symbols`
would be a second, invisible statement of the surface that disagrees with
`include/predicates.h` the first time one of them changes, and `dllexport` on
the ELF side is a toolchain-specific annotation this project has no business
adding to a 1996 public-domain file.

**What is done instead.** `zig build check -Dlinkage=dynamic` compiles the same
five buildable rows against the shared object and refuses the sixth by name,
instead of narrowing the matrix to the rows that would be convenient.
`flake.nix` exposes no Windows system, so the question does not arise in a Nix
build either. The boundary is stated in `README.md`, `README.zig.md`, `NOTICE.md`
item 9 and the `devenv.nix` `sdk:check-shared` task, because a consumer who finds
it by `dlsym`-ing a DLL finds it the expensive way.

## 26. A devenv task inherits the caller's working directory, not this checkout

**Observed on this host, 2026-10-04, through the pinned devenv.** Entered from a
project directory outside this checkout, `devenv tasks run --mode single` on the
two canonical entries failed with

```
/nix/store/…-sdk-consumer: line 3: cd: consumer: No such file or directory
/nix/store/…-sdk-provenance: line 3: tools/check-provenance.sh: No such file or directory
```

devenv materialises a task as a generated shell program and runs it with the
working directory the environment was entered from. That directory is the
devenv project: it holds `.devenv/` and `devenv.lock` and none of `build.zig`,
`consumer/` or `tools/`. It is not this SDK, and `$DEVENV_ROOT` names that
project rather than the SDK, so a body written against `$DEVENV_ROOT` would
have failed identically.

**Decision.** Every body that needs a file in this SDK resolves
`builtins.toString ./.` before it runs anything: the build, test, smoke and
check bodies change to that directory, the consumer body changes to
`consumer/` inside it, and the provenance body hands the path to a tool that
resolves its own root. `./.` is relative to the module that writes it, so it is
this SDK's directory whatever the caller started from.
`builtins.toString` and not a bare path interpolated into the string: a path
that keeps its string context can be copied into the read-only Nix store, and a
task that then changed into that copy would be building where it cannot write.
The path is quoted once, with `lib.escapeShellArg`, so no body re-quotes one by
hand. `sdk:provenance` also changes to the SDK root before invoking the script;
`tools/check-provenance.sh:28` independently resolves the repository from its
own `$0`.

**And the prefix, which is the same defect seen from the other side.** A
default `zig build` installs — `build.zig:679` (the artifact), `:689-691` (the
generated pkg-config file), `:703-705` (the three licence records) and `:722`
(the smoke program's compilation) are all behind the install step — so a task
that ran it with no prefix wrote a delivery tree into the checkout, which for
a source tree on a network mount is output nobody asked for. Both delivery
tasks therefore pass `--prefix` to `$ZIG_LOCAL_CACHE_DIR/predicates/static` or
`…/shared`, and refuse with a message when no local cache was named rather than
choose a location themselves. `build.zig` owns the installed layout either way;
`--prefix` only says where that layout lands, which is why this is an input to
the existing graph and not a change to it. Generated task programs retain
`"$@"`: `--prefix P`, `-p P` and `--prefix=P` are detected and used unchanged,
and other arguments reach `zig build` as written. devenv 2.4 `tasks run` cannot
forward arguments, so that CLI does not exercise this forwarding. All eight
Zig build routes supply fixed `-j8`, explicit `--cache-dir "$ZIG_LOCAL_CACHE_DIR"`
and `--summary all` before any forwarded arguments.

`test` (`build.zig:744`), `smoke` (`:730-731`, and `:724-727` records that it
deliberately does not run the install step), `check` (`:758-781`) and the
consumer package's `run` step (`consumer/build.zig:78-79`) install nothing, so
those bodies carry no prefix: there is no delivery output to move, and an
invented flag on a compile-only or run-only step would be noise.

Each Zig build task now runs `chooseCaches`, not only `enterShell`. Exported
cache values remain unchanged; missing values use `$XDG_CACHE_HOME`, then
`$TMPDIR`. Without either root the helper exits non-zero rather than allowing
Zig's default caches inside the checkout. The delivery helper's two branches
share this preamble and preserve the static/shared linkage defaults.

**Numerical review (source-only).** The translated `c` module is private:
`predicates.c` retains native linkage/dispatch, unlike `dep.module("c")`.
The consumer run forwards `b.args` for `--provider`. CI installing builds use
external prefixes and their installed consumers follow those paths.
`src/root.zig` and `README.zig.md` correct scratch and magnitude obligations
against `src/predicates.c:1446-1456,1491-1503,1575-1578,1627-1652`; the contrary
`include/predicates.h:153-161` comments remain unchanged by constraint.
The initialization guard now uses an ordinary comparison and panic in every
mode. The driver's before probes exposed the missing guard; initialized
controls returned the independent values `6` and `-6`.

**OBSERVED, 2026-10-04 (driver, Zig 0.16.0, x86_64-linux-gnu).** Both
ReleaseFast and ReleaseSmall after probes passed: all four builds exited `0`;
uninitialized runs exited `-6` (SIGABRT) with the facade's required panic;
initialized runs exited `0`, printing determinant `6` and reversed `-6`.
Let `A=/home/tmp2/gertullj/scratch/foundation-libs/numerical-contract-probes`,
`L=predicates-init-guard` or `predicates-init-control`, `M=ReleaseFast` or
`ReleaseSmall`, and `W=$A/work/relative-path-repair/after/$L/$M`.
From `$A/predicates`, the pinned compiler ran `build -j8 --summary all
--cache-dir $W/local --global-cache-dir $W/global --prefix $W/prefix
-Dtarget=x86_64-linux-gnu -Doptimize=$M -Dprobe=uninitialized` (guard) or
`-Dprobe=initialized` (control), then `$W/prefix/bin/numerical-probe`.
Exact compiler/argv and results: `$A/receipts/relative-path-repair/after/
{predicates-init-guard,predicates-init-control}/{ReleaseFast,ReleaseSmall}/receipt.json`.
These are focused guard/control results, not the permanent four-mode suite.
No execution was performed by this source worker.