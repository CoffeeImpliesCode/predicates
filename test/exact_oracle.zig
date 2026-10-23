//! An exact, independent sign oracle for the four geometric predicates.
//!
//! This file exists so the tests compare the adaptive C implementation against
//! arithmetic that cannot be wrong in the way the C can be. It shares no code,
//! no approximation and no error analysis with upstream: it evaluates the
//! determinant of each predicate in exact integer arithmetic, so the only thing
//! it can get wrong is the algebra, and the algebra is checked by reading it.
//!
//! ## Why integers and not more floating point
//!
//! The predicates are sign problems, and the interesting inputs are the ones
//! where the floating-point filter cannot decide. A double-double (about 106
//! bits) is not enough: an `insphere` determinant over coordinates spanning the
//! full double exponent range needs over ten thousand bits. So every coordinate
//! is decomposed into an exact integer mantissa and a power of two, all
//! coordinates are scaled by a common power of two so they become integers,
//! and the determinant is evaluated in arbitrary-precision integers. Scaling by
//! a power of two multiplies the determinant by a positive constant — 2^(-k·emin)
//! for a degree-k polynomial — so the sign is unchanged.
//!
//! That common factor is the "rational" half: the exact value being computed is
//! the determinant of the input rationals, and scaling only clears denominators.
//!
//! ## Where the algebra comes from
//!
//! orient2d, orient3d and incircle use the textbook forms relative to the last
//! point, which is the arrangement upstream's error analysis is built around.
//! insphere uses the 5-point circumsphere determinant in relative coordinates,
//!
//!     det =  lift_d * det3(A,B,C) - lift_c * det3(D,A,B)
//!         +  lift_b * det3(C,D,A) - lift_a * det3(B,C,D)
//!
//! with A = a - e ... D = d - e and lift_u = |u|². Expanding upstream's
//! `insphereexact` expansion tree in that arrangement and collecting terms
//! reproduces it term for term; the derivation is in FORK-NOTES.md so it can be
//! re-checked against the C without running anything.
//!
//! Note that this oracle is exact but not cheap: it is O(n²) in bignum limbs.
//! It belongs in tests, never in a hot path.

const std = @import("std");

const Big = std.math.big.int.Managed;
const Allocator = std.mem.Allocator;

/// The sign of an exact determinant. Deliberately declared here rather than
/// imported from the facade, so a wrong answer in the facade cannot be matched
/// by a wrong answer in the oracle.
pub const Sign = enum {
    negative,
    zero,
    positive,
};

pub const Error = error{
    /// A coordinate was NaN or infinite, so there is no determinant to speak of.
    NonFiniteCoordinate,
    /// The allocator ran out while building an intermediate.
    OutOfMemory,
};

/// A finite `v` is exactly `m * 2^e` with `m` an integer of at most 53 bits.
/// The exponent range of a finite double is [-1074, 971].
const Decomposed = struct {
    m: i64,
    e: i32,
};

fn decompose(v: f64) Error!Decomposed {
    if (!std.math.isFinite(v)) return Error.NonFiniteCoordinate;
    const bits: u64 = @bitCast(v);
    const negative = (bits >> 63) != 0;
    const biased: u32 = @intCast((bits >> 52) & 0x7ff);
    const fraction = bits & 0x000f_ffff_ffff_ffff;

    var m: i64 = undefined;
    var e: i32 = undefined;
    if (biased == 0) {
        // Zero, or a subnormal: the significand has no implicit bit and the
        // exponent is pinned at the bottom of the range.
        if (fraction == 0) return .{ .m = 0, .e = 0 };
        m = @intCast(fraction);
        e = -1074;
    } else {
        m = @as(i64, @intCast(fraction)) | (@as(i64, 1) << 52);
        e = @as(i32, @intCast(biased)) - 1075;
    }
    return .{ .m = if (negative) -m else m, .e = e };
}

