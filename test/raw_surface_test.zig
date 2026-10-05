// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored. `FORK-LICENSE.md` says what that identifier
// covers and on whose authority, and `NOTICE.md` carries the file inventory.
//
//! Behavioural tests for the raw `predicates.c` surface.
//!
//! The typed wrappers in `src/root.zig` are a convenience layer over forty
//! functions and fifteen globals, and most of that surface has no wrapper at
//! all: the `*exact` and `*slow` reference implementations, the four `*adapt`
//! filters, and every file-scope constant. This file exercises those through
//! `pub const c`, which is the published escape hatch a dependent reaches for.
//!
//! Three things are checked here, and each of them is a claim about behaviour
//! rather than about wiring:
//!
//!   * The non-adaptive `*exact` and `*slow` implementations agree, in sign,
//!     with the adaptive entry point and with `exact_oracle.zig`'s exact
//!     integer arithmetic on the same inputs - including the near-degenerate
//!     fixtures the filter cannot decide from magnitude alone. Upstream keeps
//!     the three as independent implementations of one determinant, so three
//!     implementations and an independent oracle that disagree would mean one
//!     of them is wrong, and the oracle is the only witness that can say which.
//!
//!   * The `*adapt` filters have the two branches their contract describes: the
//!     caller-supplied error bound decides whether the routine returns its
//!     filtered approximation or falls through to exact arithmetic. Both ends
//!     of that decision are pinned here, on fixtures where the two branches
//!     return different numbers - which is also what makes the test sensitive
//!     to `ccwerrboundB` actually having been written. With it still zero,
//!     `errbound` is zero for every input, the branch at
//!     `src/predicates.c:1577` is always taken, and the sign assertions below
//!     fail. No sensitivity to `resulterrbound` or `ccwerrboundC` is claimed:
//!     the refinement at `src/predicates.c:1591` does read both, but on every
//!     fixture here the filtered `det` it is handed is exactly `0.0`, so
//!     `resulterrbound * |det|` contributes nothing and `ccwerrboundC` only
//!     scales a term far below the value in play. Zeroing either changes no
//!     answer this file observes.
//!
//!   * The fifteen file-scope constants are read as live data and checked
//!     against the values one `exactinit` run writes for the running
//!     floating-point format, which this file re-derives from the loop in
//!     `src/predicates.c:649-667` rather than reading from the library. That
//!     distinguishes a provider whose globals were initialized, in its own
//!     storage, for this format, from one that handed back zeros, from one
//!     built for a narrower `REAL`, and from a snapshot of a provider that was
//!     not. The typed accessors are checked against the same derivation, so a
//!     dispatch that resolved the raw symbols and a facade that did not would
//!     disagree.

const std = @import("std");
const testing = std.testing;

const predicates = @import("predicates");
const oracle = @import("exact_oracle.zig");
const support = @import("support.zig");

const c = predicates.c;

const Point2 = predicates.Point2;
const Point3 = predicates.Point3;

const Scratch = struct {
    arena: std.heap.ArenaAllocator,

    fn init() Scratch {
        return .{ .arena = std.heap.ArenaAllocator.init(testing.allocator) };
    }
    fn deinit(self: *Scratch) void {
        self.arena.deinit();
    }
    fn allocator(self: *Scratch) std.mem.Allocator {
        return self.arena.allocator();
    }
};

/// The oracle declares its own sign enum, so a facade result and an oracle
/// result are compared as data rather than as two views of one tagged value.
fn bridge(s: oracle.Sign) predicates.Sign {
    return switch (s) {
        .negative => .negative,
        .zero => .zero,
        .positive => .positive,
    };
}

/// A returned value's sign, and nothing else: the magnitude of an adaptive or
/// exact determinant is upstream's own approximation and is not guaranteed.
fn signOf(v: f64) predicates.Sign {
    return if (v > 0.0) .positive else if (v < 0.0) .negative else .zero;
}

/// Carries the fixture index into the assertion, so a mismatch names the case.
const Report = struct {
    case: usize,
    sign: predicates.Sign,
};

