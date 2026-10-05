//! Zig facade over Shewchuk's adaptive-precision geometric predicates.
//!
//! `orient2d`, `orient3d`, `incircle` and `insphere` in their adaptive forms,
//! and the sign of each. Every number this module returns comes out of the
//! canonical C in `src/predicates.c`, reached through `pub const c`, the module
//! `b.addTranslateC` produces over `include/predicates.h`. The algorithms are
//! not reimplemented here, nothing is rescaled, and no guessed scale threshold
//! is put in front of upstream's arithmetic.
//!
//! ## Using it
//!
//! ```zig
//! const predicates = @import("predicates");
//!
//! pub fn main() !void {
//!     predicates.init(); // once per process, before any predicate
//!     _ = try predicates.orient2dSign(
//!         .{ .x = 0, .y = 0 },
//!         .{ .x = 1, .y = 0 },
//!         .{ .x = 0, .y = 1 },
//!     );
//! }
//! ```
//!
//! The published module name is `predicates`, so a dependent reaches this
//! facade through `dep.module("predicates")` and the raw upstream ABI through
//! `pub const c`. A predicate takes its points by value, allocates nothing and
//! has nothing to release. Requires Zig 0.16.0. `x86_64-windows-gnu` is not a
//! supported target: upstream's source calls POSIX `random()`, which neither
//! mingw-w64 nor the UCRT provides, so the C does not compile there and this
//! facade cannot be built for it.
//! ## Two configurations, one surface
//!
//! This module is published twice over, from the same file, and the raw `c`
//! surface is the *whole* declared surface in both: all forty functions of
//! `include/predicates.h` and all fifteen globals, not only the calls the
//! typed wrappers below happen to make.
//!
//!   * In a **linked** build, `c` is the translation step's own output and a
//!     call is an ordinary direct call into the C library the executable was
//!     linked with. `runtime_loaded` is `false`, `load` is a misuse that stops
//!     the program, and there is no table, no readiness check and no cost on
//!     any call.
//!   * In a **runtime-loading** build, `c` is a generated dispatch that
//!     re-exports the very same declarations from the very same translation -
//!     a type named here is one nominal type, never a look-alike - and reaches
//!     the library through one process-lifetime table that `load` fills from an
//!     explicitly named provider. `runtime_loaded` is `true`. Reaching any
//!     routed function, or any of the fifteen globals, before a successful load
//!     stops the program with a message naming the symbol; there is no implicit
//!     load, no fallback to a linked copy and no reset.
//!
//! A consumer that supports both writes `if (comptime predicates.runtime_loaded)`
//! and only the branch it chose is analysed.
//!
//! ### What a provider has to match
//!
//! `runtime/library.zig` carries the full record. In outline, because the
//! difference between these two lists is the whole risk:
//!
//!   * **External family.** The platform C ABI. Every entry point takes scalars
//!     and pointers and returns a scalar or an `int`; no struct, union or array
//!     is ever passed or returned by value
//!     (`include/predicates.h:99-186`), so there is no structure-return
//!     convention to match and no aggregate layout to agree on. A provider has
//!     to come from a toolchain for the same C ABI, not merely the same
//!     architecture.
//!   * **Scalars.** `int` is `c_int`; `PREDICATES_REAL` is IEEE 754 binary64,
//!     because `src/predicates.c:133` hard-codes `#define REAL double` and the
//!     header's `PREDICATES_REAL` override (`include/predicates.h:48-50`) only
//!     changes the spelling, never the type in this build. `float` is binary32
//!     in the three debug helpers that return it - `floatrand`,
//!     `narrowfloatrand` and `uniformfloatrand` (`include/predicates.h:77-82`).
//!   * **Data layout.** The only addressed objects that cross the boundary are
//!     the fifteen globals, each a single scalar in the provider's own data
//!     segment (`src/predicates.c:361-368`). They are fifteen separate symbols,
//!     not a struct, and nothing reads them through an aggregate. In a
//!     runtime-loading build they are reached as *live addresses* in the loaded
//!     image, never as copied values: a dispatch that snapshotted `epsilon`
//!     would report the provider's initialization, not the provider's data.
//!   * **Allocator.** None. `src/predicates.c` allocates nothing, frees nothing
//!     and transfers no ownership; every buffer it writes to is one the caller
//!     supplied and sized. Its one external call is POSIX `random()`, and the
//!     six debug helpers are the only code that makes it
//!     (`src/predicates.c:503-505,529-531,552-553,572-573,597-598,619`), one
//!     range per helper in `include/predicates.h` order, every one resolved
//!     inside the provider's own image.
//!   * **Code generation.** The requirement that decides whether any provider
//!     computes the right answer: `-ffp-contract=off`, no fast-math, optimizer
//!     on, and no excess precision. `Two_Product` and `Two_Two_Diff` are
//!     error-free transformations that assume each multiply and each subtract is
//!     separately rounded, so a fused multiply-add silently destroys the
//!     robustness this module exists for. `include/predicates.h:24-32` states it
//!     and `build.zig` passes it for the one translation unit that implements
//!     the predicates. Nothing observable from inside a provider reports it,
//!     which is why it is written down here rather than checked.
//!
//! ## Initialization
//!
//! `exactinit()` in the C computes `splitter`, `epsilon` and the roundoff error
//! bounds from the running floating-point format. Until it runs, all of them
//! are zero and robust C predicates have no sign guarantee. Upstream's
//! contract is "call exactinit() once, before anything else". The facade
//! enforces this precondition in every optimize mode and restates it on every
//! callable declaration:
//!
//!   * Call `init()` once during process start-up, before any predicate. It is
//!     idempotent, thread-safe, and cheap after the first call.
//!   * An ordinary comparison and panic diagnose a missed `init()` before any
//!     predicate or constant access in Debug, ReleaseSafe, ReleaseFast and
//!     ReleaseSmall. This programming error is not a recoverable return.
//!   * `init()` publishes the C globals with a release store, and every path
//!     that observes completion — its own fast path, the spin loop, and
//!     `isInitialized` — reads that store with an acquire load. A thread that
//!     sees the initialization done also sees the constants.
//!
//! `init()` runs `exactinit()` under a once-guard: exactly one thread ever
//! executes it. Calling `c.exactinit()` directly from several threads is a data
//! race on the file-scope globals even though every thread would write the same
//! values, because a concurrent write to a non-atomic object is undefined
//! behaviour whatever it writes. The once-guard is what makes repeated
//! initialization safe; it is not decoration.
//!
//! The `*fast` routines carry the same precondition although the C functions
//! they call read none of these globals. That is a deliberate facade duty and
//! not an upstream necessity: one initialization rule for the whole surface,
//! checked wherever it is called.
//!
//! ## Non-finite input
//!
//! The C has no contract for NaN or infinity. A NaN coordinate propagates
//! through every filter comparison and the routine returns a value that is not
//! a determinant of anything. This facade refuses that input: every predicate
//! checks all of its coordinates and returns `Error.NonFiniteCoordinate` before
//! calling into C. An infinity is not obviously better — `incircle` on infinite
//! coordinates can reach the adaptive engine — so it is refused too.
//!
//! This is a facade-level contract, not an upstream guarantee. A caller using
//! the `c` escape hatch directly gets upstream behaviour. Unlike the
//! initialization check, this one is an ordinary comparison and an error
//! return, so it rejects the same input in all four optimize modes.
//!
//! Being finite is not being well scaled. That check is the only one the
//! facade makes, and it says nothing about magnitude.
//!
//! ## Result contract
//!
//! The unsuffixed routines guarantee the SIGN of their result and nothing else,
//! and only inside the well-scaled domain described below. The magnitude is
//! upstream's rough determinant approximation: twice the signed area for
//! `orient2d` (`src/predicates.c:1413-1426`) or six times the signed volume for
//! `orient3d`. It may be the filtered determinant or an adaptive expansion
//! estimate/component, not a permanent scaled down. `detsum` and the permanent
//! scale internal error bounds, not the returned magnitude
//! (`src/predicates.c:1575-1578,1627-1652`).
//!
//! The raw `*exact` and `*slow` predicates take only point arrays and own their
//! local expansion scratch; callers do not allocate `expanarg` buffers
//! (`src/predicates.c:1446-1456,1491-1503,1802-1809,2502-2513,3617-3639`).
//! Call `init()` before using them too. This differs from the preserved
//! `include/predicates.h:153-161` comments, which incorrectly describe the
//! magnitude and a caller-owned scratch obligation.
//!
//! `Sign.zero` means the returned value was neither greater nor less than zero.
//! Inside the well-scaled domain that is exact degeneracy. Outside it the same
//! answer also covers a zero produced by an underflowing product and a NaN
//! produced by an overflowing filter, so `.zero` there does not establish exact
//! degeneracy. Read the sign, or use the `*Sign` wrappers, which are the
//! operation most callers actually want.
//!
//! The `*Fast` routines are upstream's deliberately non-robust versions: no
//! error analysis, so a near-degenerate input can and does give the wrong sign.
//! They are exposed because knowing when they fail is useful, and the test
//! suite pins that difference. Do not use them in a predicate you need to be
//! right.
//!
//! ## Range the upstream guarantee does not cover
//!
//! The adaptive routines are exact in the *sign* for well-scaled input. They
//! are not a guard against the double range itself, and they cannot be: their
//! first move is a filtered floating-point expression, and that expression is
//! where a coordinate at the edge of the range dies.
//!
//! Two concrete failures, both read out of the branch structure in
//! `src/predicates.c` rather than guessed:
//!
//!   * `orient2d((2^-1074, 0), (0, 2^-1074), (0, 0))` computes
//!     `detleft = 2^-1074 * 2^-1074 = 2^-2148`, which is below the smallest
//!     subnormal and rounds to zero. `detleft` is then neither positive nor
//!     negative, so the routine returns `det`, which is zero, for a
//!     configuration whose exact determinant is positive.
//!   * Near `floatMax` that same product overflows to infinity. When only one
//!     of the two products overflows, the opposite one is `<= 0.0` and the
//!     routine takes the early `return det` with an infinite magnitude whose
//!     sign is still correct. When both overflow with the same sign, `detsum`
//!     is infinite, `errbound = ccwerrboundA * detsum` is infinite, and `det`
//!     is `inf - inf`, which is NaN. NaN compares false in both directions, so
//!     the filter cannot resolve it and the NaN is passed to
//!     `orient2dadapt` with an infinite `detsum`.
//!
//! The first failure is settled by the branch. What the adaptive engine returns
//! from that NaN is not settled by reading it, so this module claims no outcome
//! beyond the arithmetic above, and `signOf` maps any result that is not
//! ordered, a NaN included, to `Sign.zero`.
//!
//! Neither is repaired here. Turning it into an error would mean guessing at a
//! scale threshold upstream never states, and a heuristic that is wrong in the
//! other direction is worse than an honest range. Scale the geometry into the
//! range where the products stay normal; that is what every consumer of these
//! predicates has always had to do.
//!
//! ## The raw C
//!
//! `pub const c` is the unmodified upstream ABI: the expansion arithmetic, the
//! `*exact`, `*slow` and `*adapt` routines, the random-value helpers, and the
//! globals `exactinit` writes. It is published surface, and it bypasses
//! everything above — no finite-coordinate rejection, no initialization
//! precondition, and upstream's own habit of needing `exactinit()` before
//! anything else, with a data race if several threads make that call at once.
//! The `*adapt` routines take a caller-computed error bound as an argument and
//! are helpers of the unsuffixed routines rather than entry points of their
//! own.
//!
//! ## The constants `exactinit` writes
//!
//! The fifteen file-scope globals are published surface, and `include/predicates.h:190-193`
//! gives one reason for that: a caller can assert the library was built for the
//! floating-point format it expects. The accessors below read them **out of the
//! live image** - the provider's own storage in a runtime-loading build, the
//! linked library's own storage otherwise - and never from a copy taken at
//! some earlier moment. That distinction is the whole point: after `init()` has
//! run, `epsilon()` and `c.epsilonAddr().*` (or `c.epsilon` in a linked build)
//! are the same storage, and if a dispatch were handing out a snapshot the two
//! would only agree by accident.
//!
//! `epsilon` and `splitter` are what the adaptive engine is actually built on.
//! On IEEE 754 binary64 `exactinit` leaves `epsilon` at `2^-53` and `splitter`
//! at `2^27 + 1` (`src/predicates.c:658-667`); reading them back is how a
//! caller finds out that a provider was initialized at all, and that it was
//! compiled for `REAL = double` rather than something narrower.
//!
//! They are read after the same initialization precondition the predicates
//! carry, for the same reason: before `init()` they are zero in both
//! configurations.