/// The smallest exponent in the input, so that scaling by `2^-emin` clears the
/// denominator of every coordinate at once.
fn minExponent(coords: []const f64) Error!i32 {
    var emin: i32 = 0;
    for (coords) |v| {
        const d = try decompose(v);
        emin = @min(emin, d.e);
    }
    return emin;
}

/// `v * 2^-emin`, as an exact integer.
fn scaled(gpa: Allocator, v: f64, emin: i32) Error!Big {
    const d = try decompose(v);
    var out = try Big.init(gpa);
    // Managed's shift is three arguments, destination first, and it allows the
    // destination to alias the source.
    if (d.m < 0) {
        try out.set(-d.m);
        try out.shiftLeft(&out, @intCast(d.e - emin));
        out.negate();
    } else {
        try out.set(d.m);
        try out.shiftLeft(&out, @intCast(d.e - emin));
    }
    return out;
}

fn add(gpa: Allocator, a: Big, b: Big) Error!Big {
    var out = try Big.init(gpa);
    try out.add(&a, &b);
    return out;
}

fn sub(gpa: Allocator, a: Big, b: Big) Error!Big {
    var out = try Big.init(gpa);
    try out.sub(&a, &b);
    return out;
}

fn mul(gpa: Allocator, a: Big, b: Big) Error!Big {
    var out = try Big.init(gpa);
    try out.mul(&a, &b);
    return out;
}

fn signOf(v: Big) Sign {
    if (v.eqlZero()) return .zero;
    return if (v.isPositive()) .positive else .negative;
}

/// The three coordinates of a point, already scaled to exact integers.
const Vec2 = [2]Big;
const Vec3 = [3]Big;

fn vec2(gpa: Allocator, v: anytype, emin: i32) Error!Vec2 {
    return .{ try scaled(gpa, v[0], emin), try scaled(gpa, v[1], emin) };
}

fn vec3(gpa: Allocator, v: anytype, emin: i32) Error!Vec3 {
    return .{
        try scaled(gpa, v[0], emin),
        try scaled(gpa, v[1], emin),
        try scaled(gpa, v[2], emin),
    };
}

fn lift2(gpa: Allocator, v: Vec2) Error!Big {
    const dx = try mul(gpa, v[0], v[0]);
    const dy = try mul(gpa, v[1], v[1]);
    return add(gpa, dx, dy);
}

fn lift3(gpa: Allocator, v: Vec3) Error!Big {
    const dx = try mul(gpa, v[0], v[0]);
    const dy = try mul(gpa, v[1], v[1]);
    const dz = try mul(gpa, v[2], v[2]);
    return add(gpa, try add(gpa, dx, dy), dz);
}

/// `u . (v x w)` for three 3-vectors of exact integers.
fn det3(gpa: Allocator, u: *const Vec3, v: *const Vec3, w: *const Vec3) Error!Big {
    const x = try sub(gpa, try mul(gpa, v[1], w[2]), try mul(gpa, v[2], w[1]));
    const y = try sub(gpa, try mul(gpa, v[2], w[0]), try mul(gpa, v[0], w[2]));
    const z = try sub(gpa, try mul(gpa, v[0], w[1]), try mul(gpa, v[1], w[0]));
    return try add(gpa, try add(gpa, try mul(gpa, u[0], x), try mul(gpa, u[1], y)), try mul(gpa, u[2], z));
}

/// `(u - w) . ((v - w) x (t - w))`, the 2x3 determinant used by orient3d.
fn det3diff(gpa: Allocator, u: Vec3, v: Vec3, t: Vec3, w: Vec3) Error!Big {
    const a = [3]Big{
        try sub(gpa, u[0], w[0]),
        try sub(gpa, u[1], w[1]),
        try sub(gpa, u[2], w[2]),
    };
    const b = [3]Big{
        try sub(gpa, v[0], w[0]),
        try sub(gpa, v[1], w[1]),
        try sub(gpa, v[2], w[2]),
    };
    const c = [3]Big{
        try sub(gpa, t[0], w[0]),
        try sub(gpa, t[1], w[1]),
        try sub(gpa, t[2], w[2]),
    };
    return det3(gpa, &a, &b, &c);
}

