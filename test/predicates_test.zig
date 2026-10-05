//! Behavioural tests for the Zig facade.
//!
//! Every sign claim is checked against `exact_oracle.zig`, which evaluates the
//! same determinant in exact integer arithmetic. Round trips through the C are
//! not evidence of anything here: the C is the thing under test, and the oracle
//! is the only independent witness in the file.
//!
//! What is deliberately NOT asserted is any magnitude. Upstream guarantees the
//! sign of `orient2d` and friends and explicitly does not guarantee the
//! magnitude, which is its own adaptive determinant approximation rather than
//! any scaled permanent. Asserting on it would pin an incidental detail of the
//! adaptive loop.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const predicates = @import("predicates");
const oracle = @import("exact_oracle.zig");
const support = @import("support.zig");

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

/// The oracle declares its own sign enum on purpose. Bridging through this
/// function means a facade result and an oracle result are compared as data,
/// not as two views of the same tagged value.
fn bridge(s: oracle.Sign) predicates.Sign {
    return switch (s) {
        .negative => .negative,
        .zero => .zero,
        .positive => .positive,
    };
}

/// Carries the case name into the assertion so a mismatch names the fixture.
/// `std.testing.expectEqual` in this Zig version takes no message argument, and
/// comparing the name alongside the sign puts it in the failure output.
const Report = struct {
    case: []const u8,
    sign: predicates.Sign,
};

fn checkOrient2d(name: []const u8, a: Point2, b: Point2, c: Point2) !void {
    var scratch = Scratch.init();
    defer scratch.deinit();
    const want = try oracle.orient2dSign(scratch.allocator(), a.x, a.y, b.x, b.y, c.x, c.y);
    try testing.expectEqual(
        Report{ .case = name, .sign = bridge(want) },
        Report{ .case = name, .sign = try predicates.orient2dSign(a, b, c) },
    );
}

fn checkOrient3d(name: []const u8, a: Point3, b: Point3, c: Point3, d: Point3) !void {
    var scratch = Scratch.init();
    defer scratch.deinit();
    const want = try oracle.orient3dSign(
        scratch.allocator(),
        a.x,
        a.y,
        a.z,
        b.x,
        b.y,
        b.z,
        c.x,
        c.y,
        c.z,
        d.x,
        d.y,
        d.z,
    );
    try testing.expectEqual(
        Report{ .case = name, .sign = bridge(want) },
        Report{ .case = name, .sign = try predicates.orient3dSign(a, b, c, d) },
    );
}

fn checkIncircle(name: []const u8, a: Point2, b: Point2, c: Point2, d: Point2) !void {
    var scratch = Scratch.init();
    defer scratch.deinit();
    const want = try oracle.incircleSign(scratch.allocator(), a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y);
    try testing.expectEqual(
        Report{ .case = name, .sign = bridge(want) },
        Report{ .case = name, .sign = try predicates.incircleSign(a, b, c, d) },
    );
}

fn checkInsphere(name: []const u8, a: Point3, b: Point3, c: Point3, d: Point3, e: Point3) !void {
    var scratch = Scratch.init();
    defer scratch.deinit();
    const want = try oracle.insphereSign(
        scratch.allocator(),
        a.x,
        a.y,
        a.z,
        b.x,
        b.y,
        b.z,
        c.x,
        c.y,
        c.z,
        d.x,
        d.y,
        d.z,
        e.x,
        e.y,
        e.z,
    );
    try testing.expectEqual(
        Report{ .case = name, .sign = bridge(want) },
        Report{ .case = name, .sign = try predicates.insphereSign(a, b, c, d, e) },
    );
}

/// Move a double by `n` units in the last place, by adding to its bit pattern.
/// Correct for any normal, non-zero value: the low mantissa bits are the ulp
/// grid, and the sign bit is far away from them.
fn ulpBump(v: f64, n: i64) f64 {
    const bits: u64 = @bitCast(v);
    const delta: u64 = @bitCast(n);
    return @bitCast(bits +% delta);
}