/// The live address of one of the fifteen constants, through the *raw* route.
///
/// The runtime-loading dispatch publishes `NAMEAddr()` per data symbol and that
/// accessor is what checks readiness and returns the address the loader
/// resolved inside the loaded image. A linked build has no accessor and no
/// table, and the linked library's own storage is the same object.
fn rawGlobal(comptime name: []const u8) *const f64 {
    if (comptime predicates.runtime_loaded) return @field(c, name ++ "Addr")();
    return &@field(c, name);
}

// ---------------------------------------------------------------------------
// The three exact implementations of each determinant.
// ---------------------------------------------------------------------------

test "orient2d exact and slow agree with the adaptive entry point and the oracle" {
    try support.ready();
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const triangles = [_][3]Point2{
        .{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 } },
        .{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 } },
        .{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 } },
        // The one-ulp cancellation: exact determinant -2^-104, about 2^-156 of
        // the terms it comes from. Only exact arithmetic decides it.
        .{ .{ .x = 1 + bump, .y = 1 }, .{ .x = 1, .y = 1 - bump }, .{ .x = 0, .y = 0 } },
        // Exactly collinear, so the answer is zero and every implementation has
        // to produce an exact zero rather than a tiny residue.
        .{ .{ .x = 0.5, .y = 0.5 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 } },
        // A hair off the same line.
        .{ .{ .x = 1, .y = 1 }, .{ .x = 1 + bump, .y = 1 }, .{ .x = 1, .y = 1 + 2 * bump } },
    };
    for (triangles, 0..) |t, index| {
        const a = [2]f64{ t[0].x, t[0].y };
        const b = [2]f64{ t[1].x, t[1].y };
        const d = [2]f64{ t[2].x, t[2].y };
        var scratch = Scratch.init();
        defer scratch.deinit();
        const want = Report{
            .case = index,
            .sign = bridge(try oracle.orient2dSign(
                scratch.allocator(),
                t[0].x,
                t[0].y,
                t[1].x,
                t[1].y,
                t[2].x,
                t[2].y,
            )),
        };
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.orient2dexact(&a, &b, &d)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.orient2dslow(&a, &b, &d)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.orient2d(&a, &b, &d)) });
    }
}

test "orient3d exact and slow agree with the adaptive entry point and the oracle" {
    try support.ready();
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const tetrahedra = [_][4]Point3{
        .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        },
        .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = -1 },
        },
        // Four coplanar points: an exact zero.
        .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 1, .y = 1, .z = 0 },
        },
        // A sliver: the determinant is a product of two 1e-13 terms.
        .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 1e-13, .y = 1e-13, .z = -1 },
        },
        // Four points a few ulps off a single plane, which is where a filtered
        // implementation is most likely to lose the sign.
        .{
            .{ .x = 1, .y = 1, .z = 1 },
            .{ .x = 1, .y = 1 + bump, .z = 1 },
            .{ .x = 1 + bump, .y = 1, .z = 1 },
            .{ .x = 1, .y = 1, .z = 1 + 4 * bump },
        },
    };
    for (tetrahedra, 0..) |q, index| {
        const a = [3]f64{ q[0].x, q[0].y, q[0].z };
        const b = [3]f64{ q[1].x, q[1].y, q[1].z };
        const d = [3]f64{ q[2].x, q[2].y, q[2].z };
        const e = [3]f64{ q[3].x, q[3].y, q[3].z };
        var scratch = Scratch.init();
        defer scratch.deinit();
        const want = Report{
            .case = index,
            .sign = bridge(try oracle.orient3dSign(
                scratch.allocator(),
                q[0].x,
                q[0].y,
                q[0].z,
                q[1].x,
                q[1].y,
                q[1].z,
                q[2].x,
                q[2].y,
                q[2].z,
                q[3].x,
                q[3].y,
                q[3].z,
            )),
        };
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.orient3dexact(&a, &b, &d, &e)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.orient3dslow(&a, &b, &d, &e)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.orient3d(&a, &b, &d, &e)) });
    }
}

