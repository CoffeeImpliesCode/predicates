//! Zig facade over Shewchuk's adaptive-precision geometric predicates.
//!
//! The algorithms are not reimplemented here. Every number this module returns
//! comes out of the canonical C in `src/predicates.c`, reached through
//! `pub const c`, the module produced by `b.addTranslateC` over
//! `include/predicates.h`. What this module adds is the part a C header cannot
//! express: typed points, a documented initialization lifecycle, and an
//! explicit contract for the one input class the C has no answer for.
//!
//! ## Initialization
//!
//! `exactinit()` in the C computes `splitter`, `epsilon` and the roundoff error
//! bounds from the running floating-point format. Until it runs, all of them
//! are zero and every robust predicate here returns a wrong answer. Upstream's
//! contract is "call exactinit() once, before anything else". That contract is
//! easy to state and easy to break by accident, so it is enforced here:
//!
//!   * Call `predicates.init()` once during process start-up, before any
//!     predicate. It is idempotent, thread-safe, and cheap after the first
//!     call.
//!   * Every predicate asserts that it has happened. The assertion is live in
//!     Debug and ReleaseSafe and compiled out in ReleaseFast, so a debug build
//!     of a consumer reports the mistake at the call site instead of returning
//!     silently wrong signs.
//!
//! `init()` runs `exactinit()` under a once-guard: exactly one thread ever
//! executes it. Calling `c.exactinit()` directly from several threads is a data
//! race on the file-scope globals even though every thread would write the same
//! values, because a concurrent write to a non-atomic object is undefined
//! behaviour whatever it writes. The once-guard is what makes repeated
//! initialization safe; it is not decoration.
//!
//! ## Non-finite input
//!
//! The C has no contract for NaN or infinity. A NaN coordinate propagates
//! through every filter comparison and the routine returns a value that is not a
//! determinant of anything. This facade refuses that input: every predicate
//! checks all of its coordinates and returns `Error.NonFiniteCoordinate` before
//! calling into C. An infinity is not obviously better — `incircle` on infinite
//! coordinates can reach the adaptive engine — so it is refused too.
//!
//! This is a facade-level contract, not an upstream guarantee. A caller using
//! the `c` escape hatch directly gets upstream behaviour.
//!
//! ## Result contract
//!
//! The unsuffixed routines guarantee the SIGN of their result and nothing else.
//! The magnitude is a scaled approximation of the permanent of the filtered
//! determinant. Read the sign, or use the `*Sign` wrappers, which are the
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
//! The first failure is settled by the branch. The second is not: what the
//! adaptive engine does with that NaN has not been probed on any host, so
//! nothing further is claimed here beyond the arithmetic above.
//!
//! Neither is repaired here. Turning it into an error would mean guessing at a
//! scale threshold upstream never states, and a heuristic that is wrong in the
//! other direction is worse than an honest range. Scale the geometry into the
//! range where the products stay normal; that is what every consumer of these
//! predicates has always had to do.

const std = @import("std");

/// Every declaration transcribed from `src/predicates.c`, translated to Zig.
/// Use it for the expansion arithmetic, the `*exact` and `*slow` reference
/// implementations, and the random-value helpers. It is the unmodified
/// upstream ABI.
pub const c = @import("c");

/// A point in the plane, in the coordinate order upstream expects.
pub const Point2 = struct {
    x: f64,
    y: f64,
};

/// A point in space, in the coordinate order upstream expects.
pub const Point3 = struct {
    x: f64,
    y: f64,
    z: f64,
};