/// Nudge a point by `step` ulps of its first non-zero coordinate.
///
/// Zero has to be skipped. Its bit pattern is not on any ulp grid: adding a
/// small integer to it walks up through the exponent field and lands in
/// denormal, then in NaN, so a "one ulp from zero" perturbation would turn into
/// a non-finite coordinate and test the error contract instead of the filter.
fn nudgePoint2(p: Point2, step: i64) Point2 {
    if (p.x != 0.0) return .{ .x = ulpBump(p.x, step), .y = p.y };
    return .{ .x = p.x, .y = ulpBump(p.y, step) };
}

fn nudgePoint3(p: Point3, step: i64) Point3 {
    if (p.x != 0.0) return .{ .x = ulpBump(p.x, step), .y = p.y, .z = p.z };
    if (p.y != 0.0) return .{ .x = p.x, .y = ulpBump(p.y, step), .z = p.z };
    return .{ .x = p.x, .y = p.y, .z = ulpBump(p.z, step) };
}

// ---------------------------------------------------------------------------
// Initialization lifecycle.
// ---------------------------------------------------------------------------

test "init is idempotent and observable" {
    // Test order is not a contract, so this establishes the precondition
    // itself rather than assuming an earlier test ran.
    try support.ready();
    try testing.expect(predicates.isInitialized());
    predicates.init();
    predicates.init();
    try testing.expect(predicates.isInitialized());

    // Prove init actually reached the C. The constants exactinit computes are
    // not asserted here: they are an implementation detail of a 1996 file, and
    // a test that pins them breaks on every upstream refresh without ever
    // catching a real fault. What matters is the behaviour they enable.
    // `splitter` is the constant the Dekker split depends on; left at zero it
    // turns every adaptive routine into noise, and this fixture is one that
    // only exact arithmetic can decide. The exact determinant is
    // (1+2^-52)(1-2^-52) - 1 = -2^-104.
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    try testing.expectEqual(
        predicates.Sign.negative,
        try predicates.orient2dSign(
            .{ .x = 1 + bump, .y = 1 },
            .{ .x = 1, .y = 1 - bump },
            .{ .x = 0, .y = 0 },
        ),
    );
}

fn initWorker(done: *std.atomic.Value(usize)) void {
    predicates.init();
    _ = done.fetchAdd(1, .release);
}

/// Kept out of the test body so a target without threads never analyses it.
fn runConcurrentInits(count: usize) !void {
    var done = std.atomic.Value(usize).init(0);
    var threads: [8]std.Thread = undefined;
    var spawned: usize = 0;
    while (spawned < count) : (spawned += 1) {
        threads[spawned] = std.Thread.spawn(.{}, initWorker, .{&done}) catch |err| {
            for (threads[0..spawned]) |t| t.join();
            return err;
        };
    }
    for (threads[0..count]) |t| t.join();
    try testing.expectEqual(count, done.load(.acquire));
}

test "concurrent init does not race on the C globals" {
    // wasi has no threads; the helper above is never analysed for it.
    if (comptime builtin.os.tag == .wasi) return error.SkipZigTest;
    // The provider has to be in place before any worker thread calls
    // `exactinit` through it, and test order is not a contract.
    try support.ready();
    try runConcurrentInits(8);
    try testing.expect(predicates.isInitialized());
    try checkOrient2d(
        "after concurrent init",
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 0 },
        .{ .x = 0, .y = 1 },
    );
}

// ---------------------------------------------------------------------------
// Non-finite input contract.
// ---------------------------------------------------------------------------

