//! Tests for the expansion arithmetic reached through `predicates.c`.
//!
//! These routines are the substrate the four predicates are built out of, and
//! they are part of the published API, so they are tested directly rather than
//! only through the predicates that use them.
//!
//! An expansion here is a nonoverlapping, increasing sequence of doubles whose
//! exact sum is a dyadic rational. Two facts make the assertions below
//! checkable without a reference implementation:
//!
//!   * Summing the components from smallest to largest rounds back to the
//!     correctly rounded value of the exact sum. That is a theorem about
//!     nonoverlapping expansions, not about this code, so a round trip through
//!     a routine has to come back.
//!   * A routine that promises zero elimination must return an expansion with no
//!     zero components and minimal length; a routine that does not must return
//!     the same value.
//!
//! Nothing here asserts a particular length beyond what the contract requires,
//! because the length is an implementation choice of the adaptive loop.

const std = @import("std");
const testing = std.testing;

const c = @import("predicates").c;
const support = @import("support.zig");

/// Sum an expansion the way `estimate` does: from smallest to largest. For a
/// nonoverlapping expansion this is the correctly rounded value of the exact
/// sum, so it is the value any consumer will read back.
fn sumOf(expansion: []const f64) f64 {
    var total: f64 = 0.0;
    for (expansion) |component| total += component;
    return total;
}

fn expectNoZeros(expansion: []const f64) !void {
    for (expansion, 0..) |component, index| {
        if (component == 0.0) {
            std.debug.print("zero component at index {d} of {d}\n", .{ index, expansion.len });
            return error.UnexpectedZeroComponent;
        }
    }
}

test "expansion sums round-trip through every addition routine" {
    try support.ready();
    const a = 1.0;
    const b = std.math.ldexp(@as(f64, 1.0), -60);
    const expected = a + b;

    var one_a = [1]f64{a};
    var one_b = [1]f64{b};
    var out: [8]f64 = undefined;

    const fast_len: usize = @intCast(c.fast_expansion_sum_zeroelim(1, &one_a, 1, &one_b, &out));
    try testing.expectEqual(2, fast_len);
    try testing.expectEqual(expected, sumOf(out[0..fast_len]));
    try expectNoZeros(out[0..fast_len]);

    const fast_keep_len: usize = @intCast(c.fast_expansion_sum(1, &one_a, 1, &one_b, &out));
    try testing.expectEqual(2, fast_keep_len);
    try testing.expectEqual(expected, sumOf(out[0..fast_keep_len]));

    const sum1_len: usize = @intCast(c.expansion_sum_zeroelim1(1, &one_a, 1, &one_b, &out));
    try testing.expectEqual(expected, sumOf(out[0..sum1_len]));
    try expectNoZeros(out[0..sum1_len]);

    const sum2_len: usize = @intCast(c.expansion_sum_zeroelim2(1, &one_a, 1, &one_b, &out));
    try testing.expectEqual(expected, sumOf(out[0..sum2_len]));
    try expectNoZeros(out[0..sum2_len]);

    const sum_keep_len: usize = @intCast(c.expansion_sum(1, &one_a, 1, &one_b, &out));
    try testing.expectEqual(expected, sumOf(out[0..sum_keep_len]));
}

test "grow_expansion adds a scalar and keeps the expansion nonoverlapping" {
    try support.ready();
    var base = [1]f64{1.0};
    var out: [8]f64 = undefined;

    // 1.0 + 2^-52 is itself a double, so the error term of the Two_Sum is
    // exactly zero and zero elimination collapses the result to one component.
    const grown: usize = @intCast(c.grow_expansion_zeroelim(1, &base, std.math.ldexp(@as(f64, 1.0), -52), &out));
    try testing.expectEqual(1, grown);
    try testing.expectEqual(1.0 + std.math.ldexp(@as(f64, 1.0), -52), sumOf(out[0..grown]));
    try expectNoZeros(out[0..grown]);

    // Without zero elimination the result may carry a zero component, but the
    // value is still the same.
    const grown_keep: usize = @intCast(c.grow_expansion(1, &base, std.math.ldexp(@as(f64, 1.0), -52), &out));
    try testing.expectEqual(1.0 + std.math.ldexp(@as(f64, 1.0), -52), sumOf(out[0..grown_keep]));

    // Growing an expansion by zero must not lose a component.
    var two = [2]f64{ std.math.ldexp(@as(f64, 1.0), -60), 1.0 };
    const unchanged: usize = @intCast(c.grow_expansion_zeroelim(2, &two, 0.0, &out));
    try testing.expectEqual(2, unchanged);
    try testing.expectEqual(1.0, sumOf(out[0..unchanged]));
}