const std = @import("std");

/// Every declaration transcribed from `src/predicates.c`, translated to Zig.
/// It is the unmodified upstream ABI: the expansion arithmetic, the `*exact`,
/// `*slow` and `*adapt` routines, the random-value helpers, and the globals
/// `exactinit` writes.
///
/// Reaching for it bypasses the contracts this facade adds. Nothing here
/// rejects a non-finite coordinate, nothing checks initialization, and
/// `c.exactinit()` keeps upstream's own habit of needing one call before
/// anything else, with a data race if several threads make it at once. The
/// `*adapt` routines additionally take a caller-computed error bound as an
/// argument and are helpers of the unsuffixed routines, not entry points.
///
/// It is also, in a runtime-loading build, the surface that needs a loaded
/// provider: every function here and every one of the fifteen globals is
/// reached through the dispatch's table, and reaching one before `load` has
/// succeeded stops the program with a message naming the symbol. In a linked
/// build the same names are ordinary direct calls with nothing to load and
/// nothing to check.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same fifty-five symbols through the platform loader, in which
/// case `load` is the call that makes the library usable and every call before
/// it stops the program.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit absolute file path and `.system` is an explicit
/// basename for the platform loader. There is no path-to-system fallback and no
/// implicit fallback of any kind; a request that cannot be honoured is an
/// error, not a different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside
/// the loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// Before it returns, the loader has resolved all forty functions and all
/// fifteen globals, run the provider's own `exactinit` against them and checked
/// that the constants came out as IEEE 754 binary64 requires
/// (`runtime/library.zig`). A provider that is present but was not built for
/// this ABI is refused here, by name, rather than answering the first caller
/// with a wrong sign.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "predicates: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// A point in the plane, in the coordinate order upstream expects.
///
/// A plain value: copies are independent, every field is writable, and no
/// coordinate is checked until a predicate is called with it. The predicates
/// hand it to the C as the array `[x, y]`.
pub const Point2 = struct {
    x: f64,
    y: f64,
};