test "every facade entry point rejects non-finite coordinates" {
    try support.ready();
    const nan = std.math.nan(f64);
    const inf = std.math.inf(f64);
    const p0: Point2 = .{ .x = 0, .y = 0 };
    const p1: Point2 = .{ .x = 1, .y = 0 };
    const bad2: Point2 = .{ .x = nan, .y = 0 };
    const q0: Point3 = .{ .x = 0, .y = 0, .z = 0 };
    const q1: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const bad3: Point3 = .{ .x = 0, .y = inf, .z = 0 };
    const NotFinite = predicates.Error.NonFiniteCoordinate;

    // orient2d family.
    try testing.expectError(NotFinite, predicates.orient2d(bad2, p1, p0));
    try testing.expectError(NotFinite, predicates.orient2dSign(p0, bad2, p1));
    try testing.expectError(NotFinite, predicates.orient2dfast(p0, p1, bad2));

    // orient3d family.
    try testing.expectError(NotFinite, predicates.orient3d(bad3, q1, q0, q0));
    try testing.expectError(NotFinite, predicates.orient3dSign(q0, q0, q1, bad3));
    try testing.expectError(NotFinite, predicates.orient3dfast(q0, bad3, q1, q0));

    // incircle family.
    try testing.expectError(NotFinite, predicates.incircle(bad2, p1, p0, p0));
    try testing.expectError(NotFinite, predicates.incircleSign(p0, p1, bad2, p0));
    try testing.expectError(NotFinite, predicates.incirclefast(p0, p1, p0, bad2));

    // insphere family.
    try testing.expectError(NotFinite, predicates.insphere(bad3, q1, q0, q0, q0));
    try testing.expectError(NotFinite, predicates.insphereSign(q0, q0, q1, bad3, q0));
    try testing.expectError(NotFinite, predicates.inspherefast(q0, q0, bad3, q1, q0));
}

test "infinities are refused even where a filter might survive them" {
    try support.ready();
    const huge: Point2 = .{ .x = std.math.inf(f64), .y = 0 };
    const also_huge: Point2 = .{ .x = 0, .y = std.math.inf(f64) };
    try testing.expectError(
        predicates.Error.NonFiniteCoordinate,
        predicates.orient2d(huge, also_huge, .{ .x = 1, .y = 1 }),
    );
}

// ---------------------------------------------------------------------------
// orient2d.
// ---------------------------------------------------------------------------

test "orient2d matches the exact oracle on ordinary inputs" {
    try support.ready();
    try checkOrient2d("counterclockwise unit triangle", .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 });
    try checkOrient2d("clockwise unit triangle", .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 });
    try checkOrient2d("counterclockwise, negative quadrant", .{ .x = -1, .y = -1 }, .{ .x = 1, .y = -1 }, .{ .x = -1, .y = 1 });
    // Small enough to be a stress case, large enough that the area itself is
    // a normal double.  A smaller triangle leaves the double range, where this
    // package guarantees no sign; see FORK-NOTES.md, "Extreme inputs are not
    // covered by upstream's guarantee", for why.
    try checkOrient2d("tiny triangle at the origin", .{ .x = 0, .y = 0 }, .{ .x = 2.0e-150, .y = 0 }, .{ .x = 0, .y = 2.0e-150 });
}

test "orient2d is exactly zero on degenerate input" {
    try support.ready();
    try checkOrient2d("collinear on the diagonal", .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 });
    try checkOrient2d("collinear on an axis", .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 5 }, .{ .x = 0, .y = -5 });
    try checkOrient2d("all three identical", .{ .x = 3, .y = -4 }, .{ .x = 3, .y = -4 }, .{ .x = 3, .y = -4 });
    try checkOrient2d("first two identical", .{ .x = 7, .y = 9 }, .{ .x = 7, .y = 9 }, .{ .x = -1, .y = 2 });
    try checkOrient2d("subnormal collinear", .{ .x = 0, .y = 0 }, .{ .x = std.math.floatTrueMin(f64), .y = 0 }, .{ .x = std.math.floatTrueMin(f64) * 2, .y = 0 });
}

