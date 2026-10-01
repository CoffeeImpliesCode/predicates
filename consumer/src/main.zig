//! Consumes the `predicates` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("predicates")` here. No path reaches into the
//! library's own tree, so if this builds and produces the answers below, the
//! module contract is real.
//!
//! The answers are worked out by hand and independent of the library, so a
//! mismatch is a real fault rather than a restatement of what the library just
//! did. Any mismatch exits non-zero.

const std = @import("std");
const predicates = @import("predicates");

pub fn main() !void {
    predicates.init();

    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // A triangle wound counterclockwise about the origin: the orientation
    // determinant is cross((a-c), (b-c)) = cross((-1,-1), (0,-1)) = 1.
    const o = predicates.Point2;
    const t = predicates.Point3;
    const a = o{ .x = 0, .y = 0 };
    const b = o{ .x = 1, .y = 0 };
    const c = o{ .x = 0, .y = 1 };
    try expect(w, "orient2d(counterclockwise)", predicates.Sign.positive, try predicates.orient2dSign(a, b, c));

    // The same three points with b and c exchanged: the determinant negates.
    try expect(w, "orient2d(clockwise)", predicates.Sign.negative, try predicates.orient2dSign(a, c, b));

    // Collinear, so the exact determinant is zero.
    try expect(w, "orient2d(collinear)", predicates.Sign.zero, try predicates.orient2dSign(
        o{ .x = 0, .y = 0 },
        o{ .x = 1, .y = 1 },
        o{ .x = 2, .y = 2 },
    ));

    // A tetrahedron with (0,0,0), (1,0,0), (0,1,0) as its base and the apex at
    // (0,0,-1) below it. The exact determinant is +1.
    try expect(w, "orient3d(apex below the base plane)", predicates.Sign.positive, try predicates.orient3dSign(
        t{ .x = 0, .y = 0, .z = 0 },
        t{ .x = 1, .y = 0, .z = 0 },
        t{ .x = 0, .y = 1, .z = 0 },
        t{ .x = 0, .y = 0, .z = -1 },
    ));

    // The origin is strictly inside the unit circle through (1,0), (0,1) and
    // (-1,0) when they are taken counterclockwise.
    try expect(w, "incircle(centre inside)", predicates.Sign.positive, try predicates.incircleSign(
        o{ .x = 1, .y = 0 },
        o{ .x = 0, .y = 1 },
        o{ .x = -1, .y = 0 },
        o{ .x = 0, .y = 0 },
    ));

    // The origin is strictly inside the circumsphere of the tetrahedron
    // (1,0,0) (0,1,0) (0,0,1) (-1,-1,-1), whose circumsphere has centre
    // (-1/4,-1/4,-1/4) and squared radius 27/16.
    try expect(w, "insphere(origin inside)", predicates.Sign.positive, try predicates.insphereSign(
        t{ .x = 1, .y = 0, .z = 0 },
        t{ .x = 0, .y = 1, .z = 0 },
        t{ .x = 0, .y = 0, .z = 1 },
        t{ .x = -1, .y = -1, .z = -1 },
        t{ .x = 0, .y = 0, .z = 0 },
    ));

    // The raw C escape hatch is part of the published surface too, and this is
    // where a dependent proves the archive it linked is the one the header
    // describes. Two_Sum is an error-free transformation, and 1 + 2^-53 is
    // exactly half way between 1.0 and the next double, so binary64 rounds it
    // to even and returns exactly 1.0: the bit is gone the moment plain
    // arithmetic touches it. Growing the one-component expansion [1.0] by
    // 2^-53 has to hand back the two-component expansion [2^-53, 1.0], which
    // still represents the value plain arithmetic cannot hold.
    const half_ulp = std.math.ldexp(@as(f64, 1.0), -53);
    var single = [1]f64{1.0};
    var expanded: [4]f64 = undefined;
    const length = predicates.c.grow_expansion_zeroelim(1, &single, half_ulp, &expanded);
    const naive = 1.0 + half_ulp;
    const recovered = length == 2 and expanded[0] == half_ulp and expanded[1] == 1.0;
    try w.print("c.grow_expansion_zeroelim  length {d} naive {s} recovered {s}\n", .{
        length,
        if (naive == 1.0) "1.0" else "other",
        if (recovered) "exact" else "inexact",
    });
    // If plain arithmetic had not lost the bit, this fixture would prove
    // nothing about the transformation.
    if (naive != 1.0) return error.ConsumerCheckFailed;
    if (!recovered) return error.ConsumerCheckFailed;

    try w.print("consumer ok\n", .{});
    try w.flush();
}

fn expect(
    w: *std.Io.Writer,
    what: []const u8,
    want: predicates.Sign,
    got: predicates.Sign,
) !void {
    const name = switch (want) {
        .negative => "negative",
        .zero => "zero",
        .positive => "positive",
    };
    try w.print("{s} = {s}\n", .{ what, name });
    if (got != want) {
        const got_name = switch (got) {
            .negative => "negative",
            .zero => "zero",
            .positive => "positive",
        };
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, name, got_name });
        return error.ConsumerCheckFailed;
    }
}