test "scale_expansion multiplies by a scalar" {
    try support.ready();
    var two = [2]f64{ std.math.ldexp(@as(f64, 1.0), -60), 1.0 };
    var out: [8]f64 = undefined;

    const scaled_len: usize = @intCast(c.scale_expansion_zeroelim(2, &two, 2.0, &out));
    try testing.expectEqual(2, scaled_len);
    try testing.expectEqual(2.0, sumOf(out[0..scaled_len]));
    try expectNoZeros(out[0..scaled_len]);

    const scaled_keep: usize = @intCast(c.scale_expansion(2, &two, 0.5, &out));
    try testing.expectEqual(0.5, sumOf(out[0..scaled_keep]));

    // Scaling by zero collapses the expansion but must report a usable length.
    const zeroed: usize = @intCast(c.scale_expansion_zeroelim(2, &two, 0.0, &out));
    try testing.expectEqual(1, zeroed);
    try testing.expectEqual(0.0, sumOf(out[0..zeroed]));
}

test "linear_expansion_sum adds nonoverlapping expansions" {
    try support.ready();
    // The precondition of `linear_expansion_sum` is that the two magnitude
    // ranges do not overlap, so every component of `f` is below every
    // component of `e`.  Interleaving them (as 2^-61, 0.5 against
    // 2^-60, 1.0 does) violates that and is not a linear sum at all.
    var e = [2]f64{ 0.25, 1.0 };
    var f = [2]f64{ 0.03125, 0.0625 };
    var out: [16]f64 = undefined;

    // The linear sum is a speed optimisation, not a length promise: for
    // two mutually nonoverlapping expansions the exact result often needs
    // far fewer components than the two inputs together.  Here 0.25 + 1.0
    // plus 0.03125 + 0.0625 is exactly 1.34375, so one component is the
    // whole answer and the routine is right to say so.
    const len: usize = @intCast(c.linear_expansion_sum_zeroelim(2, &e, 2, &f, &out));
    try testing.expectEqual(1, len);
    try testing.expectEqual(1.34375, sumOf(out[0..len]));

    const keep_len: usize = @intCast(c.linear_expansion_sum(2, &e, 2, &f, &out));
    try testing.expectEqual(1.34375, sumOf(out[0..keep_len]));
}

test "compress removes interspersed zero components" {
    try support.ready();
    // A hand-built expansion with an interspersed zero. Upstream only promises
    // that compress drops zero components and preserves the value; the exact
    // output length is not part of the contract beyond that.
    var with_zero = [3]f64{ 0.0, 1.0, 1.0 };
    var out: [8]f64 = undefined;

    const len: usize = @intCast(c.compress(3, &with_zero, &out));
    try testing.expect(len < 3);
    try testing.expectEqual(2.0, sumOf(out[0..len]));
    try expectNoZeros(out[0..len]);

    // An expansion with no zeros survives compress with the same value.
    var clean = [2]f64{ std.math.ldexp(@as(f64, 1.0), -60), 1.0 };
    const clean_len: usize = @intCast(c.compress(2, &clean, &out));
    try testing.expectEqual(1.0, sumOf(out[0..clean_len]));
}

test "estimate recovers the value an expansion represents" {
    try support.ready();
    var base = [1]f64{1.0};
    var out: [8]f64 = undefined;
    const grown: usize = @intCast(c.grow_expansion_zeroelim(1, &base, std.math.ldexp(@as(f64, 1.0), -52), &out));
    const target = 1.0 + std.math.ldexp(@as(f64, 1.0), -52);

    try testing.expectEqual(target, c.estimate(@intCast(grown), &out));
    try testing.expectEqual(target, sumOf(out[0..grown]));

    // estimate on a single-component expansion is that component.
    var single = [1]f64{-3.75};
    try testing.expectEqual(-3.75, c.estimate(1, &single));
}

test "the random helpers produce finite values within their documented ranges" {
    try support.ready();
    // Upstream ships these for its timing harness. They call the C library
    // random(), which is why this package links libc; the test is here so the
    // dependency is exercised rather than merely declared.
    //
    // Bounds are read off the loops in src/predicates.c rather than the header
    // comments, which are looser. doublerand builds a 53-bit significand and
    // then multiplies by 2^(1 + 2 + 4 + ... + 512) at most, so the magnitude
    // cannot exceed 2^53 * 2^513 < 2^600 and cannot overflow a double. The sign
    // follows from `a - 1073741824`, so the value may be negative.
    const double_samples = [_]f64{
        c.doublerand(),
        c.narrowdoublerand(),
        c.uniformdoublerand(),
    };
    for (double_samples) |sample| {
        try testing.expect(std.math.isFinite(sample));
        try testing.expect(@abs(sample) < std.math.ldexp(@as(f64, 1.0), 600));
    }

    // floatrand works from a 24-bit significand and an exponent multiplier up
    // to 2^63, so |result| stays under 2^87, comfortably inside binary32.
    const float_samples = [_]f32{
        c.floatrand(),
        c.narrowfloatrand(),
        c.uniformfloatrand(),
    };
    for (float_samples) |sample| {
        try testing.expect(std.math.isFinite(sample));
        try testing.expect(@abs(sample) < std.math.ldexp(@as(f32, 1.0), 100));
    }
}
