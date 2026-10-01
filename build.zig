const std = @import("std");

/// Flags the canonical C source needs on every target.
///
/// These are not style choices. Each one exists because getting it wrong makes
/// the predicates silently return the wrong sign.
///
/// `-std=gnu17` pins the language standard rather than taking clang's default.
/// `src/predicates.c` is written in K&R style throughout; C23 removed
/// old-style function definitions, so an unpinned default is a future compile
/// break with no code change on our side. Pinning the standard upstream's
/// source was written for keeps the C byte-identical instead of rewriting forty
/// definitions.
///
/// `-ffp-contract=off` is a correctness requirement. `Two_Product` and
/// `Two_Two_Diff` are error-free transformations built on the assumption that
/// each multiply and each subtract is separately rounded. Clang contracts a
/// multiply and an add into an FMA by default, which breaks the Dekker
/// splitting these macros depend on; the predicates then stop being robust
/// without any diagnostic.
///
/// `-fno-fast-math` is redundant with the default and is written out anyway.
/// Its failure mode is silent: finite-math-only and its relatives let the
/// optimizations that destroy the error analysis run, and the result is a
/// wrong sign from a library whose entire purpose is a right sign.
///
/// Excess precision is the fourth condition upstream names. Every target below
/// is 64-bit or wasm32 and evaluates `double` in binary64 with no x87
/// registers, so there is nothing to suppress; upstream's escape hatch,
/// `#define INEXACT volatile`, is left exactly as upstream wrote it.
const c_flags = [_][]const u8{
    "-std=gnu17",
    "-ffp-contract=off",
    "-fno-fast-math",
};

/// Required compile-only targets. Windows lacks upstream's POSIX random().
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const Graph = struct {
    /// The compiled C library. This is the artifact a C consumer links.
    c_lib: *std.Build.Step.Compile,
    /// The Zig facade, with `c` bound to the translated aggregate header.
    module: *std.Build.Module,
};

/// Builds one target's C library and Zig facade.
///
/// `public` selects between the package module set, which is what a dependent
/// reaches through `dep.module("predicates")`, and a private module. A cross
/// target check needs the private form: modules are registered by name against
/// the whole build, so registering `predicates` once per cross target would
/// leave only the last of them reachable and silently stop checking the rest.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    public: bool,
) Graph {
    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // libc, because `src/predicates.c` includes <stdio.h> and <stdlib.h>
        // and the random-value helpers it publishes call random().
        .link_libc = true,
    });
    c_mod.addCSourceFile(.{
        .file = b.path("src/predicates.c"),
        .flags = &c_flags,
    });

    const c_lib = b.addLibrary(.{
        .name = "predicates",
        .linkage = .static,
        .root_module = c_mod,
    });
    // Installing the header also puts it on the include path of anything that
    // links this artifact, so a dependent that wants the C API does not have to
    // reach into this repository's tree for it.
    c_lib.installHeader(b.path("include/predicates.h"), "predicates.h");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("include/predicates.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const c_module = if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    const module = if (public)
        b.addModule("predicates", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    module.addImport("c", c_module);
    module.linkLibrary(c_lib);

    return .{ .c_lib = c_lib, .module = module };
}

/// Compiles the C library, the facade, the test binary and the example for one
/// cross target, and attaches every one of them to `step`.
///
/// Compiling the test binary is what makes this a real check of the facade
/// rather than of an unreferenced archive: Zig analyses a function body only
/// when something calls it, every public facade function is called from the
/// tests, and so building the test binary for a target analyses all of them for
/// that target. The full C source is compiled by the same graph. Nothing is
/// run, so every result here is compile evidence and not a claim that a
/// cross-built binary executed.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const cross = addGraph(b, cross_target, optimize, false);

    const cross_test_mod = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    cross_test_mod.addImport("predicates", cross.module);
    step.dependOn(&b.addTest(.{ .root_module = cross_test_mod }).step);

    const cross_example_mod = b.createModule(.{
        .root_source_file = b.path("examples/smoke.zig"),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    cross_example_mod.addImport("predicates", cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = "predicates-smoke-cross",
        .root_module = cross_example_mod,
    }).step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const graph = addGraph(b, target, optimize, true);
    b.installArtifact(graph.c_lib);

    // `zig build` installs the compiled C library and compiles the example. The
    // example is the cheapest thing that proves the facade and the C agree on
    // types, symbols and link-time dependencies. It is not installed: it is a
    // proof, not a deliverable.
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport("predicates", graph.module);
    const example = b.addExecutable(.{
        .name = "predicates-smoke",
        .root_module = example_mod,
    });
    b.getInstallStep().dependOn(&example.step);

    // A run artifact already depends on building the executable, which depends
    // on compiling the C and linking the facade. `zig build smoke` deliberately
    // does not run the install step: installing is `zig build`'s job, and
    // conflating the two would make a smoke run depend on the install layout.
    const run_example = b.addRunArtifact(example);
    const smoke_step = b.step("smoke", "Run the deterministic example");
    smoke_step.dependOn(&run_example.step);

    // The test root is `test/all.zig`, which names the files carrying test
    // blocks. A root that only re-exported them would discover no tests and
    // still exit zero, which is a green step that proves nothing.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("predicates", graph.module);
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run the behavioral tests").dependOn(&b.addRunArtifact(unit_tests).step);

    // The cross target gate. Compiling the test binary is what makes this a
    // real check of the facade rather than of an unreferenced archive, and
    // `addTargetCheck` says why.
    const check_step = b.step(
        "check",
        "Compile the C source, facade, tests and example for all six targets without running them",
    );
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, target.query, optimize);
    } else {
        for (check_targets) |query| addTargetCheck(b, check_step, query, optimize);
    }
}