/// A point in space, in the coordinate order upstream expects.
///
/// A plain value: copies are independent, every field is writable, and no
/// coordinate is checked until a predicate is called with it. The predicates
/// hand it to the C as the array `[x, y, z]`.
pub const Point3 = struct {
    x: f64,
    y: f64,
    z: f64,
};

/// The sign of a predicate result. This, not the magnitude, is the part the
/// adaptive routines guarantee, and only inside the well-scaled domain the
/// module documentation describes.
pub const Sign = enum {
    /// The predicate returned a value smaller than zero.
    negative,
    /// The predicate returned a value that was neither greater nor less than
    /// zero. Inside the well-scaled domain that is exact degeneracy. Outside
    /// it the same answer also covers a product that underflowed to zero and a
    /// filter that overflowed to NaN, so it does not establish exact
    /// degeneracy there.
    zero,
    /// The predicate returned a value greater than zero.
    positive,

    /// The opposite sign, with zero mapped to itself. Convenient when a
    /// predicate decides which side of a plane a point is on and the two
    /// branches of the construction are symmetric.
    pub fn negate(self: Sign) Sign {
        return switch (self) {
            .negative => .positive,
            .zero => .zero,
            .positive => .negative,
        };
    }
};

/// Errors returned by the facade. Upstream has no error channel at all.
pub const Error = error{
    /// A coordinate was NaN or infinite. A checked return, live in every
    /// optimize mode, and it fires before any call into C. It says nothing
    /// about scale: finite coordinates can still form products outside the
    /// double range. See the module documentation.
    NonFiniteCoordinate,
};