// ---------------------------------------------------------------------------
// The four predicates.
//
// Sign conventions, matching src/predicates.c:
//   orient2d  positive when a, b, c run counterclockwise.
//   orient3d  positive when d lies below the plane of a, b, c.
//   incircle  positive when d is inside the circle through a, b, c, given
//             that a, b, c run counterclockwise.
//   insphere  positive when e is inside the sphere through a, b, c, d, given
//             that a, b, c, d run counterclockwise seen from outside.
// ---------------------------------------------------------------------------

/// Exact sign of the 2D orientation determinant of a, b, c.
pub fn orient2dSign(gpa: Allocator, ax: f64, ay: f64, bx: f64, by: f64, cx: f64, cy: f64) Error!Sign {
    const emin = try minExponent(&.{ ax, ay, bx, by, cx, cy });
    const a = try vec2(gpa, .{ ax, ay }, emin);
    const b = try vec2(gpa, .{ bx, by }, emin);
    const c = try vec2(gpa, .{ cx, cy }, emin);

    const det = try sub(
        gpa,
        try mul(gpa, try sub(gpa, a[0], c[0]), try sub(gpa, b[1], c[1])),
        try mul(gpa, try sub(gpa, a[1], c[1]), try sub(gpa, b[0], c[0])),
    );
    return signOf(det);
}

/// Exact sign of the 3D orientation determinant of a, b, c, d.
pub fn orient3dSign(
    gpa: Allocator,
    ax: f64,
    ay: f64,
    az: f64,
    bx: f64,
    by: f64,
    bz: f64,
    cx: f64,
    cy: f64,
    cz: f64,
    dx: f64,
    dy: f64,
    dz: f64,
) Error!Sign {
    const emin = try minExponent(&.{ ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz });
    const a = try vec3(gpa, .{ ax, ay, az }, emin);
    const b = try vec3(gpa, .{ bx, by, bz }, emin);
    const c = try vec3(gpa, .{ cx, cy, cz }, emin);
    const d = try vec3(gpa, .{ dx, dy, dz }, emin);

    // One determinant, not a sum of three. Upstream's orient3d computes
    //     adx*(bdy*cdz - bdz*cdy) + bdx*(cdy*adz - cdz*ady)
    //                                    + cdx*(ady*bdz - adz*bdy)
    // which is exactly A . (B x C) for A = a-d, B = b-d, C = c-d: the second
    // and third terms expand to ady*(bdz*cdx - bdx*cdz) + adz*(bdx*cdy - bdy*cdx).
    // Summing det3 over a cycle of arguments would add six further products and
    // be wrong.
    const det = try det3diff(gpa, a, b, c, d);
    return signOf(det);
}

/// Exact sign of the in-circle determinant of a, b, c, d.
pub fn incircleSign(gpa: Allocator, ax: f64, ay: f64, bx: f64, by: f64, cx: f64, cy: f64, dx: f64, dy: f64) Error!Sign {
    const emin = try minExponent(&.{ ax, ay, bx, by, cx, cy, dx, dy });
    const a = try vec2(gpa, .{ ax, ay }, emin);
    const b = try vec2(gpa, .{ bx, by }, emin);
    const c = try vec2(gpa, .{ cx, cy }, emin);
    const d = try vec2(gpa, .{ dx, dy }, emin);

    const ad = [2]Big{ try sub(gpa, a[0], d[0]), try sub(gpa, a[1], d[1]) };
    const bd = [2]Big{ try sub(gpa, b[0], d[0]), try sub(gpa, b[1], d[1]) };
    const cd = [2]Big{ try sub(gpa, c[0], d[0]), try sub(gpa, c[1], d[1]) };

    const abdet = try sub(gpa, try mul(gpa, ad[0], bd[1]), try mul(gpa, bd[0], ad[1]));
    const bcdet = try sub(gpa, try mul(gpa, bd[0], cd[1]), try mul(gpa, cd[0], bd[1]));
    const cadet = try sub(gpa, try mul(gpa, cd[0], ad[1]), try mul(gpa, ad[0], cd[1]));

    const det = try add(
        gpa,
        try add(
            gpa,
            try mul(gpa, try lift2(gpa, ad), bcdet),
            try mul(gpa, try lift2(gpa, bd), cadet),
        ),
        try mul(gpa, try lift2(gpa, cd), abdet),
    );
    return signOf(det);
}

