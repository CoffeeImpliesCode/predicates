// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored; see FORK-LICENSE.md and NOTICE.md.
//
const std = @import("std");

/// A package that consumes `predicates` from outside.
///
/// This exists to prove one thing: that a dependent needs only
/// `dep.module("predicates")` and gets a working, correctly linked library.
/// If the facade module stopped carrying its C artifact, or the translated
/// header stopped matching the C source, this would stop building or stop
/// producing the right signs, and nothing inside the library would notice.
///
/// Run it with `zig build run`. It exits non-zero if any predicate disagrees
/// with the answer worked out by hand, so it is a check and not a demo.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The two delivery options are re-declared here, with the same names, the
    // same values and the same defaults as the library's own `build.zig`, and
    // passed straight through.
    //
    // Re-declaring rather than forwarding blindly is deliberate: `b.dependency`
    // fails on an option the dependency does not declare, so a consumer that
    // names one gets a configure-time error instead of a silently ignored
    // flag. A consumer that passed `-Druntime=true` while the library was
    // built linked would be asking its own source for the runtime route and
    // getting a linked one, which is the same silent drop from the other side.
    //
    // `runtime` is orthogonal to `linkage`: the flag says how the facade
    // reaches the natives, the linkage says which artifact this build installs.
    // `-Druntime=true` normally pairs with `-Dlinkage=dynamic`, because a
    // provider for `load` has to be a complete shared object, but the two are
    // not coupled here and neither implies the other.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Ask the library for a static archive (default) or for a shared library",
    ) orelse .static;
    const runtime = b.option(
        bool,
        "runtime",
        "Ask the library to resolve its native symbols through the runtime loader instead of through the link line (default: link them)",
    ) orelse false;

    const dep = b.dependency("predicates", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // The library module requires libc, because the canonical C includes
        // <stdio.h> and <stdlib.h> and calls POSIX random(). Stating it here
        // too is redundant but makes the consumer's own requirement visible.
        //
        // It is also this package's platform boundary: building *this*
        // consumer for windows-gnu fails for the same reason the library's
        // own cross check does, because the C library there has no random().
        // That target is documented as unsupported in FORK-NOTES.md section
        // 21 rather than worked around here.
    });
    exe_mod.addImport("predicates", dep.module("predicates"));

    const exe = b.addExecutable(.{
        .name = "predicates-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