const InitState = enum(u8) {
    pending,
    running,
    done,
};

/// Guards the C globals against concurrent re-initialization. The C file-scope
/// variables are ordinary mutable doubles, not atomics, so the only way to keep
/// the promise is to make sure exactly one thread ever writes them.
var init_state = std.atomic.Value(InitState).init(.pending);

/// Run `exactinit()` exactly once for this process, before any predicate.
///
/// Safe and cheap to call from any thread at any time: the first caller does
/// the work, later callers observe completion. A caller that arrives while the
/// first one is still inside `exactinit()` waits for it rather than racing it.
///
/// Completion is published with a release store and observed with an acquire
/// load on every path, the already-done fast path included, so a caller that
/// returns because initialization was done also sees the constants
/// `exactinit` wrote. Returns nothing, allocates nothing and owns nothing; a
/// call after the first has completed does no work.
pub fn init() void {
    if (init_state.load(.acquire) == .done) return;
    if (init_state.cmpxchgStrong(.pending, .running, .acquire, .monotonic) == null) {
        c.exactinit();
        init_state.store(.done, .release);
        return;
    }
    // Lost the race: either another thread is inside exactinit(), or it already
    // finished between our load and our compare-and-swap. Both cases resolve
    // here, and the acquire load pairs with the winner's release store.
    while (init_state.load(.acquire) != .done) std.atomic.spinLoopHint();
}