test "incircle exact and slow agree with the adaptive entry point and the oracle" {
    try support.ready();
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const quadruples = [_][4]Point2{
        .{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 } },
        .{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 7, .y = -3 } },
        .{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 } },
        // Exactly cocircular: an exact zero.
        .{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = -1 } },
        // One ulp outside that circle, where the filter cannot decide from the
        // magnitude and the exact branch has to produce the answer.
        .{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = -(1 + bump) } },
        // Three collinear defining points span no circle.
        .{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = 3, .y = 3 } },
    };
    for (quadruples, 0..) |q, index| {
        const a = [2]f64{ q[0].x, q[0].y };
        const b = [2]f64{ q[1].x, q[1].y };
        const d = [2]f64{ q[2].x, q[2].y };
        const e = [2]f64{ q[3].x, q[3].y };
        var scratch = Scratch.init();
        defer scratch.deinit();
        const want = Report{
            .case = index,
            .sign = bridge(try oracle.incircleSign(
                scratch.allocator(),
                q[0].x,
                q[0].y,
                q[1].x,
                q[1].y,
                q[2].x,
                q[2].y,
                q[3].x,
                q[3].y,
            )),
        };
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.incircleexact(&a, &b, &d, &e)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.incircleslow(&a, &b, &d, &e)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.incircle(&a, &b, &d, &e)) });
    }
}

test "insphere exact and slow agree with the adaptive entry point and the oracle" {
    try support.ready();
    const s0: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const s1: Point3 = .{ .x = 0, .y = 1, .z = 0 };
    const s2: Point3 = .{ .x = 0, .y = 0, .z = 1 };
    const s3: Point3 = .{ .x = -1, .y = -1, .z = -1 };
    // Circumcentre (-1/4,-1/4,-1/4), squared radius 27/16, so these are the
    // exact-inside, exact-on and exact-outside answers for one sphere.
    const quintuples = [_][5]Point3{
        .{ s0, s1, s2, s3, .{ .x = 0, .y = 0, .z = 0 } },
        .{ s0, s1, s2, s3, .{ .x = 0.5, .y = 0.5, .z = 0.5 } },
        .{ s0, s1, s2, s3, .{ .x = 5, .y = 5, .z = 5 } },
        // The fifth point repeats a defining point.
        .{ s0, s1, s2, s3, s0 },
        // Four coplanar defining points span no sphere at all.
        .{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = -1, .y = 0, .z = 0 },
            .{ .x = 0, .y = -1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 3 },
        },
        // Three collinear defining points span no sphere either.
        .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 1, .y = 1, .z = 1 },
            .{ .x = 2, .y = 2, .z = 2 },
            .{ .x = 3, .y = 3, .z = 3 },
            .{ .x = 0, .y = 0, .z = 9 },
        },
    };
    for (quintuples, 0..) |q, index| {
        const a = [3]f64{ q[0].x, q[0].y, q[0].z };
        const b = [3]f64{ q[1].x, q[1].y, q[1].z };
        const d = [3]f64{ q[2].x, q[2].y, q[2].z };
        const e = [3]f64{ q[3].x, q[3].y, q[3].z };
        const f = [3]f64{ q[4].x, q[4].y, q[4].z };
        var scratch = Scratch.init();
        defer scratch.deinit();
        const want = Report{
            .case = index,
            .sign = bridge(try oracle.insphereSign(
                scratch.allocator(),
                q[0].x,
                q[0].y,
                q[0].z,
                q[1].x,
                q[1].y,
                q[1].z,
                q[2].x,
                q[2].y,
                q[2].z,
                q[3].x,
                q[3].y,
                q[3].z,
                q[4].x,
                q[4].y,
                q[4].z,
            )),
        };
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.insphereexact(&a, &b, &d, &e, &f)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.insphereslow(&a, &b, &d, &e, &f)) });
        try testing.expectEqual(want, Report{ .case = index, .sign = signOf(c.insphere(&a, &b, &d, &e, &f)) });
    }
}

// ---------------------------------------------------------------------------
// The `*adapt` filters: one caller-supplied number decides which branch runs.
// ---------------------------------------------------------------------------