/// Exact sign of the in-sphere determinant of a, b, c, d, e.
pub fn insphereSign(
    gpa: Allocator,
    ax: f64,
    ay: f64,
    az: f64,
    bx: f64,
    by: f64,
    bz: f64,
    cx: f64,
    cy: f64,
    cz: f64,
    dx: f64,
    dy: f64,
    dz: f64,
    ex: f64,
    ey: f64,
    ez: f64,
) Error!Sign {
    const emin = try minExponent(&.{
        ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, ex, ey, ez,
    });
    const a0 = try vec3(gpa, .{ ax, ay, az }, emin);
    const b0 = try vec3(gpa, .{ bx, by, bz }, emin);
    const c0 = try vec3(gpa, .{ cx, cy, cz }, emin);
    const d0 = try vec3(gpa, .{ dx, dy, dz }, emin);
    const e0 = try vec3(gpa, .{ ex, ey, ez }, emin);

    const a: Vec3 = .{
        try sub(gpa, a0[0], e0[0]),
        try sub(gpa, a0[1], e0[1]),
        try sub(gpa, a0[2], e0[2]),
    };
    const b: Vec3 = .{
        try sub(gpa, b0[0], e0[0]),
        try sub(gpa, b0[1], e0[1]),
        try sub(gpa, b0[2], e0[2]),
    };
    const c: Vec3 = .{
        try sub(gpa, c0[0], e0[0]),
        try sub(gpa, c0[1], e0[1]),
        try sub(gpa, c0[2], e0[2]),
    };
    const d: Vec3 = .{
        try sub(gpa, d0[0], e0[0]),
        try sub(gpa, d0[1], e0[1]),
        try sub(gpa, d0[2], e0[2]),
    };

    const abc = try det3(gpa, &a, &b, &c);
    const bcd = try det3(gpa, &b, &c, &d);
    const cda = try det3(gpa, &c, &d, &a);
    const dab = try det3(gpa, &d, &a, &b);

    const det = try add(
        gpa,
        try sub(
            gpa,
            try mul(gpa, try lift3(gpa, d), abc),
            try mul(gpa, try lift3(gpa, c), dab),
        ),
        try sub(
            gpa,
            try mul(gpa, try lift3(gpa, b), cda),
            try mul(gpa, try lift3(gpa, a), bcd),
        ),
    );
    return signOf(det);
}