/// Whether `init()` has completed. Useful for asserting that a subsystem
/// initialized this library rather than the reverse.
///
/// Reads the same acquire load the predicates' precondition rests on, so a
/// `true` answer carries the constants `exactinit` wrote into every caller that
/// observes it. A `false` answer says only that this caller did not observe
/// completion; another thread may be inside `exactinit()` right now.
pub fn isInitialized() bool {
    return init_state.load(.acquire) == .done;
}

/// Panic before any native predicate or constant access if `init()` has not
/// completed. An ordinary comparison preserves this check in every mode.
fn requireInit() void {
    if (isInitialized()) return;
    std.debug.panic("predicates.init() must be called before using the facade", .{});
}

/// The live address of one of the fifteen file-scope globals `exactinit`
/// writes, in whichever configuration this build is.
///
/// In a runtime-loading build the dispatch publishes `NAMEAddr()` for each of
/// them, and calling it is what checks readiness and hands back the address the
/// loader resolved inside the loaded image. In a linked build the same object
/// is the linked library's own, and its address is taken directly. Neither path
/// copies a value, so a read through this pointer is a read of the provider's
/// own storage - which is the difference between reading `epsilon` and reading
/// a snapshot somebody took of it.
fn liveGlobal(comptime name: []const u8) *const f64 {
    if (comptime runtime_loaded) return @field(c, name ++ "Addr")();
    return &@field(c, name);
}

// ---------------------------------------------------------------------------
// The constants `exactinit` writes. Each is a read of the provider's own
// storage, through the same initialization precondition the predicates carry.
// ---------------------------------------------------------------------------

/// `epsilon`: the roundoff unit `exactinit` measured for the running
/// floating-point format (`src/predicates.c:658-666`). On IEEE 754 binary64 it
/// is exactly `2^-53`, the first power of two that `1.0 + x` rounds back to
/// `1.0`.
///
/// Requires `init()`; panics before reading the constant in every optimize mode.
pub fn epsilon() f64 {
    requireInit();
    return liveGlobal("epsilon").*;
}

/// `splitter`: the Dekker splitting factor the error-free transformations in
/// `src/predicates.c` depend on (`src/predicates.c:361,661-667`). On IEEE 754
/// binary64 it is exactly `2^27 + 1`. At zero the adaptive routines produce
/// noise rather than signs.
///
/// Requires `init()`; panics before reading the constant in every optimize mode.
pub fn splitter() f64 {
    requireInit();
    return liveGlobal("splitter").*;
}

/// `resulterrbound`, the bound every expansion routine scales a result against
/// (`src/predicates.c:364,670`).
///
/// Requires `init()`; panics before reading the constant in every optimize mode.
pub fn resultErrorBound() f64 {
    requireInit();
    return liveGlobal("resulterrbound").*;
}

/// `ccwerrboundA`, `ccwerrboundB`, `ccwerrboundC`: the roundoff bounds the
/// 2D orientation filter compares its result against
/// (`src/predicates.c:365,671-673`).
///
/// Requires `init()`; panics before reading the constants in every optimize mode.
pub fn orientationErrorBounds() [3]f64 {
    requireInit();
    return .{
        liveGlobal("ccwerrboundA").*,
        liveGlobal("ccwerrboundB").*,
        liveGlobal("ccwerrboundC").*,
    };
}

/// `o3derrboundA`, `o3derrboundB`, `o3derrboundC`: the roundoff bounds the 3D
/// orientation filter compares its result against
/// (`src/predicates.c:366,674-676`).
///
/// Requires `init()`; panics before reading the constants in every optimize mode.
pub fn orientation3dErrorBounds() [3]f64 {
    requireInit();
    return .{
        liveGlobal("o3derrboundA").*,
        liveGlobal("o3derrboundB").*,
        liveGlobal("o3derrboundC").*,
    };
}