test "the adaptive filter takes its branch from the error bound it is given" {
    try support.ready();
    // The one-ulp cancellation again: the exact determinant is -2^-104 while
    // each product rounds to 1.0 in binary64. What the filter returns is *not*
    // zero, and that is the contract rather than an accident of rounding:
    // `Two_Product` (`src/predicates.c:213`) returns the rounded product and
    // the exact rounding error as separate values, `Two_Two_Diff` (`:265`)
    // folds both products' heads and tails into one nonoverlapping expansion,
    // and `estimate` (`:1392`) sums it. The tail `-2^-104` is the only record
    // the determinant left anywhere, so the filtered approximation is the
    // exact determinant, correctly rounded.
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const a = [2]f64{ 1 + bump, 1 };
    const b = [2]f64{ 1, 1 - bump };
    const d = [2]f64{ 0, 0 };

    // A zero error bound makes `ccwerrboundB * detsum` zero, and
    // `(det >= 0) || (-det >= 0)` holds for every det, so `src/predicates.c:1577`
    // takes the first branch and returns `det` unchanged. The filter never
    // clamps to zero - there is no such step in `orient2dadapt`, and every
    // value it returns is one the expansion computed - so the branch-1 answer
    // here is the exact -2^-104.
    try testing.expectEqual(-std.math.ldexp(@as(f64, 1.0), -104), c.orient2dadapt(&a, &b, &d, 0.0));

    // The non-robust routine is what loses the determinant, and the two are
    // meant to disagree here: `orient2dfast` (`src/predicates.c:1443`) is
    // `acx * bcy - acy * bcx` in binary64, so both products round to 1.0 and
    // it reports zero for a triangle that is not collinear. The oracle below
    // computes -2^-104 in exact integer arithmetic, which is what makes the
    // filter's answer the correct one of the two.
    try testing.expectEqual(0.0, c.orient2dfast(&a, &b, &d));

    // An error bound of one is astronomically larger than the determinant, so
    // the filter declines at `src/predicates.c:1577` and runs the tails branch.
    // Every coordinate difference against the origin is exact, so `:1586-1589`
    // returns `det` again and the value does not change. Keeping the fixture
    // says plainly what it can and cannot show: branch 1 and branch 2 agree on
    // this input, so on its own it does not demonstrate that the bound was
    // read at all. The fixture below is the one that does.
    var scratch = Scratch.init();
    defer scratch.deinit();
    const want = bridge(try oracle.orient2dSign(scratch.allocator(), a[0], a[1], b[0], b[1], d[0], d[1]));
    try testing.expectEqual(predicates.Sign.negative, want);
    try testing.expectEqual(want, signOf(c.orient2dadapt(&a, &b, &d, 1.0)));

    // The unsuffixed entry point computes the bound itself and reaches the same
    // answer, which is the whole of its contract.
    try testing.expectEqual(want, signOf(c.orient2d(&a, &b, &d)));

    // Catastrophic cancellation, which is what the adaptive filter is for. Both
    // products are 2^108 and cancel exactly in the expansion, so the filtered
    // value is exactly zero; the determinant that the rounding threw away is
    // -2^54, and only the tails still carry it. Taking the branch here returns
    // zero for a triangle that is nowhere near collinear.
    const far = std.math.ldexp(@as(f64, 1.0), 54);
    const p = [2]f64{ 0, 0 };
    const q = [2]f64{ 0, 1 };
    const r = [2]f64{ far, far };
    try testing.expectEqual(0.0, c.orient2dfast(&p, &q, &r));
    try testing.expectEqual(0.0, c.orient2dadapt(&p, &q, &r, 0.0));

    // A bound of one is far above that filtered zero, so the filter declines,
    // the refinement at `src/predicates.c:1592` adds the discarded -2^54 back,
    // and the sign comes out negative. This is the assertion that is sensitive
    // to `ccwerrboundB` having been written: were it still zero, `errbound`
    // would be zero for every input, branch 1 would always be taken, and both
    // this value and the sign would be the zero asserted above.
    const want_far = bridge(try oracle.orient2dSign(scratch.allocator(), p[0], p[1], q[0], q[1], r[0], r[1]));
    try testing.expectEqual(predicates.Sign.negative, want_far);
    try testing.expectEqual(-far, c.orient2dadapt(&p, &q, &r, 1.0));

    // And `orient2d` reaches the same answer by computing the bound itself.
    try testing.expectEqual(want_far, signOf(c.orient2d(&p, &q, &r)));
}