test "orient2d matches the exact oracle over a wide coordinate range" {
    // Two hundred octaves apart, chosen so every product the filtered
    // expression forms stays inside the double range. Subnormal and
    // near-floatMax inputs are excluded on purpose; see FORK-NOTES.md,
    // "Extreme inputs are not covered by upstream's guarantee", for why.
    try support.ready();
    const small = std.math.ldexp(@as(f64, 1.0), -400);
    const large = std.math.ldexp(@as(f64, 1.0), 400);
    try checkOrient2d(
        "coordinates 800 octaves apart",
        .{ .x = small, .y = large },
        .{ .x = large, .y = small },
        .{ .x = 0, .y = 0 },
    );
    try checkOrient2d(
        "wide range, determinant at the scale limit",
        .{ .x = small, .y = 0 },
        .{ .x = 0, .y = large },
        .{ .x = 2 * small, .y = 0 },
    );
}

test "orient2d survives ulp-scale perturbations of near-degenerate triangles" {
    try support.ready();
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const bases = [_][3]Point2{
        // A hair off the line through (1,1).
        .{ .{ .x = 1, .y = 1 }, .{ .x = 1 + bump, .y = 1 }, .{ .x = 1, .y = 1 + 2 * bump } },
        // Exactly collinear, so every ulp decides the answer.
        .{ .{ .x = 0.5, .y = 0.5 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 } },
        // Widely separated magnitudes, which is where the filter is weakest.
        .{ .{ .x = 1e-30, .y = 1e30 }, .{ .x = 1e30, .y = 1e-30 }, .{ .x = 1, .y = 1 } },
    };
    for (bases) |base| {
        var which: usize = 0;
        while (which < base.len) : (which += 1) {
            var step: i64 = -4;
            while (step <= 4) : (step += 1) {
                var nudged = base;
                nudged[which] = nudgePoint2(base[which], step);
                var name_buf: [96]u8 = undefined;
                const name = try std.fmt.bufPrint(
                    &name_buf,
                    "point {d} x {d} ulp",
                    .{ which, step },
                );
                try checkOrient2d(name, nudged[0], nudged[1], nudged[2]);
            }
        }
    }
}

test "orient2dfast loses the sign where orient2d does not" {
    try support.ready();
    // The exact determinant is (1+2^-52)(1-2^-52) - 1 = -2^-104, which is
    // about 2^-156 of the size of the terms it is made from. Both products
    // round to 1.0 in binary64, so the fast path returns zero.
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const a: Point2 = .{ .x = 1 + bump, .y = 1 };
    const b: Point2 = .{ .x = 1, .y = 1 - bump };
    const c: Point2 = .{ .x = 0, .y = 0 };

    try testing.expectEqual(predicates.Sign.negative, try predicates.orient2dSign(a, b, c));
    try testing.expectEqual(0.0, try predicates.orient2dfast(a, b, c));
}

// ---------------------------------------------------------------------------
// orient3d.
// ---------------------------------------------------------------------------

test "orient3d matches the exact oracle on ordinary inputs" {
    try support.ready();
    try checkOrient3d(
        "apex above the xy plane",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
    );
    try checkOrient3d(
        "apex below the xy plane",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = -1 },
    );
    try checkOrient3d(
        "sliver tetrahedron",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 1e-13, .y = 1e-13, .z = -1 },
    );
}

test "orient3d is exactly zero on degenerate input" {
    try support.ready();
    try checkOrient3d(
        "all four coplanar in z = 0",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 1, .y = 1, .z = 0 },
    );
    try checkOrient3d(
        "apex coincident with a base vertex",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 0 },
    );
    try checkOrient3d(
        "base points collinear",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 1, .z = 0 },
        .{ .x = 2, .y = 2, .z = 0 },
        .{ .x = 0, .y = 0, .z = 9 },
    );
}