/// `iccerrboundA`, `iccerrboundB`, `iccerrboundC`: the roundoff bounds the
/// in-circle filter compares its result against
/// (`src/predicates.c:367,677-679`).
///
/// Requires `init()`; panics before reading the constants in every optimize mode.
pub fn incircleErrorBounds() [3]f64 {
    requireInit();
    return .{
        liveGlobal("iccerrboundA").*,
        liveGlobal("iccerrboundB").*,
        liveGlobal("iccerrboundC").*,
    };
}

/// `isperrboundA`, `isperrboundB`, `isperrboundC`: the roundoff bounds the
/// in-sphere filter compares its result against
/// (`src/predicates.c:368,680-682`).
///
/// Requires `init()`; panics before reading the constants in every optimize mode.
pub fn insphereErrorBounds() [3]f64 {
    requireInit();
    return .{
        liveGlobal("isperrboundA").*,
        liveGlobal("isperrboundB").*,
        liveGlobal("isperrboundC").*,
    };
}

fn finite2(p: Point2) bool {
    return std.math.isFinite(p.x) and std.math.isFinite(p.y);
}

fn finite3(p: Point3) bool {
    return std.math.isFinite(p.x) and std.math.isFinite(p.y) and std.math.isFinite(p.z);
}

/// Maps a predicate's returned value onto the sign channel. A NaN is neither
/// greater nor less than zero, so it lands in `Sign.zero` together with an
/// exact zero. That is the documented behaviour outside the well-scaled
/// domain, not a case to repair here.
fn signOf(v: f64) Sign {
    return if (v > 0.0) .positive else if (v < 0.0) .negative else .zero;
}

// ---------------------------------------------------------------------------
// 2D orientation. The sign convention and the argument-order rule are stated on
// `orient2d`.
// ---------------------------------------------------------------------------

/// Robust 2D orientation. Positive when `pa`, `pb`, `pc` occur
/// counterclockwise, negative when clockwise, zero when collinear; a cyclic
/// rotation of the three keeps the sign and a transposition flips it.
///
/// The sign is guaranteed for well-scaled input. Read the sign, not the
/// magnitude: the value is upstream's adaptive determinant approximation, not
/// the permanent that scales its internal error bound.
///
/// Requires `init()`; panics before calling C in every optimize mode.
/// `Error.NonFiniteCoordinate` is a checked return in every mode and leaves
/// the native predicate uncalled.
pub fn orient2d(pa: Point2, pb: Point2, pc: Point2) Error!f64 {
    requireInit();
    if (!finite2(pa) or !finite2(pb) or !finite2(pc)) return Error.NonFiniteCoordinate;
    const a = [2]f64{ pa.x, pa.y };
    const b = [2]f64{ pb.x, pb.y };
    const d = [2]f64{ pc.x, pc.y };
    return c.orient2d(&a, &b, &d);
}

/// Sign of `orient2d`, which is the whole of what a caller can rely on.
///
/// `Sign.zero` is exact degeneracy inside the well-scaled domain and also
/// covers an underflowed zero and an overflowed NaN outside it. The `init()`
/// precondition panics in `orient2d` in every mode; non-finite coordinates
/// produce the same checked return.
pub fn orient2dSign(pa: Point2, pb: Point2, pc: Point2) Error!Sign {
    return signOf(try orient2d(pa, pb, pc));
}

/// Upstream's non-robust 2D orientation: no error analysis, so the sign is
/// wrong for near-collinear input. Use it only where that is acceptable.
///
/// Requires `init()` even though `orient2dfast` reads none of the globals
/// `exactinit` writes: the facade gives its whole surface one initialization
/// duty. Missing initialization panics before calling C in every mode.
/// `Error.NonFiniteCoordinate` is checked in all four modes.
pub fn orient2dfast(pa: Point2, pb: Point2, pc: Point2) Error!f64 {
    requireInit();
    if (!finite2(pa) or !finite2(pb) or !finite2(pc)) return Error.NonFiniteCoordinate;
    const a = [2]f64{ pa.x, pa.y };
    const b = [2]f64{ pb.x, pb.y };
    const d = [2]f64{ pc.x, pc.y };
    return c.orient2dfast(&a, &b, &d);
}

// ---------------------------------------------------------------------------
// 3D orientation. The sign convention is stated on `orient3d`.
// ---------------------------------------------------------------------------

