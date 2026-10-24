// SPDX-License-Identifier: LicenseRef-PublicDomain
// Fork terms are in FORK-LICENSE.md. src/predicates.c keeps its public-domain grant.

const std = @import("std");

const manifest = @import("build.zig.zon");

// Builds runtime dispatch and the shared loader core.
const runtime_graph = @import("runtime/graph.zig");

/// GNU17 accepts the source's K&R definitions.
/// Disable FP contraction and fast math to preserve error-free transforms.
const c_flags = [_][]const u8{
    "-std=gnu17",
    "-ffp-contract=off",
    "-fno-fast-math",
};

/// Compile-only targets for `check`; the generated binaries are not run.
const supported_check_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "aarch64-macos-none",
    "riscv64-linux-gnu",
    "wasm32-wasi",
};

/// Windows is refused because upstream calls POSIX `random()`.
/// PE/COFF shared builds also need exports absent from the source.
const refused_check_targets = [_][]const u8{
    "x86_64-windows-gnu",
};

/// Build refusal details for an unsupported target.
const Refusal = struct {
    summary: []const u8,
    detail: []const u8,
};

/// Returns the recorded refusal for an operating system, if any.
fn refusalFor(os_tag: std.Target.Os.Tag) ?Refusal {
    if (os_tag != .windows) return null;

    return .{
        .summary = "no buildable configuration for this target: the canonical source calls POSIX random(), which Windows does not provide.",
        .detail =
        \\src/predicates.c calls POSIX random() at 13 call sites in the six
        \\helpers it publishes for generating random values: three in
        \\doublerand (src/predicates.c:503-505), three in narrowdoublerand
        \\(:529-531), two in uniformdoublerand (:552-553), two in floatrand
        \\(:572-573), two in narrowfloatrand (:597-598) and one in
        \\uniformfloatrand (:619). random() is POSIX, not ISO C. The
        \\toolchain's Windows <stdlib.h>, at
        \\lib/libc/include/any-windows-any/stdlib.h, declares rand_s at line
        \\365 and no random, so the compile of the canonical file fails on
        \\Windows in every configuration of this package. That same compile
        \\also reports each of the 33 old-style function definitions in the
        \\1996 source as an error, which the five rows that do build do not.
        \\Both failures are in the canonical file, and neither is something a
        \\flag in this graph can set.
        \\
        \\A shared object meets a second, independent boundary behind that one:
        \\a PE/COFF DLL exports nothing unless the source marks each symbol,
        \\and none of the 40 functions or 15 globals in src/predicates.c
        \\carries __declspec(dllexport) or any other export declaration.
        \\-Dlinkage=dynamic therefore does not reach the boundary above; it
        \\meets this one as well.
        \\
        \\What would have to change, and why none of it is done here:
        \\
        \\  * Supplying a random(). That is what makes the target compile, and
        \\    it means shipping a different generator behind six published
        \\    entry points declared in include/predicates.h.
        \\  * Declaring random() and leaving the definition to the linker. A
        \\    declaration with no definition behind it converts a compile
        \\    error into a link error, and this graph links a test binary and
        \\    an example, so the failure moves rather than goes away.
        \\  * Passing -Wno-error=old-style-definition. It would silence 33 of
        \\    the 39 diagnostics and change nothing, because random() is still
        \\    undeclared. This package passes no -Wno- flag for the C at all.
        \\  * Editing src/predicates.c. UPSTREAM.md records the digest that is
        \\    the reason to trust this package, and FORK-NOTES.md section 21
        \\    records the diagnostics, the header that settles the question and
        \\    the options refused here.
        \\
        \\The rows that do build: x86_64-linux-gnu, aarch64-linux-gnu,
        \\aarch64-macos-none, riscv64-linux-gnu, wasm32-wasi.
        ,
    };
}