test "orient3d matches the exact oracle over a wide coordinate range" {
    // Three hundred octaves apart. See the orient2d note above on why the
    // extreme ends of the double range are not used here.
    try support.ready();
    const small = std.math.ldexp(@as(f64, 1.0), -300);
    const large = std.math.ldexp(@as(f64, 1.0), 300);
    try checkOrient3d(
        "coordinates 600 octaves apart",
        .{ .x = small, .y = large, .z = small },
        .{ .x = large, .y = small, .z = large },
        .{ .x = 1, .y = 1, .z = 1 },
        .{ .x = 0, .y = 0, .z = 0 },
    );
    try checkOrient3d(
        "wide range with an exact zero",
        .{ .x = small, .y = 0, .z = 0 },
        .{ .x = large, .y = 0, .z = 0 },
        .{ .x = 0, .y = large, .z = 0 },
        .{ .x = -small, .y = large, .z = 0 },
    );
}

test "orient3d survives ulp-scale perturbations of a nearly flat tetrahedron" {
    try support.ready();
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const base = [4]Point3{
        .{ .x = 1, .y = 1, .z = 1 },
        .{ .x = 1, .y = 1 + bump, .z = 1 },
        .{ .x = 1 + bump, .y = 1, .z = 1 },
        .{ .x = 1, .y = 1, .z = 1 + 4 * bump },
    };
    var which: usize = 0;
    while (which < base.len) : (which += 1) {
        var step: i64 = -4;
        while (step <= 4) : (step += 1) {
            var nudged = base;
            nudged[which] = nudgePoint3(base[which], step);
            var name_buf: [64]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "point {d} z {d} ulp", .{ which, step });
            try checkOrient3d(name, nudged[0], nudged[1], nudged[2], nudged[3]);
        }
    }
}

// ---------------------------------------------------------------------------
// incircle.
// ---------------------------------------------------------------------------

test "incircle matches the exact oracle on ordinary inputs" {
    try support.ready();
    try checkIncircle("origin inside the unit circle", .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 0 });
    try checkIncircle("far point outside the unit circle", .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 7, .y = -3 });
    try checkIncircle("reversed orientation puts the origin outside", .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 });
}

test "incircle is exactly zero on degenerate input" {
    try support.ready();
    try checkIncircle("fourth point on the same circle", .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = -1 });
    try checkIncircle("fourth point repeats a defining point", .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 1, .y = 0 });
    try checkIncircle("defining points collinear", .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = 3, .y = 3 });
    try checkIncircle("unit square, fourth corner", .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 });
}

test "incircle matches the exact oracle over a wide coordinate range" {
    // Two hundred octaves apart. See the orient2d note above on why the
    // extreme ends of the double range are not used here.
    try support.ready();
    const small = std.math.ldexp(@as(f64, 1.0), -200);
    const large = std.math.ldexp(@as(f64, 1.0), 200);
    try checkIncircle(
        "coordinates 400 octaves apart",
        .{ .x = small, .y = large },
        .{ .x = large, .y = -small },
        .{ .x = -small, .y = -large },
        .{ .x = 0, .y = 0 },
    );
    try checkIncircle(
        "four points on a circle of radius 2^200",
        .{ .x = large, .y = 0 },
        .{ .x = 0, .y = large },
        .{ .x = -large, .y = 0 },
        .{ .x = 0, .y = -large },
    );
}

test "incircle survives ulp-scale perturbations of a near-cocircular quadruple" {
    try support.ready();
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const base = [4]Point2{
        .{ .x = 1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = -1, .y = 0 },
        // Exactly on the circle; every ulp flips the answer.
        .{ .x = 0, .y = -1 },
    };
    var which: usize = 0;
    while (which < base.len) : (which += 1) {
        var step: i64 = -4;
        while (step <= 4) : (step += 1) {
            var nudged = base;
            nudged[which] = nudgePoint2(base[which], step);
            var name_buf: [64]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "point {d} y {d} ulp", .{ which, step });
            try checkIncircle(name, nudged[0], nudged[1], nudged[2], nudged[3]);
        }
    }
    // A test point one ulp outside the circle, where the filter cannot decide
    // from the magnitude alone and has to fall through to exact arithmetic.
    var off_circle = [4]Point2{
        .{ .x = 1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = -(1 + bump) },
    };
    off_circle[3] = nudgePoint2(off_circle[3], -1);
    try checkIncircle("test point one ulp outside the circle", off_circle[0], off_circle[1], off_circle[2], off_circle[3]);
}