/// The sign of a predicate result. This, not the magnitude, is the part the
/// adaptive routines guarantee.
pub const Sign = enum {
    negative,
    zero,
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
    /// A coordinate was NaN or infinite. See the module documentation.
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
pub fn init() void {
    if (init_state.load(.monotonic) == .done) return;
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
pub fn isInitialized() bool {
    return init_state.load(.monotonic) == .done;
}

/// Live in Debug and ReleaseSafe, compiled out in ReleaseFast. A predicate
/// reached before `init()` returns a number with no error analysis behind it,
/// and the sign can be wrong; that is a programming error, not a runtime
/// condition, so it is an assert and not an error.
fn requireInit() void {
    std.debug.assert(isInitialized());
}

fn finite2(p: Point2) bool {
    return std.math.isFinite(p.x) and std.math.isFinite(p.y);
}

fn finite3(p: Point3) bool {
    return std.math.isFinite(p.x) and std.math.isFinite(p.y) and std.math.isFinite(p.z);
}

fn signOf(v: f64) Sign {
    return if (v > 0.0) .positive else if (v < 0.0) .negative else .zero;
}

// ---------------------------------------------------------------------------
// 2D orientation.
//
// orient2d is positive when pa, pb, pc appear in counterclockwise order, zero
// when they are collinear, negative when clockwise. It does not matter which
// point is passed where: the determinant is alternating, so a cyclic rotation
// preserves the sign and a transposition flips it.
// ---------------------------------------------------------------------------

/// Robust 2D orientation. Guaranteed sign, approximate magnitude.
pub fn orient2d(pa: Point2, pb: Point2, pc: Point2) Error!f64 {
    requireInit();
    if (!finite2(pa) or !finite2(pb) or !finite2(pc)) return Error.NonFiniteCoordinate;
    const a = [2]f64{ pa.x, pa.y };
    const b = [2]f64{ pb.x, pb.y };
    const d = [2]f64{ pc.x, pc.y };
    return c.orient2d(&a, &b, &d);
}

/// Sign of `orient2d`, which is the whole of what a caller can rely on.
pub fn orient2dSign(pa: Point2, pb: Point2, pc: Point2) Error!Sign {
    return signOf(try orient2d(pa, pb, pc));
}

/// Upstream's non-robust 2D orientation. No error analysis: the sign is wrong
/// for near-collinear inputs.
pub fn orient2dfast(pa: Point2, pb: Point2, pc: Point2) Error!f64 {
    requireInit();
    if (!finite2(pa) or !finite2(pb) or !finite2(pc)) return Error.NonFiniteCoordinate;
    const a = [2]f64{ pa.x, pa.y };
    const b = [2]f64{ pb.x, pb.y };
    const d = [2]f64{ pc.x, pc.y };
    return c.orient2dfast(&a, &b, &d);
}

// ---------------------------------------------------------------------------
// 3D orientation.
//
// orient3d is positive when pd lies below the plane through pa, pb, pc, where
// "below" means pa, pb, pc look counterclockwise from above the plane. Zero
// means coplanar.
// ---------------------------------------------------------------------------

/// Robust 3D orientation. Guaranteed sign, approximate magnitude: roughly six
/// times the signed volume of the tetrahedron.
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

/// Sign of `orient3d`.
pub fn orient3dSign(pa: Point3, pb: Point3, pc: Point3, pd: Point3) Error!Sign {
    return signOf(try orient3d(pa, pb, pc, pd));
}

/// Upstream's non-robust 3D orientation.
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
// Incircle.
//
// incircle is positive when pd lies inside the circle through pa, pb, pc,
// assuming pa, pb, pc are in counterclockwise order. The sign convention for
// the in-circle test reverses if the caller reverses the order of pa, pb, pc;
// the magnitude scales with it.
// ---------------------------------------------------------------------------

/// Robust in-circle test. Guaranteed sign, approximate magnitude.
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

/// Sign of `incircle`.
pub fn incircleSign(pa: Point2, pb: Point2, pc: Point2, pd: Point2) Error!Sign {
    return signOf(try incircle(pa, pb, pc, pd));
}

/// Upstream's non-robust in-circle test.
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
// Insphere.
//
// insphere is positive when pe lies inside the sphere through pa, pb, pc, pd,
// assuming pa, pb, pc, pd are in counterclockwise order seen from outside.
// ---------------------------------------------------------------------------

/// Robust in-sphere test. Guaranteed sign, approximate magnitude.
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

/// Sign of `insphere`.
pub fn insphereSign(pa: Point3, pb: Point3, pc: Point3, pd: Point3, pe: Point3) Error!Sign {
    return signOf(try insphere(pa, pb, pc, pd, pe));
}

/// Upstream's non-robust in-sphere test.
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
