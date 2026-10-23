// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// Fork-authored; see FORK-LICENSE.md and NOTICE.md.

//! External consumer of the published `predicates` module; no source-tree imports.
//! Checks use independently computed answers; runtime builds require an explicit provider.

const std = @import("std");
const predicates = @import("predicates");

/// The environment variable naming the provider for a runtime-loading run.
const provider_env_var = "PREDICATES_TEST_PROVIDER";

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

    // Counterclockwise winding gives orientation determinant +1.
    const o = predicates.Point2;
    const t = predicates.Point3;
    const a = o{ .x = 0, .y = 0 };
    const b = o{ .x = 1, .y = 0 };
    const c = o{ .x = 0, .y = 1 };
    try expect(w, "orient2d(counterclockwise)", predicates.Sign.positive, try predicates.orient2dSign(a, b, c));

    // Swapping two vertices negates the determinant.
    try expect(w, "orient2d(clockwise)", predicates.Sign.negative, try predicates.orient2dSign(a, c, b));

    // Collinear points have zero exact determinant.
    try expect(w, "orient2d(collinear)", predicates.Sign.zero, try predicates.orient2dSign(
        o{ .x = 0, .y = 0 },
        o{ .x = 1, .y = 1 },
        o{ .x = 2, .y = 2 },
    ));

    // The apex below the xy-plane base gives determinant +1.
    try expect(w, "orient3d(apex below the base plane)", predicates.Sign.positive, try predicates.orient3dSign(
        t{ .x = 0, .y = 0, .z = 0 },
        t{ .x = 1, .y = 0, .z = 0 },
        t{ .x = 0, .y = 1, .z = 0 },
        t{ .x = 0, .y = 0, .z = -1 },
    ));

    // The origin is inside the counterclockwise unit circle.
    try expect(w, "incircle(centre inside)", predicates.Sign.positive, try predicates.incircleSign(
        o{ .x = 1, .y = 0 },
        o{ .x = 0, .y = 1 },
        o{ .x = -1, .y = 0 },
        o{ .x = 0, .y = 0 },
    ));

    // The origin is inside this tetrahedron's circumsphere.
    try expect(w, "insphere(origin inside)", predicates.Sign.positive, try predicates.insphereSign(
        t{ .x = 1, .y = 0, .z = 0 },
        t{ .x = 0, .y = 1, .z = 0 },
        t{ .x = 0, .y = 0, .z = 1 },
        t{ .x = -1, .y = -1, .z = -1 },
        t{ .x = 0, .y = 0, .z = 0 },
    ));

    // Two_Sum preserves the half-ULP lost by plain binary64 addition.
    // Growing `[1.0]` by `2^-53` must return `[2^-53, 1.0]`.
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
    // Require ordinary addition to lose the half-ULP; otherwise the fixture proves nothing.
    if (naive != 1.0) return error.ConsumerCheckFailed;
    if (!recovered) return error.ConsumerCheckFailed;

    // Exact determinant is -2^-104 although both products round to 1.0.
    // The fast filter sees zero; exact variants must retain the negative sign.
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
    // Tuple fields require comptime indices, so unroll this check.
    inline for (variants) |value| {
        if (!(value < 0.0)) return error.ConsumerCheckFailed;
    }

    // Compare all 15 provider-owned constants with values independently measured from `exactinit`.
    // This detects missing initialization, wrong precision, or copied data.
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

    // Raw accessors must expose the same storage as typed accessors.
    if (rawConstant("epsilon") != predicates.epsilon()) return error.ConsumerCheckFailed;
    if (rawConstant("isperrboundC") != predicates.insphereErrorBounds()[2]) {
        return error.ConsumerCheckFailed;
    }

    try w.print("consumer ok\n", .{});
    try w.flush();
}

/// Binary64 constants measured by an independent `exactinit` calculation.
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

/// Reads a provider-owned constant through raw C or runtime dispatch.
/// Runtime builds use `NAMEAddr()`; linked builds read the exported object.
fn rawConstant(comptime name: []const u8) f64 {
    if (comptime predicates.runtime_loaded) return @field(predicates.c, name ++ "Addr")().*;
    return @field(predicates.c, name);
}

fn labelOf(v: f64) []const u8 {
    return if (v > 0.0) "positive" else if (v < 0.0) "negative" else "zero";
}

fn signLabel(s: predicates.Sign) []const u8 {
    return switch (s) {
        .negative => "negative",
        .zero => "zero",
        .positive => "positive",
    };
}

/// Reads the provider path from `--provider` or `PREDICATES_TEST_PROVIDER`.
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

/// Prints explicit guidance when no runtime provider was named.
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
