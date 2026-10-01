//! A runnable, deterministic demonstration of the facade.
//!
//! Every line below is a fixed input with a known exact answer, so the output
//! is reproducible on any host and a change in it is a change in behaviour
//! rather than in timing or in a random seed. `zig build smoke` runs this.
//!
//! Only signs are printed. The magnitude a robust predicate returns is a scaled
//! approximation of the permanent, which upstream explicitly does not
//! guarantee; printing it would suggest a precision the library does not have.

const std = @import("std");
const predicates = @import("predicates");

/// Provenance of the C this binary was linked against. Printed, not asserted:
/// the checksum belongs to a provenance gate, and a smoke run should say which
/// upstream it exercised rather than fail when the pin moves.
const upstream_revision = "1996-05-18";
const upstream_sha256 = "f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029";

fn label(s: predicates.Sign) []const u8 {
    return switch (s) {
        .negative => "negative",
        .zero => "zero",
        .positive => "positive",
    };
}

pub fn main() !void {
    predicates.init();

    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("predicates smoke\n", .{});
    try w.print("upstream {s} sha256 {s}\n", .{ upstream_revision, upstream_sha256 });

    // orient2d: positive is counterclockwise.
    const o = predicates.Point2;
    try w.print("orient2d  unit triangle, counterclockwise {s}\n", .{
        label(try predicates.orient2dSign(
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 0 },
            .{ .x = 0, .y = 1 },
        )),
    });
    try w.print("orient2d  unit triangle, clockwise         {s}\n", .{
        label(try predicates.orient2dSign(
            .{ .x = 1, .y = 0 },
            .{ .x = 0, .y = 0 },
            .{ .x = 0, .y = 1 },
        )),
    });
    try w.print("orient2d  three points on a line           {s}\n", .{
        label(try predicates.orient2dSign(
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            .{ .x = 2, .y = 2 },
        )),
    });

    // The case that separates the robust routine from the fast one. The exact
    // determinant is (1+2^-52)(1-2^-52) - 1 = -2^-104; both products round to
    // 1.0 in binary64, so the non-robust path returns zero and the adaptive one
    // returns the right sign.
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const a = o{ .x = 1 + bump, .y = 1 };
    const b = o{ .x = 1, .y = 1 - bump };
    const origin = o{ .x = 0, .y = 0 };
    try w.print("orient2d  one-ulp cancellation, robust     {s}\n", .{
        label(try predicates.orient2dSign(a, b, origin)),
    });
    try w.print("orient2d  one-ulp cancellation, fast       {s}\n", .{
        label(fastSign(try predicates.orient2dfast(a, b, origin))),
    });

    // orient3d: positive means the fourth point is below the plane.
    const t = predicates.Point3;
    const p0 = t{ .x = 0, .y = 0, .z = 0 };
    const p1 = t{ .x = 1, .y = 0, .z = 0 };
    const p2 = t{ .x = 0, .y = 1, .z = 0 };
    try w.print("orient3d  apex above the xy plane          {s}\n", .{
        label(try predicates.orient3dSign(p0, p1, p2, .{ .x = 0, .y = 0, .z = 1 })),
    });
    try w.print("orient3d  apex below the xy plane          {s}\n", .{
        label(try predicates.orient3dSign(p0, p1, p2, .{ .x = 0, .y = 0, .z = -1 })),
    });
    try w.print("orient3d  four coplanar points             {s}\n", .{
        label(try predicates.orient3dSign(p0, p1, p2, .{ .x = 1, .y = 1, .z = 0 })),
    });

    // incircle: positive means the fourth point is inside.
    const r0 = o{ .x = 1, .y = 0 };
    const r1 = o{ .x = 0, .y = 1 };
    const r2 = o{ .x = -1, .y = 0 };
    try w.print("incircle  centre of the unit circle        {s}\n", .{
        label(try predicates.incircleSign(r0, r1, r2, origin)),
    });
    try w.print("incircle  far outside the unit circle      {s}\n", .{
        label(try predicates.incircleSign(r0, r1, r2, .{ .x = 7, .y = -3 })),
    });
    try w.print("incircle  reversed orientation             {s}\n", .{
        label(try predicates.incircleSign(r2, r1, r0, origin)),
    });
    try w.print("incircle  fourth point on the circle       {s}\n", .{
        label(try predicates.incircleSign(r0, r1, r2, .{ .x = 0, .y = -1 })),
    });

    // insphere: positive means the fifth point is inside the circumsphere of a
    // tetrahedron whose circumsphere has centre (-1/4,-1/4,-1/4) and squared
    // radius 27/16.
    const s0 = t{ .x = 1, .y = 0, .z = 0 };
    const s1 = t{ .x = 0, .y = 1, .z = 0 };
    const s2 = t{ .x = 0, .y = 0, .z = 1 };
    const s3 = t{ .x = -1, .y = -1, .z = -1 };
    try w.print("insphere  origin inside the circumsphere   {s}\n", .{
        label(try predicates.insphereSign(s0, s1, s2, s3, p0)),
    });
    try w.print("insphere  far outside the circumsphere     {s}\n", .{
        label(try predicates.insphereSign(s0, s1, s2, s3, .{ .x = 5, .y = 5, .z = 5 })),
    });
    try w.print("insphere  fifth point on the sphere       {s}\n", .{
        label(try predicates.insphereSign(s0, s1, s2, s3, .{ .x = 0.5, .y = 0.5, .z = 0.5 })),
    });

    // The input contract upstream has no answer for.
    const nan_point = o{ .x = std.math.nan(f64), .y = 0 };
    const rejected = blk: {
        if (predicates.orient2d(nan_point, r0, r1)) |_| {
            break :blk "no error";
        } else |err| {
            break :blk @errorName(err);
        }
    };
    try w.print("orient2d  NaN coordinate refused with      {s}\n", .{rejected});

    try w.flush();
}

fn fastSign(v: f64) predicates.Sign {
    return if (v > 0.0) .positive else if (v < 0.0) .negative else .zero;
}
