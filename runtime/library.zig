// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored. `FORK-LICENSE.md` says what that identifier
// covers and on whose authority, and `NOTICE.md` carries the file inventory.
// `src/predicates.c` is Shewchuk's own public-domain file and is outside this
// identifier entirely.
//
//! Predicates' side of the runtime loader: the names its synchronization
//! binding has, and what it requires of a provider beyond resolving its
//! symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! Predicates', and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every declaration in `include/predicates.h`: forty functions and fifteen
//! globals, all of them, and nothing else.
//!
//! The functions are `exactinit` (line 65), the six debug helpers
//! `doublerand`, `narrowdoublerand`, `uniformdoublerand`, `floatrand`,
//! `narrowfloatrand` and `uniformfloatrand` (lines 77-82), the thirteen
//! expansion-arithmetic routines (lines 99-135), and the twenty geometric
//! predicates: `fast`, `exact`, `slow`, `adapt` and the adaptive entry point for
//! `orient2d`, `orient3d`, `incircle` and `insphere` (lines 164-186).
//!
//! The globals are `splitter`, `epsilon`, `resulterrbound` and the twelve error
//! bounds `ccwerrboundA/B/C`, `o3derrboundA/B/C`, `iccerrboundA/B/C` and
//! `isperrboundA/B/C` (lines 195-209). They are fifteen separate objects, not a
//! struct: `src/predicates.c:361-368` declares them as fifteen independent
//! `REAL` file-scope variables, and nothing in the translation ever reads them
//! through an aggregate. The dispatch therefore holds fifteen pointers and asks
//! for each symbol by name, and the requirement on a provider is fifteen
//! addressable, writable `double` objects - which is also exactly what
//! `exactinit` writes.
//!
//! Nothing is optional and nothing is excluded; `runtime/graph.zig` records the
//! same three lists, and they are empty on purpose.
//!
//! ## The ABI boundary, stated honestly
//!
//! This header has an unusually small ABI surface and an unusually large
//! *arithmetic* one, and it is worth separating the two.
//!
//! What a provider must match, and why each one matters:
//!
//!   * **C ABI of the platform.** Every entry point takes scalars and pointers
//!     and returns a scalar or an `int`. No function in the header passes or
//!     returns a struct, a union or an array by value
//!     (`include/predicates.h:99-186`), so there is no structure-return
//!     convention to agree on and no aggregate whose field order could drift.
//!     The provider has to be built by a toolchain for the same C ABI as this
//!     dispatch, which on every target this package supports means the same
//!     target triple, not merely the same architecture.
//!   * **Scalar widths.** `int` is `c_int`, 32 bits on every ABI in the
//!     six-target matrix. `PREDICATES_REAL` is `double`, because
//!     `src/predicates.c:133` hard-codes `#define REAL double` and
//!     `include/predicates.h:48-50` only offers `PREDICATES_REAL` as a spelling
//!     of it, so every coordinate, every expansion component and every error
//!     bound is an IEEE 754 binary64. `float` is `f32` in the three debug
//!     helpers that return it - `floatrand`, `narrowfloatrand` and
//!     `uniformfloatrand` (`include/predicates.h:77-82`). Nothing here widens
//!     or narrows a type.
//!   * **Layout.** The only objects with an address that crosses the boundary
//!     are those fifteen globals, and each is a single scalar. There is no
//!     padding between symbols that a caller could depend on, no table this
//!     library hands out, and no handle type: an expansion is a caller-owned
//!     `double` array plus a separate length, which is why no accessor here
//!     takes a pointer to a struct.
//!   * **Allocator.** None crosses this boundary. `src/predicates.c` calls no
//!     allocation function, frees nothing, and hands no ownership to the
//!     caller; every buffer it writes to is one the caller supplied and sized.
//!     Its one external call is POSIX `random()`
//!     (`src/predicates.c:503-505,529-531,552-553,572-573,597-598,619`),
//!     reached only from the six debug helpers - thirteen call sites, one
//!     range per helper in `include/predicates.h` order - and it is a C
//!     library function resolved inside the provider's own image rather than
//!     through this table.
//!   * **Code-generation configuration.** This is the one that decides whether
//!     a provider computes the right answer at all, and it is the reason the
//!     check below is about arithmetic rather than about a version.
//!     `Two_Product` and `Two_Two_Diff` are error-free transformations that
//!     assume each multiply and each subtract is separately rounded, so the
//!     implementation must be compiled with floating-point contraction disabled
//!     (`-ffp-contract=off`), without fast-math, and with the optimizer on -
//!     `include/predicates.h:24-32` states this and `build.zig` passes the
//!     first two. Excess precision has to be off too; upstream's escape hatch
//!     is `#define INEXACT volatile` and `src/predicates.c:130` leaves
//!     `INEXACT` empty, as upstream wrote it.
//!
//! ## What the check at load time establishes
//!
//! There is no version function, no build stamp and no self-description in this
//! library to ask, so resolving the symbols is the boundary and everything past
//! it has to be measured. `validate` measures it the only way this ABI allows:
//! it runs the provider's own `exactinit` on the candidate image and reads the
//! constants back out of the provider's own data.
//!
//! For IEEE 754 binary64 that measurement is exact and is written down in the
//! source rather than guessed. `exactinit` halves `epsilon` until adding it to
//! one no longer moves one (`src/predicates.c:658-666`), which stops at
//! `2^-53`; it doubles `splitter` on every other pass, 27 times over those same
//! iterations, and then adds one (`src/predicates.c:667`), which gives
//! `2^27 + 1`; and it derives `resulterrbound` from the measured `epsilon`
//! (`src/predicates.c:670`).
//!
//! So a candidate whose `exactinit` did not reach its own globals, or whose
//! `REAL` is not `double`, or whose data symbols resolved to something other
//! than its own writable storage, is refused by name here rather than returning
//! wrong signs to the first caller. Agreement on these three values is evidence
//! about the provider's arithmetic and its data, and it is not proof of
//! anything else: two builds that agree on them can still differ in how they
//! were compiled, which is the code-generation requirement above and is not
//! observable from inside the image. A provider that passes and was compiled
//! wrongly fails later, loudly, in upstream's own code.
//!
//! ## Calling `exactinit` during the load
//!
//! It is a side effect on the candidate, and it is deliberate. `validate` is
//! given a table already filled with the candidate's resolved addresses and runs
//! before anything is published, with no lock held
//! (`runtime/loader.zig:478-491`), so the call is invisible to every other
//! thread: nothing can reach this module until the release store that publishes
//! the table, and a candidate that fails the check is closed with the values
//! still in it. `exactinit` itself is pure arithmetic over the candidate's own
//! globals - it calls nothing, allocates nothing and takes no lock - so it
//! cannot re-enter the loader. If the candidate is refused, nothing survives the
//! close; if it is accepted, the constants are already the ones a caller needs
//! and the facade's own `init()` writes the identical values again under its
//! once-guard.
//!
//! ## Configuration boundaries of this package
//!
//! Three things about *this* package bound what a provider can be, and none of
//! them is something a loader flag can change.
//!
//!   * `x86_64-windows-gnu` has no build at all. `src/predicates.c` calls POSIX
//!     `random()`, which mingw-w64 and the UCRT do not provide, so the shared
//!     object a provider would have to be does not exist on that target. A
//!     Windows provider would need explicit exports in any case, since PE/COFF
//!     exports nothing by default and this source carries no
//!     `__declspec(dllexport)`.
//!   * A target with no dynamic loader, such as `wasm32-wasi`, has no provider
//!     to open. The loader refuses the request with `UnsupportedTarget` instead
//!     of falling back to a linked copy.
//!   * The delivered linkage. `-Dlinkage=dynamic` is what produces something a
//!     runtime-loading build can open; `-Dlinkage=static` produces an archive,
//!     which is not a provider. That is a boundary of the delivered
//!     configuration and not of this descriptor.

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=predicates_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn predicates_rt_lock() void;
    extern fn predicates_rt_unlock() void;
    extern fn predicates_rt_wait() void;
    extern fn predicates_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn predicates_rt_thread_self() u64;

    pub fn lock() void {
        predicates_rt_lock();
    }
    pub fn unlock() void {
        predicates_rt_unlock();
    }
    pub fn wait() void {
        predicates_rt_wait();
    }
    pub fn broadcast() void {
        predicates_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return predicates_rt_thread_self();
    }
};

