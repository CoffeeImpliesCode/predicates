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

    const dep = b.dependency("predicates", .{
        .target = target,
        .optimize = optimize,
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
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