// ---------------------------------------------------------------------------
// insphere.
// ---------------------------------------------------------------------------

test "insphere matches the exact oracle on ordinary inputs" {
    try support.ready();
    const a: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const b: Point3 = .{ .x = 0, .y = 1, .z = 0 };
    const c: Point3 = .{ .x = 0, .y = 0, .z = 1 };
    const d: Point3 = .{ .x = -1, .y = -1, .z = -1 };
    try checkInsphere("origin inside the circumsphere", a, b, c, d, .{ .x = 0, .y = 0, .z = 0 });
    try checkInsphere("far point outside the circumsphere", a, b, c, d, .{ .x = 5, .y = 5, .z = 5 });
    try checkInsphere("near point outside the circumsphere", a, b, c, d, .{ .x = -2, .y = -2, .z = -2 });
}

test "insphere is exactly zero on degenerate input" {
    try support.ready();
    const a: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const b: Point3 = .{ .x = 0, .y = 1, .z = 0 };
    const c: Point3 = .{ .x = 0, .y = 0, .z = 1 };
    const d: Point3 = .{ .x = -1, .y = -1, .z = -1 };
    // (1/2,1/2,1/2) lies exactly on the circumsphere of this tetrahedron, whose
    // centre is (-1/4,-1/4,-1/4) and whose squared radius is 27/16.
    try checkInsphere("fifth point exactly on the sphere", a, b, c, d, .{ .x = 0.5, .y = 0.5, .z = 0.5 });
    try checkInsphere("fifth point repeats a defining point", a, b, c, d, a);
    // Four coplanar points span no sphere at all.
    const e0: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const e1: Point3 = .{ .x = 0, .y = 1, .z = 0 };
    const e2: Point3 = .{ .x = -1, .y = 0, .z = 0 };
    const e3: Point3 = .{ .x = 0, .y = -1, .z = 0 };
    try checkInsphere("four coplanar defining points", e0, e1, e2, e3, .{ .x = 0, .y = 0, .z = 3 });
    // Three collinear defining points span no sphere either.
    try checkInsphere(
        "three collinear defining points",
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 1, .z = 1 },
        .{ .x = 2, .y = 2, .z = 2 },
        .{ .x = 3, .y = 3, .z = 3 },
        .{ .x = 0, .y = 0, .z = 9 },
    );
}

test "insphere matches the exact oracle over a wide coordinate range" {
    // One hundred octaves apart, which keeps every intermediate the
    // filtered expression forms inside the double range. See the orient2d
    // note above on why the extreme ends are not used here.
    try support.ready();
    const small = std.math.ldexp(@as(f64, 1.0), -100);
    const large = std.math.ldexp(@as(f64, 1.0), 100);
    try checkInsphere(
        "coordinates 200 octaves apart",
        .{ .x = small, .y = large, .z = small },
        .{ .x = large, .y = -small, .z = large },
        .{ .x = -small, .y = -large, .z = small },
        .{ .x = large, .y = large, .z = -large },
        .{ .x = 0, .y = 0, .z = 0 },
    );
    try checkInsphere(
        "wide range with a tiny fifth point",
        .{ .x = large, .y = 0, .z = 0 },
        .{ .x = 0, .y = large, .z = 0 },
        .{ .x = 0, .y = 0, .z = large },
        .{ .x = -large, .y = -large, .z = -large },
        .{ .x = small / 2, .y = small / 2, .z = small / 2 },
    );
}

