// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored. `FORK-LICENSE.md` says what that identifier
// covers and on whose authority, and `NOTICE.md` carries the file inventory.

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
//!
//! In a runtime-loading build the provider is named on the command line
//! (`--provider <path>`) or in `PREDICATES_TEST_PROVIDER`, and the program says
//! which configuration it is in its first line. In a linked build neither is
//! needed and neither is read.

const std = @import("std");
const predicates = @import("predicates");

/// The environment variable naming the provider for a runtime-loading run.
const provider_env_var = "PREDICATES_TEST_PROVIDER";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    if (comptime predicates.runtime_loaded) {
        const provider = try providerRequest(init);
        try predicates.load(.{ .path = provider });
    }
    predicates.init();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const w = &stdout.interface;

    try w.print("predicates consumer ({s} C library)\n", .{
        if (predicates.runtime_loaded) "loaded" else "linked",
    });

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
    // where a dependent proves the library it reached is the one the header
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

    // The three implementations of the 2D orientation determinant have to agree
    // on an input where only exact arithmetic can decide. The exact determinant
    // of ((1+2^-52, 1), (1, 1-2^-52), (0,0)) is (1+2^-52)(1-2^-52) - 1, which
    // is -2^-104: negative, and about 2^-156 of the terms it comes from. Both
    // products round to 1.0 in binary64, so a filtered implementation sees zero
    // and only the exact ones can produce the sign.
    const bump = std.math.ldexp(@as(f64, 1.0), -52);
    const near = [2]f64{ 1 + bump, 1 };
    const near_b = [2]f64{ 1, 1 - bump };
    const origin = [2]f64{ 0, 0 };
    const variants = .{
        predicates.c.orient2dexact(&near, &near_b, &origin),
        predicates.c.orient2dslow(&near, &near_b, &origin),
        predicates.c.orient2d(&near, &near_b, &origin),
    };
    try w.print("orient2d one-ulp cancellation  exact {s} slow {s} adaptive {s}\n", .{
        labelOf(variants[0]),
        labelOf(variants[1]),
        labelOf(variants[2]),
    });
    // `inline` because the three entries are computed at run time: a runtime
    // `for` would index this tuple with a run-time index, and a tuple field
    // index has to be comptime-known. Unrolling keeps all three assertions
    // rather than dropping a row, which is what a runtime `for` would force.
    inline for (variants) |value| {
        if (!(value < 0.0)) return error.ConsumerCheckFailed;
    }

    // The fifteen file-scope constants, read through the typed accessors and
    // compared against what the initialization loop in `src/predicates.c:658-667`
    // produces for IEEE 754 binary64. This consumer re-derives them rather than
    // asking the library, so a provider that was never initialized, or that was
    // built for a narrower floating-point format, or that handed back a copy
    // rather than its own data, fails here instead of silently answering every
    // predicate wrongly.
    const measured = measure();
    try w.print("constants epsilon {d} splitter {d} resulterrbound {d}\n", .{
        predicates.epsilon(),
        predicates.splitter(),
        predicates.resultErrorBound(),
    });
    if (predicates.epsilon() != measured.epsilon) return error.ConsumerCheckFailed;
    if (predicates.splitter() != measured.splitter) return error.ConsumerCheckFailed;
    if (predicates.resultErrorBound() !=
        (3.0 + 8.0 * measured.epsilon) * measured.epsilon) return error.ConsumerCheckFailed;

    // And the raw route sees the same storage, so a dependent that needs the
    // constants can reach them without the typed layer.
    if (rawConstant("epsilon") != predicates.epsilon()) return error.ConsumerCheckFailed;
    if (rawConstant("isperrboundC") != predicates.insphereErrorBounds()[2]) {
        return error.ConsumerCheckFailed;
    }

    try w.print("consumer ok\n", .{});
    try w.flush();
}

/// What one `exactinit` run writes for the running floating-point format.
///
/// `src/predicates.c:649-667`, transcribed: halve `epsilon` until adding it to
/// one no longer moves one, double `splitter` on every other pass, then add one.
const Measured = struct { epsilon: f64, splitter: f64 };

fn measure() Measured {
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

/// One of the fifteen constants through the raw route.
///
/// In a runtime-loading build the dispatch publishes `NAMEAddr()` per data
/// symbol, and that accessor is what checks readiness and returns the address
/// the loader resolved inside the loaded image. A linked build has no accessor
/// and no table, and the linked library's own storage is the same object.
fn rawConstant(comptime name: []const u8) f64 {
    if (comptime predicates.runtime_loaded) return @field(predicates.c, name ++ "Addr")().*;
    return @field(predicates.c, name);
}

fn labelOf(v: f64) []const u8 {
    return if (v > 0.0) "positive" else if (v < 0.0) "negative" else "zero";
}

/// The same three names for a value the facade already reduced to a sign.
fn signLabel(s: predicates.Sign) []const u8 {
    return switch (s) {
        .negative => "negative",
        .zero => "zero",
        .positive => "positive",
    };
}

/// The provider this run should load, from `--provider <path>` or from
/// `PREDICATES_TEST_PROVIDER`.
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
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export {s} with a shared object exporting the forty functions and " ++
            "the fifteen globals of include/predicates.h. Nothing is loaded by " ++
            "default and no other file is tried.\n",
        .{provider_env_var},
    );
    return error.NoProviderConfigured;
}

fn expect(
    w: *std.Io.Writer,
    what: []const u8,
    want: predicates.Sign,
    got: predicates.Sign,
) !void {
    const name = signLabel(want);
    try w.print("{s} = {s}\n", .{ what, name });
    if (got != want) {
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, name, signLabel(got) });
        return error.ConsumerCheckFailed;
    }
}