/// Prints the refusal reason and returns `UnsupportedTarget`.
fn refuseTarget(b: *std.Build, target: std.Build.ResolvedTarget) error{UnsupportedTarget} {
    const refusal = refusalFor(target.result.os.tag) orelse
        @panic("build.zig internal error: refusalFor returned null for a target this build refused");
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    std.log.err("predicates: {s}: {s}\n{s}", .{ triple, refusal.summary, refusal.detail });
    return error.UnsupportedTarget;
}

fn parseTriple(b: *std.Build, triple: []const u8) std.Target.Query {
    return std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch |err| {
        @panic(b.fmt("build.zig: {s} is not a target triple: {s}", .{ triple, @errorName(err) }));
    };
}

/// Ensures the supported and refused target lists match `refusalFor`.
fn checkMatrixPartition(b: *std.Build) void {
    for (supported_check_targets) |triple| {
        if (refusalFor(b.resolveTargetQuery(parseTriple(b, triple)).result.os.tag) != null) {
            @panic(b.fmt(
                "build.zig: {s} is in supported_check_targets but this build refuses its operating system; move it to refused_check_targets",
                .{triple},
            ));
        }
    }
    for (refused_check_targets) |triple| {
        if (refusalFor(b.resolveTargetQuery(parseTriple(b, triple)).result.os.tag) == null) {
            @panic(b.fmt(
                "build.zig: {s} is in refused_check_targets but refusalFor now accepts its operating system; move it to supported_check_targets and prove that it builds",
                .{triple},
            ));
        }
    }
}

/// Licensing files installed with each package.
const licence_material = [_][]const u8{
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
};

/// Install path for licensing records.
const licence_dest_dir = "share/licenses/predicates";

const Graph = struct {
    c_lib: *std.Build.Step.Compile,
    module: *std.Build.Module,
};

/// Builds a target's C library and facade.
/// `public` controls package registration; `linkage` selects the artifact type.
/// `runtime` changes symbol resolution independently of linkage.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime: bool,
    public: bool,
) Graph {
    // Specify `?bool` so the `true` and `null` branches have one type.
    const pic: ?bool = if (linkage == .dynamic) true else null;

    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // The native source includes libc headers and calls POSIX `random()`.
        .link_libc = true,
        // Enable PIC only for shared libraries.
        // Null preserves static defaults; true adds `-fPIC` through the Zig build API.
        .pic = pic,
    });
    c_mod.addCSourceFile(.{
        .file = b.path("src/predicates.c"),
        .flags = &c_flags,
    });

    const c_lib = b.addLibrary(.{
        .name = "predicates",
        .linkage = linkage,
        .root_module = c_mod,
    });
    // No `.version`: upstream has no release series to support a soname ABI promise.
    // Keep default visibility; runtime loading resolves all functions and globals.
    // Windows is refused because upstream lacks POSIX `random()` and PE exports.
    // `installHeader` attaches the include path to dependent artifacts.
    c_lib.installHeader(b.path("include/predicates.h"), "predicates.h");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("include/predicates.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Keep raw declarations private; the facade exposes them through its `c` import.
    // Runtime mode binds the generated dispatch module instead.
    const c_module = if (runtime)
        runtime_graph.createModule(b, translate_c, target, optimize)
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

    // Import the loader core only in linked mode so its public types stay unique.
    // Runtime dispatch re-exports those types; do not register a second core.
    // The facade's comptime branch omits this import in runtime mode.
    if (!runtime) {
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));

        // Link the C artifact only in linked mode; otherwise the linker could bypass dispatch.
        // It remains built and installed in runtime mode as the provider to load.
        module.linkLibrary(c_lib);
    }

    return .{ .c_lib = c_lib, .module = module };
}