test "insphere survives ulp-scale perturbations of a near-cospherical quintuple" {
    try support.ready();
    const base = [5]Point3{
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = -1, .y = -1, .z = -1 },
        // Exactly on the circumsphere.
        .{ .x = 0.5, .y = 0.5, .z = 0.5 },
    };
    var which: usize = 0;
    while (which < base.len) : (which += 1) {
        var step: i64 = -4;
        while (step <= 4) : (step += 1) {
            var nudged = base;
            nudged[which] = nudgePoint3(base[which], step);
            var name_buf: [64]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "point {d} x {d} ulp", .{ which, step });
            try checkInsphere(name, nudged[0], nudged[1], nudged[2], nudged[3], nudged[4]);
        }
    }
}

// ---------------------------------------------------------------------------
// Sign conventions that a caller can rely on.
// ---------------------------------------------------------------------------

test "the documented sign conventions hold on the canonical fixtures" {
    try support.ready();

    // orient2d: rotating the argument cycle keeps the sign, swapping two
    // arguments flips it. The determinant is alternating, so this is a property
    // of the mathematics, not of the adaptive loop.
    const a: Point2 = .{ .x = 0.3, .y = 0.7 };
    const b: Point2 = .{ .x = 5.5, .y = -2.25 };
    const c: Point2 = .{ .x = -1.5, .y = 4.75 };
    const base = try predicates.orient2dSign(a, b, c);
    // The known answer the symmetry is then applied to. Relative to c the two
    // difference vectors are (1.8, -4.05) and (7, -7), and the determinant is
    // 1.8*(-7) - (-4.05)*7 = 15.75, which is nowhere near zero, so the sign is
    // settled by the arithmetic and not by any ulp. Without it the equalities
    // below would also hold for a routine that answered zero every time.
    try testing.expectEqual(predicates.Sign.positive, base);
    try testing.expectEqual(base, try predicates.orient2dSign(b, c, a));
    try testing.expectEqual(base, try predicates.orient2dSign(c, a, b));
    try testing.expectEqual(base.negate(), try predicates.orient2dSign(b, a, c));
    try testing.expectEqual(base.negate(), try predicates.orient2dSign(c, b, a));

    // A zero result is stable under the same transformations.
    try testing.expectEqual(
        predicates.Sign.zero,
        try predicates.orient2dSign(a, b, b),
    );
}

fn signOf(v: f64) predicates.Sign {
    return if (v > 0.0) .positive else if (v < 0.0) .negative else .zero;
}

test "the fast paths agree with the robust ones on well-conditioned input" {
    try support.ready();

    // The control for the case where they provably do not. Upstream promises
    // nothing about the *fast routines; on this input the filter is exact, so
    // they must match, and the test is what keeps that true.
    const p0: Point2 = .{ .x = 0, .y = 0 };
    const p1: Point2 = .{ .x = 1, .y = 0 };
    const p2: Point2 = .{ .x = 0, .y = 1 };
    const p3: Point2 = .{ .x = -1, .y = 0 };

    try testing.expectEqual(
        try predicates.orient2dSign(p0, p1, p2),
        signOf(try predicates.orient2dfast(p0, p1, p2)),
    );

    const q0: Point3 = .{ .x = 0, .y = 0, .z = 0 };
    const q1: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const q2: Point3 = .{ .x = 0, .y = 1, .z = 0 };
    const q3: Point3 = .{ .x = 0, .y = 0, .z = 1 };

    try testing.expectEqual(
        try predicates.orient3dSign(q0, q1, q2, q3),
        signOf(try predicates.orient3dfast(q0, q1, q2, q3)),
    );
    try testing.expectEqual(
        try predicates.incircleSign(p1, p2, p3, p0),
        signOf(try predicates.incirclefast(p1, p2, p3, p0)),
    );

    const s1: Point3 = .{ .x = 1, .y = 0, .z = 0 };
    const s2: Point3 = .{ .x = 0, .y = 1, .z = 0 };
    const s3: Point3 = .{ .x = 0, .y = 0, .z = 1 };
    const s4: Point3 = .{ .x = -1, .y = -1, .z = -1 };

    try testing.expectEqual(
        try predicates.insphereSign(s1, s2, s3, s4, q0),
        signOf(try predicates.inspherefast(s1, s2, s3, s4, q0)),
    );
}
