// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored; see FORK-LICENSE.md and NOTICE.md.
//
const std = @import("std");

/// External consumer that imports the package as a dependency.
/// `zig build run` checks signs against hand-computed answers.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Re-declare and forward `linkage` and `runtime`; undeclared options fail instead of being ignored.
    // They are independent: runtime loading needs a shared provider, while linkage selects the installed artifact.
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
        // The C artifact calls POSIX `random()`, so this consumer needs libc and does not support windows-gnu.
    });
    exe_mod.addImport("predicates", dep.module("predicates"));

    const exe = b.addExecutable(.{
        .name = "predicates-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.addPassthruArgs();
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