// ---------------------------------------------------------------------------
// The fifteen file-scope constants, as live data.
// ---------------------------------------------------------------------------

/// What one `exactinit` writes for the running floating-point format.
///
/// `src/predicates.c:649-667`, transcribed: halve `epsilon` until adding it to
/// one no longer moves one, doubling `splitter` on every other pass, then add
/// one to it. Nothing here reads the library, which is what makes it a witness
/// rather than a restatement.
const Measured = struct {
    epsilon: f64,
    splitter: f64,
};

fn measured() Measured {
    var every_other = true;
    var epsilon: f64 = 1.0;
    var splitter: f64 = 1.0;
    var check: f64 = 1.0;
    while (true) {
        const lastcheck = check;
        epsilon *= 0.5;
        if (every_other) splitter *= 2.0;
        every_other = !every_other;
        check = 1.0 + epsilon;
        if (check == 1.0 or check == lastcheck) break;
    }
    return .{ .epsilon = epsilon, .splitter = splitter + 1.0 };
}

/// One family of three bounds, exactly as `src/predicates.c:671-682` writes
/// them: `(n0 + n1 * epsilon) * epsilon`, and the third one squared. The
/// coefficients are transcribed from those lines and are not derived from the
/// library, so a family that was never initialized, or that was initialized
/// from a different epsilon, cannot satisfy them.
const BoundFamily = struct {
    a: []const u8,
    b: []const u8,
    c: []const u8,
    a0: f64,
    a1: f64,
    b0: f64,
    b1: f64,
    c0: f64,
    c1: f64,
};

const bound_families = [_]BoundFamily{
    .{ .a = "ccwerrboundA", .b = "ccwerrboundB", .c = "ccwerrboundC", .a0 = 3, .a1 = 16, .b0 = 2, .b1 = 12, .c0 = 9, .c1 = 64 },
    .{ .a = "o3derrboundA", .b = "o3derrboundB", .c = "o3derrboundC", .a0 = 7, .a1 = 56, .b0 = 3, .b1 = 28, .c0 = 26, .c1 = 288 },
    .{ .a = "iccerrboundA", .b = "iccerrboundB", .c = "iccerrboundC", .a0 = 10, .a1 = 96, .b0 = 4, .b1 = 48, .c0 = 44, .c1 = 576 },
    .{ .a = "isperrboundA", .b = "isperrboundB", .c = "isperrboundC", .a0 = 16, .a1 = 224, .b0 = 5, .b1 = 72, .c0 = 71, .c1 = 1408 },
};

fn expectedBounds(family: BoundFamily, e: f64) struct { a: f64, b: f64, c: f64 } {
    return .{
        .a = (family.a0 + family.a1 * e) * e,
        .b = (family.b0 + family.b1 * e) * e,
        .c = (family.c0 + family.c1 * e) * e * e,
    };
}

test "the fifteen constants are the ones one exactinit run writes, read live" {
    try support.ready();
    const want = measured();

    // The two the adaptive engine is literally built on. For IEEE 754 binary64
    // these are 2^-53 and 2^27 + 1, but the test asserts the measured values
    // rather than those constants, so it states what it means: the provider's
    // constants describe the format this dispatch was translated for.
    try testing.expectEqual(want.epsilon, predicates.epsilon());
    try testing.expectEqual(want.splitter, predicates.splitter());
    try testing.expectEqual(want.epsilon, rawGlobal("epsilon").*);
    try testing.expectEqual(want.splitter, rawGlobal("splitter").*);

    const e = want.epsilon;

    try testing.expectEqual((3.0 + 8.0 * e) * e, predicates.resultErrorBound());
    try testing.expectEqual((3.0 + 8.0 * e) * e, rawGlobal("resulterrbound").*);

    // `inline` because `rawGlobal` names its global at comptime time, and a
    // runtime `for` would hand it a runtime string. The table is five rows of
    // comptime-known names, so unrolling it specializes each row rather than
    // weakening the assertion: all fifteen constants are still read live.
    inline for (bound_families) |family| {
        const want_bounds = expectedBounds(family, e);
        try testing.expectEqual(want_bounds.a, rawGlobal(family.a).*);
        try testing.expectEqual(want_bounds.b, rawGlobal(family.b).*);
        try testing.expectEqual(want_bounds.c, rawGlobal(family.c).*);
    }
}

