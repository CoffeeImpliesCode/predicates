// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored. `FORK-LICENSE.md` says what that identifier
// covers and on whose authority, and `NOTICE.md` carries the file inventory.

//! A runnable, deterministic demonstration of the facade and of the raw
//! surface behind it.
//!
//! Every line below is a fixed input with a known exact answer, so the output
//! is reproducible on any host and a change in it is a change in behaviour
//! rather than in timing or in a random seed. `zig build smoke` runs this.
//!
//! Only signs are printed, with one exception. The unsuffixed predicates return
//! upstream's own adaptive determinant approximation, whose magnitude upstream
//! explicitly does not guarantee; printing it would suggest a precision the
//! library does not have. The fifteen file-scope constants are the other
//! thing printed, and those *are* exact - they are a function of the running
//! floating-point format and nothing else - so they are shown as their IEEE
//! 754 binary64 bit patterns rather than as rounded decimal, which is both
//! unambiguous and identical on every supported target.
//!
//! In a runtime-loading build the provider is named on the command line
//! (`--provider <path>`) or in `PREDICATES_TEST_PROVIDER`, and the program says
//! which configuration it is in the first two lines. In a linked build neither
//! is needed and neither is read.

const std = @import("std");
const predicates = @import("predicates");

/// Provenance of the C this binary was linked against, or loaded. Printed, not
/// asserted: the checksum belongs to a provenance gate, and a smoke run should
/// say which upstream it exercised rather than fail when the pin moves.
const upstream_revision = "1996-05-18";
const upstream_sha256 = "f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029";

/// The environment variable naming the provider for a runtime-loading run.
const provider_env_var = "PREDICATES_TEST_PROVIDER";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

fn label(s: predicates.Sign) []const u8 {
    return switch (s) {
        .negative => "negative",
        .zero => "zero",
        .positive => "positive",
    };
}

pub fn main(init: std.process.Init) !void {
    // The one explicit step a runtime-loading build needs before anything else
    // can run. In a linked build this is a comptime no-op and nothing is
    // loaded, because there is nothing to load.
    if (comptime predicates.runtime_loaded) {
        const provider = try providerRequest(init);
        try predicates.load(.{ .path = provider });
    }
    predicates.init();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const w = &stdout.interface;

    try w.print("predicates smoke\n", .{});
    try w.print("{s} C library, upstream {s} sha256 {s}\n", .{
        if (predicates.runtime_loaded) "loaded" else "linked",
        upstream_revision,
        upstream_sha256,
    });

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

    // The expansion arithmetic, through the raw route. Two_Sum is an
    // error-free transformation, and 1 + 2^-53 is exactly half way between 1.0
    // and the next double, so binary64 rounds it to even and plain arithmetic
    // cannot hold the bit at all. Growing the one-component expansion [1.0] by
    // 2^-53 has to hand back [2^-53, 1.0], which still represents the value.
    const half_ulp = std.math.ldexp(@as(f64, 1.0), -53);
    var single = [1]f64{1.0};
    var expanded: [4]f64 = undefined;
    const grown = predicates.c.grow_expansion_zeroelim(1, &single, half_ulp, &expanded);
    const naive = 1.0 + half_ulp;
    try w.print("c.grow_expansion_zeroelim  length {d} naive {s} components ", .{
        grown,
        if (naive == 1.0) "1.0" else "other",
    });
    var component: usize = 0;
    while (component < @min(@as(usize, @intCast(grown)), expanded.len)) : (component += 1) {
        try w.print("{x} ", .{@as(u64, @bitCast(expanded[component]))});
    }
    try w.print("\n", .{});

    // The fifteen file-scope constants, read out of the live image through the
    // typed accessors. One `exactinit` leaves `epsilon` at 2^-53, `splitter` at
    // 2^27 + 1, and the thirteen remaining values on the formulas in
    // `src/predicates.c:670-682`; the bit patterns below follow from those and
    // are identical on every target this package supports. A runtime-loading
    // build reads them out of the loaded provider's data segment and a linked
    // build out of the linked library's. What is printed is the storage, not a
    // copy, which is why the raw route reads the same numbers.
    try w.print("constants  epsilon {x} splitter {x} resulterrbound {x}\n", .{
        @as(u64, @bitCast(predicates.epsilon())),
        @as(u64, @bitCast(predicates.splitter())),
        @as(u64, @bitCast(predicates.resultErrorBound())),
    });
    const ccw = predicates.orientationErrorBounds();
    const o3d = predicates.orientation3dErrorBounds();
    const icc = predicates.incircleErrorBounds();
    const isp = predicates.insphereErrorBounds();
    try w.print("constants  ccw {x} {x} {x}\n", .{
        @as(u64, @bitCast(ccw[0])),
        @as(u64, @bitCast(ccw[1])),
        @as(u64, @bitCast(ccw[2])),
    });
    try w.print("constants  o3d {x} {x} {x}\n", .{
        @as(u64, @bitCast(o3d[0])),
        @as(u64, @bitCast(o3d[1])),
        @as(u64, @bitCast(o3d[2])),
    });
    try w.print("constants  icc {x} {x} {x}\n", .{
        @as(u64, @bitCast(icc[0])),
        @as(u64, @bitCast(icc[1])),
        @as(u64, @bitCast(icc[2])),
    });
    try w.print("constants  isp {x} {x} {x}\n", .{
        @as(u64, @bitCast(isp[0])),
        @as(u64, @bitCast(isp[1])),
        @as(u64, @bitCast(isp[2])),
    });

    try w.flush();
}

/// The provider this run should load, from `--provider <path>` or from
/// `PREDICATES_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location and does not
/// fall back to a linked copy: a runtime-loading build that was not told which
/// file to load says so, rather than loading something else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get(provider_env_var) orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export {s} with a shared object exporting the forty functions and " ++
            "the fifteen globals of include/predicates.h. Nothing is loaded by " ++
            "default and no other file is tried.\n",
        .{provider_env_var},
    );
    return error.NoProviderConfigured;
}

fn fastSign(v: f64) predicates.Sign {
    return if (v > 0.0) .positive else if (v < 0.0) .negative else .zero;
}