// ---------------------------------------------------------------------------
// Self-checks of the oracle itself.
//
// These run with no reference to the C library, so a failure here localises to
// this file rather than to the thing under test.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "decompose pins the mantissa/exponent convention" {
    // The convention is IEEE 754's own: `m` is the *full* 53-bit significand
    // with the implicit bit already in place, so a normal double always has
    // 2^52 <= |m| < 2^53, and `v == m * 2^e` exactly.  A zero or a subnormal
    // has no implicit bit: zero is (0, 0) and a subnormal is its raw fraction
    // at e = -1074.
    const cases = [_]struct { v: f64, m: i64, e: i32 }{
        .{ .v = 0.0, .m = 0, .e = 0 },
        .{ .v = -0.0, .m = 0, .e = 0 },
        // 1.0 == 2^52 * 2^-52.
        .{ .v = 1.0, .m = 4503599627370496, .e = -52 },
        .{ .v = -1.0, .m = -4503599627370496, .e = -52 },
        .{ .v = 0.5, .m = 4503599627370496, .e = -53 },
        // 3.0 == (1.5 * 2^52) * 2^-51.
        .{ .v = 3.0, .m = 6755399441055744, .e = -51 },
        // 3.5 == (1.75 * 2^52) * 2^-51.
        .{ .v = -3.5, .m = -7881299347898368, .e = -51 },
        // 1024.0 == 2^52 * 2^-42.
        .{ .v = 1024.0, .m = 4503599627370496, .e = -42 },
        // 2^53 - 1 is the largest significand a double carries, reached at
        // biased exponent 1075, so its `e` is 0.
        .{ .v = 9007199254740991.0, .m = 9007199254740991, .e = 0 },
        // The smallest subnormal has no implicit bit: raw fraction 1.
        .{ .v = 4.9406564584124654e-324, .m = 1, .e = -1074 },
        // The largest finite double is 2^1024 - 2^971, i.e. the full
        // significand at the top biased exponent.
        .{ .v = 1.7976931348623157e308, .m = 9007199254740991, .e = 971 },
    };
    for (cases) |case| {
        const d = try decompose(case.v);
        try testing.expectEqual(case.m, d.m);
        try testing.expectEqual(case.e, d.e);
    }
}

test "decompose round-trips every value it produced" {
    const cases = [_]f64{
        0.0,   -0.0,
        1.0,   -1.0,
        0.5,   0.1,
        -0.1,  1e-300,
        1e300, -1e-300,
        4.9406564584124654e-324, // smallest subnormal
        1.7976931348623157e308, // largest finite
        9007199254740991.0, // 2^53 - 1
        0.30000000000000004,
    };
    for (cases) |v| {
        const d = try decompose(v);
        // |m| has to leave room for the negation in `scaled`, or a negative
        // coordinate would come out positive.
        try testing.expect(d.m <= (@as(i64, 1) << 53));
        try testing.expect(d.m >= -(@as(i64, 1) << 53));
        // Convert the mantissa to f64 before `ldexp`. Compare values, not bit
        // patterns, because decomposition maps -0.0 to 0 and the oracle ignores
        // a zero's sign.
        const rebuilt = std.math.ldexp(@as(f64, @floatFromInt(d.m)), d.e);
        try testing.expect(rebuilt == v);
    }
}

test "oracle orient2d agrees with hand-computed determinants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // a=(0,0) b=(1,0) c=(0,1): cross((a-c),(b-c)) = cross((0,-1),(1,-1))
    // = 0*(-1) - (-1)*1 = 1, counterclockwise.
    try testing.expectEqual(Sign.positive, try orient2dSign(gpa, 0, 0, 1, 0, 0, 1));
    try testing.expectEqual(Sign.negative, try orient2dSign(gpa, 1, 0, 0, 0, 0, 1));
    // Three points on the diagonal: an exact zero, not a rounding artefact.
    try testing.expectEqual(Sign.zero, try orient2dSign(gpa, 0, 0, 1, 1, 2, 2));
    // Repeated points always give an exact zero.
    try testing.expectEqual(Sign.zero, try orient2dSign(gpa, 3, -4, 3, -4, 3, -4));
    // The cancellation case the fast path gets wrong:
    // (1+2^-52)(1-2^-52) - 1*1 = -2^-104, which does not survive a double.
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    try testing.expectEqual(Sign.negative, try orient2dSign(gpa, 1 + bump, 1, 1, 1 - bump, 0, 0));
}