/// `epsilon` after `exactinit` on IEEE 754 binary64: the first power of two
/// that `1.0 + x` rounds back to `1.0`, reached by halving from one
/// (`src/predicates.c:658-666`).
const binary64_epsilon: f64 = 0x1p-53;

/// `splitter` after `exactinit` on IEEE 754 binary64: `splitter` doubles on
/// every other pass of that same loop, 27 times for 53 passes, and then gains
/// one (`src/predicates.c:661-667`).
const binary64_splitter: f64 = 0x1p27 + 1.0;

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "predicates";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// This project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        ///
        /// This library publishes no version, so there is nothing to ask for and
        /// nothing to compare against. What there is instead is arithmetic that
        /// has one exact answer for a given floating-point format, and this runs
        /// it on the candidate and reads the result out of the candidate's own
        /// data. See the module documentation for why that measures what it
        /// claims to measure.
        pub fn validate(dst: *const table) ?[]const u8 {
            // The candidate is already in `dst` and nothing is published yet, so
            // this writes to an image no caller can reach.
            dst.exactinit();

            const epsilon = dst.epsilon.*;
            if (epsilon != binary64_epsilon) {
                return "exactinit() left epsilon at a value other than 2^-53, so " ++
                    "this provider was not built for IEEE 754 binary64 REAL, or " ++
                    "the fifteen file-scope globals are not the provider's own " ++
                    "writable storage";
            }

            const splitter = dst.splitter.*;
            if (splitter != binary64_splitter) {
                return "exactinit() left splitter at a value other than 2^27 + 1, " ++
                    "so this provider was not built for IEEE 754 binary64 REAL, or " ++
                    "the fifteen file-scope globals are not the provider's own " ++
                    "writable storage";
            }

            // The one derived value, checked because it is the error bound every
            // expansion routine scales its own result against
            // (`src/predicates.c:670`). A provider whose globals are live but
            // whose initialization ran against a different format still fails
            // here.
            const expected = (3.0 + 8.0 * binary64_epsilon) * binary64_epsilon;
            if (dst.resulterrbound.* != expected) {
                return "resulterrbound does not match the value exactinit() " ++
                    "derives from a binary64 epsilon, so the constants this " ++
                    "provider published were not produced by one exactinit run";
            }

            return null;
        }
    };
}