/// Adds the C library, facade, tests and example to a compile-only target check.
/// The test binary forces facade analysis; no binary is run.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime: bool,
) void {
    // Use the requested linkage and runtime mode for every target check.
    const cross_target = b.resolveTargetQuery(query);
    const cross = addGraph(b, cross_target, optimize, linkage, runtime, false);

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

/// Generates prefix-relative pkg-config metadata for static and shared artifacts.
/// Both use `-lpredicates`; `Cflags` adds only the include path.
fn pkgConfigFile(b: *std.Build, package_version: std.SemanticVersion) std.Build.LazyPath {
    return b.addWriteFiles().add("predicates.pc", b.fmt(
        \\# Generated by predicates/build.zig from the sources in this package.
        \\# Do not edit.
        \\#
        \\# `prefix` is this file's own directory, so the metadata is right
        \\# wherever the prefix is placed; that spelling needs pkg-config 0.29+
        \\# or pkgconf.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\includedir=${{prefix}}/include
        \\libdir=${{prefix}}/lib
        \\
        \\Name: predicates
        \\Description: Shewchuk's adaptive-precision floating-point arithmetic and fast robust geometric predicates
        \\URL: https://www.cs.cmu.edu/~quake/robust.html
        \\Version: {f}
        \\Cflags: -I${{includedir}}
        \\Libs: -L${{libdir}} -lpredicates
        \\Libs.private:
        \\
    , .{package_version}));
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Revalidate matrix declarations before configuring the target.
    checkMatrixPartition(b);

    // Refuse unsupported systems before creating a graph or invoking a compiler.
    if (refusalFor(target.result.os.tag) != null) return refuseTarget(b, target);

    // The library artifact defaults to static; it still needs libc at runtime.
    // CLI values are the standard `LinkMode` tags: `static` and `dynamic`.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Install the native artifact as a static archive (default) or as a shared library",
    ) orelse .static;

    // Runtime loading is independent of static/shared artifact linkage.
    // Keep linked mode as default; `runtime_loaded` exposes the mode at comptime.
    const runtime = b.option(
        bool,
        "runtime",
        "Resolve the native symbols through the runtime loader instead of through the link line (default: link them)",
    ) orelse false;

    // Derive the generated pkg-config version from the package manifest.
    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };

    const graph = addGraph(b, target, optimize, linkage, runtime, true);

    // Install the provider artifact in both modes.
    b.installArtifact(graph.c_lib);

    // Install generated pkg-config metadata at the prefix-relative path.
    // Attach its step explicitly because `addInstallFile` does not.
    b.getInstallStep().dependOn(
        &b.addInstallFile(pkgConfigFile(b, package_version), "lib/pkgconfig/predicates.pc").step,
    );

    // Copy licensing and provenance records unchanged into the install prefix.
    for (licence_material) |file| {
        b.installFile(file, b.fmt("{s}/{s}", .{ licence_dest_dir, file }));
    }

    // Compile the smoke example in the default build without installing it.
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

    // The smoke step runs the example without depending on installation.
    const run_example = b.addRunArtifact(example);
    run_example.addPassthruArgs();
    const smoke_step = b.step("smoke", "Run the deterministic example");
    smoke_step.dependOn(&run_example.step);

    // test/all.zig imports test blocks; a re-export-only root would discover none.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("predicates", graph.module);
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run the behavioral tests").dependOn(&b.addRunArtifact(unit_tests).step);

    const refused_rows = std.mem.join(b.allocator, ", ", &refused_check_targets) catch
        @panic("OOM");
    const check_step = b.step(
        "check",
        b.fmt(
            "Compile the C source, facade, tests and example for the {d} buildable targets without running them ({s} refused, with its reason printed when it is asked for by name): {s} library, {s}",
            .{
                supported_check_targets.len,
                refused_rows,
                @tagName(linkage),
                if (runtime) "runtime-loaded natives" else "linked natives",
            },
        ),
    );
    // Check the requested target only, or all supported targets for the native build.
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, target.query, optimize, linkage, runtime);
    } else {
        for (supported_check_targets) |triple| {
            addTargetCheck(b, check_step, parseTriple(b, triple), optimize, linkage, runtime);
        }
    }
}