test "oracle orient3d agrees with a hand-computed determinant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // a=(0,0,0) b=(1,0,0) c=(0,1,0) d=(0,0,1). Relative to d the three
    // difference vectors are (0,0,-1), (1,0,-1) and (0,1,-1); the determinant
    // is (0,0,-1) . ((1,0,-1) x (0,1,-1)) = (0,0,-1) . (1,1,1) = -1, so the
    // apex is above the plane.
    try testing.expectEqual(Sign.negative, try orient3dSign(gpa, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1));
    // Reflecting the apex flips the determinant.
    try testing.expectEqual(Sign.positive, try orient3dSign(gpa, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, -1));
    // Four points on the plane z = 0: an exact zero.
    try testing.expectEqual(Sign.zero, try orient3dSign(gpa, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0));
    // The apex coinciding with a base vertex is an exact zero too.
    try testing.expectEqual(Sign.zero, try orient3dSign(gpa, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0));
}

test "oracle incircle agrees with a hand-computed determinant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Unit circle through (1,0) (0,1) (-1,0), counterclockwise, origin inside.
    // Relative to d=(0,0): ad=(1,0) bd=(0,1) cd=(-1,0), so alift=bcdet=1,
    // blift=abdet=1, cadet=0, clift=1 and det = 1 + 0 + 1 = 2.
    try testing.expectEqual(Sign.positive, try incircleSign(gpa, 1, 0, 0, 1, -1, 0, 0, 0));
    // The same three points with the order reversed gives det = -2.
    try testing.expectEqual(Sign.negative, try incircleSign(gpa, -1, 0, 0, 1, 1, 0, 0, 0));
    // (0,-1) lies on that same circle, so this is an exact zero.
    try testing.expectEqual(Sign.zero, try incircleSign(gpa, 1, 0, 0, 1, -1, 0, 0, -1));
    // Repeating one of the defining points is an exact zero too.
    try testing.expectEqual(Sign.zero, try incircleSign(gpa, 1, 0, 0, 1, -1, 0, 1, 0));
}

test "oracle insphere agrees with a hand-computed determinant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // a=(1,0,0) b=(0,1,0) c=(0,0,1) d=(-1,-1,-1) is a non-degenerate
    // tetrahedron. Its circumsphere has centre (-1/4,-1/4,-1/4) and squared
    // radius 27/16. The origin is inside it and the determinant works out
    // to 6 > 0.
    try testing.expectEqual(Sign.positive, try insphereSign(gpa, 1, 0, 0, 0, 1, 0, 0, 0, 1, -1, -1, -1, 0, 0, 0));
    // (2,2,2) is well outside that sphere: squared distance from the centre
    // is 3*(9/4)^2 = 243/16, past the 27/16 radius.
    try testing.expectEqual(Sign.negative, try insphereSign(gpa, 1, 0, 0, 0, 1, 0, 0, 0, 1, -1, -1, -1, 2, 2, 2));
    // (1/2,1/2,1/2) is exactly on that sphere: squared distance from the
    // centre is 3*(3/4)^2 = 27/16, so the determinant is exactly zero.
    try testing.expectEqual(Sign.zero, try insphereSign(gpa, 1, 0, 0, 0, 1, 0, 0, 0, 1, -1, -1, -1, 0.5, 0.5, 0.5));
    // Four coplanar points span no sphere at all, so the determinant is
    // identically zero whatever the fifth point is.
    try testing.expectEqual(Sign.zero, try insphereSign(gpa, 1, 0, 0, 0, 1, 0, -1, 0, 0, 0, -1, 0, 0, 0, 1));
}

test "oracle rejects non-finite input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const nan = std.math.nan(f64);
    const inf = std.math.inf(f64);
    try testing.expectError(Error.NonFiniteCoordinate, orient2dSign(gpa, nan, 0, 1, 0, 0, 1));
    try testing.expectError(Error.NonFiniteCoordinate, orient2dSign(gpa, 0, 0, 1, 0, 0, inf));
    try testing.expectError(Error.NonFiniteCoordinate, orient3dSign(gpa, nan, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1));
    try testing.expectError(Error.NonFiniteCoordinate, incircleSign(gpa, 0, inf, 1, 0, 0, 1, 0, 0));
    try testing.expectError(Error.NonFiniteCoordinate, insphereSign(gpa, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, inf));
}