test "the typed accessors and the raw route read the same provider storage" {
    try support.ready();
    // A dispatch that resolved the symbols and a facade that did not would
    // give different numbers here. So would a dispatch that snapshotted the
    // values at load time instead of addressing the provider's own data: the
    // snapshot and the live object would only agree while nothing wrote to the
    // globals, and `exactinit` is the one thing that always does.
    try testing.expectEqual(rawGlobal("epsilon").*, predicates.epsilon());
    try testing.expectEqual(rawGlobal("splitter").*, predicates.splitter());
    try testing.expectEqual(rawGlobal("resulterrbound").*, predicates.resultErrorBound());

    const raw_orientation = .{
        rawGlobal("ccwerrboundA").*,
        rawGlobal("ccwerrboundB").*,
        rawGlobal("ccwerrboundC").*,
    };
    try testing.expectEqual(raw_orientation, predicates.orientationErrorBounds());
    const raw_orientation3d = .{
        rawGlobal("o3derrboundA").*,
        rawGlobal("o3derrboundB").*,
        rawGlobal("o3derrboundC").*,
    };
    try testing.expectEqual(raw_orientation3d, predicates.orientation3dErrorBounds());
    const raw_incircle = .{
        rawGlobal("iccerrboundA").*,
        rawGlobal("iccerrboundB").*,
        rawGlobal("iccerrboundC").*,
    };
    try testing.expectEqual(raw_incircle, predicates.incircleErrorBounds());
    const raw_insphere = .{
        rawGlobal("isperrboundA").*,
        rawGlobal("isperrboundB").*,
        rawGlobal("isperrboundC").*,
    };
    try testing.expectEqual(raw_insphere, predicates.insphereErrorBounds());

    // And the adaptive engine is answering from those constants, not from a
    // private copy of them. This is the catastrophic-cancellation fixture from
    // the filter test above, and it is the one whose sign depends on
    // `ccwerrboundB` being non-zero: with that global still zero, `errbound`
    // is zero for every input, the branch at `src/predicates.c:1577` is always
    // taken, and this returns the filtered zero - sign `zero`, not `negative`.
    const far = std.math.ldexp(@as(f64, 1.0), 54);
    try testing.expectEqual(
        predicates.Sign.negative,
        try predicates.orient2dSign(
            .{ .x = 0, .y = 0 },
            .{ .x = 0, .y = 1 },
            .{ .x = far, .y = far },
        ),
    );
}

// ---------------------------------------------------------------------------
// The loader, in the configuration that has one.
// ---------------------------------------------------------------------------

test "a repeated request for the loaded provider succeeds and a different one is refused" {
    try support.ready();
    if (comptime !predicates.runtime_loaded) return error.SkipZigTest;

    const chosen = predicates.loadedSource().?;
    try testing.expect(chosen == .path);

    // Same request again: the provider already in use stays in use and the
    // call succeeds. This is what every test in this package relies on when it
    // establishes the precondition for itself.
    try predicates.load(chosen);
    try testing.expectEqual(chosen, predicates.loadedSource().?);

    // A different request is refused rather than silently honoured. The library
    // in use does not change.
    try testing.expectError(error.ProviderMismatch, predicates.load(.{ .path = "/nonexistent/libpredicates.so" }));
    try testing.expectEqual(chosen, predicates.loadedSource().?);

    // A request of the other kind is refused too. There is no path-to-system
    // fallback and no system-to-path fallback, so naming the library by
    // basename while a path is loaded is a different request rather than a
    // second spelling of the one in use.
    try testing.expectError(error.ProviderMismatch, predicates.load(.{ .system = "libpredicates.so" }));

    // And the library still works through both routes after all of that.
    try testing.expectEqual(
        predicates.Sign.positive,
        try predicates.orient2dSign(
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 0 },
            .{ .x = 0, .y = 1 },
        ),
    );
}