/// Robust 3D orientation. Positive when `pd` lies below the plane through
/// `pa`, `pb`, `pc`, where below means those three look counterclockwise from
/// above the plane; negative when it lies above, zero when the four are
/// coplanar.
///
/// The sign is guaranteed for well-scaled input. Read the sign, not the
/// magnitude: the value is upstream's adaptive determinant approximation, of
/// which its own comment says only that it is roughly six times the signed
/// volume of the tetrahedron, and it is not the permanent that scales its
/// internal error bound.
///
/// Requires `init()`; panics before calling C in every optimize mode.
/// `Error.NonFiniteCoordinate` is a checked return in every mode and leaves
/// the native predicate uncalled.
pub fn orient3d(pa: Point3, pb: Point3, pc: Point3, pd: Point3) Error!f64 {
    requireInit();
    if (!finite3(pa) or !finite3(pb) or !finite3(pc) or !finite3(pd)) {
        return Error.NonFiniteCoordinate;
    }
    const a = [3]f64{ pa.x, pa.y, pa.z };
    const b = [3]f64{ pb.x, pb.y, pb.z };
    const d = [3]f64{ pc.x, pc.y, pc.z };
    const e = [3]f64{ pd.x, pd.y, pd.z };
    return c.orient3d(&a, &b, &d, &e);
}

/// Sign of `orient3d`. `Sign.zero` is exact degeneracy inside the well-scaled
/// domain and also covers an underflowed zero and an overflowed NaN outside
/// it; missing `init()` panics in `orient3d` in every optimize mode.
pub fn orient3dSign(pa: Point3, pb: Point3, pc: Point3, pd: Point3) Error!Sign {
    return signOf(try orient3d(pa, pb, pc, pd));
}

/// Upstream's non-robust 3D orientation: no error analysis, so the sign is
/// wrong for near-coplanar input.
///
/// Requires `init()` even though `orient3dfast` reads none of the globals
/// `exactinit` writes: the facade gives its whole surface one initialization
/// duty. Missing initialization panics before calling C in every mode.
/// `Error.NonFiniteCoordinate` is checked in all four modes.
pub fn orient3dfast(pa: Point3, pb: Point3, pc: Point3, pd: Point3) Error!f64 {
    requireInit();
    if (!finite3(pa) or !finite3(pb) or !finite3(pc) or !finite3(pd)) {
        return Error.NonFiniteCoordinate;
    }
    const a = [3]f64{ pa.x, pa.y, pa.z };
    const b = [3]f64{ pb.x, pb.y, pb.z };
    const d = [3]f64{ pc.x, pc.y, pc.z };
    const e = [3]f64{ pd.x, pd.y, pd.z };
    return c.orient3dfast(&a, &b, &d, &e);
}

// ---------------------------------------------------------------------------
// Incircle. The sign convention and the ordering requirement on the defining
// points are stated on `incircle`.
// ---------------------------------------------------------------------------

/// Robust in-circle test. Positive when `pd` lies inside the circle through
/// `pa`, `pb`, `pc`, negative when it lies outside, zero when the four points
/// are cocircular. The three defining points must be given counterclockwise;
/// this is an oriented predicate, not a membership test.
///
/// The sign is guaranteed for well-scaled input. Read the sign, not the
/// magnitude: the value is upstream's adaptive determinant approximation, not
/// the permanent that scales its internal error bound.
///
/// Requires `init()`; panics before calling C in every optimize mode.
/// `Error.NonFiniteCoordinate` is a checked return in every mode and leaves
/// the native predicate uncalled.
pub fn incircle(pa: Point2, pb: Point2, pc: Point2, pd: Point2) Error!f64 {
    requireInit();
    if (!finite2(pa) or !finite2(pb) or !finite2(pc) or !finite2(pd)) {
        return Error.NonFiniteCoordinate;
    }
    const a = [2]f64{ pa.x, pa.y };
    const b = [2]f64{ pb.x, pb.y };
    const d = [2]f64{ pc.x, pc.y };
    const e = [2]f64{ pd.x, pd.y };
    return c.incircle(&a, &b, &d, &e);
}

/// Sign of `incircle`. `Sign.zero` is exact degeneracy inside the well-scaled
/// domain and also covers an underflowed zero and an overflowed NaN outside
/// it; missing `init()` panics in `incircle` in every optimize mode.
pub fn incircleSign(pa: Point2, pb: Point2, pc: Point2, pd: Point2) Error!Sign {
    return signOf(try incircle(pa, pb, pc, pd));
}

/// Upstream's non-robust in-circle test: no error analysis, so the sign is
/// wrong for near-cocircular input. It keeps the same counterclockwise
/// requirement on the defining points.
///
/// Requires `init()` even though `incirclefast` reads none of the globals
/// `exactinit` writes: the facade gives its whole surface one initialization
/// duty. Missing initialization panics before calling C in every mode.
/// `Error.NonFiniteCoordinate` is checked in all four modes.
pub fn incirclefast(pa: Point2, pb: Point2, pc: Point2, pd: Point2) Error!f64 {
    requireInit();
    if (!finite2(pa) or !finite2(pb) or !finite2(pc) or !finite2(pd)) {
        return Error.NonFiniteCoordinate;
    }
    const a = [2]f64{ pa.x, pa.y };
    const b = [2]f64{ pb.x, pb.y };
    const d = [2]f64{ pc.x, pc.y };
    const e = [2]f64{ pd.x, pd.y };
    return c.incirclefast(&a, &b, &d, &e);
}

// ---------------------------------------------------------------------------
// Insphere. The sign convention and the ordering requirement on the defining
// points are stated on `insphere`.
// ---------------------------------------------------------------------------

/// Robust in-sphere test. Positive when `pe` lies inside the sphere through
/// `pa`, `pb`, `pc`, `pd`, negative when it lies outside, zero when the five
/// points are cospherical. The four defining points must be ordered so that
/// `orient3d` on them is positive; any other order reverses the sign.
///
/// The sign is guaranteed for well-scaled input. Read the sign, not the
/// magnitude: the value is upstream's adaptive determinant approximation, not
/// the permanent that scales its internal error bound.
///
/// Requires `init()`; panics before calling C in every optimize mode.
/// `Error.NonFiniteCoordinate` is a checked return in every mode and leaves
/// the native predicate uncalled.
pub fn insphere(pa: Point3, pb: Point3, pc: Point3, pd: Point3, pe: Point3) Error!f64 {
    requireInit();
    if (!finite3(pa) or !finite3(pb) or !finite3(pc) or !finite3(pd) or !finite3(pe)) {
        return Error.NonFiniteCoordinate;
    }
    const a = [3]f64{ pa.x, pa.y, pa.z };
    const b = [3]f64{ pb.x, pb.y, pb.z };
    const d = [3]f64{ pc.x, pc.y, pc.z };
    const e = [3]f64{ pd.x, pd.y, pd.z };
    const f = [3]f64{ pe.x, pe.y, pe.z };
    return c.insphere(&a, &b, &d, &e, &f);
}

/// Sign of `insphere`. `Sign.zero` is exact degeneracy inside the well-scaled
/// domain and also covers an underflowed zero and an overflowed NaN outside
/// it; missing `init()` panics in `insphere` in every optimize mode.
pub fn insphereSign(pa: Point3, pb: Point3, pc: Point3, pd: Point3, pe: Point3) Error!Sign {
    return signOf(try insphere(pa, pb, pc, pd, pe));
}

/// Upstream's non-robust in-sphere test: no error analysis, so the sign is
/// wrong for near-cospherical input. It keeps the same orientation
/// requirement on the defining points.
///
/// Requires `init()` even though `inspherefast` reads none of the globals
/// `exactinit` writes: the facade gives its whole surface one initialization
/// duty. Missing initialization panics before calling C in every mode.
/// `Error.NonFiniteCoordinate` is checked in all four modes.
pub fn inspherefast(pa: Point3, pb: Point3, pc: Point3, pd: Point3, pe: Point3) Error!f64 {
    requireInit();
    if (!finite3(pa) or !finite3(pb) or !finite3(pc) or !finite3(pd) or !finite3(pe)) {
        return Error.NonFiniteCoordinate;
    }
    const a = [3]f64{ pa.x, pa.y, pa.z };
    const b = [3]f64{ pb.x, pb.y, pb.z };
    const d = [3]f64{ pc.x, pc.y, pc.z };
    const e = [3]f64{ pd.x, pd.y, pd.z };
    const f = [3]f64{ pe.x, pe.y, pe.z };
    return c.inspherefast(&a, &b, &d, &e, &f);
}
