// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// Fork-authored; see FORK-LICENSE.md and NOTICE.md for grant scope and inventory.
// Upstream `src/predicates.c` is Shewchuk's public-domain file, outside this identifier.
//
//! Build graph for the runtime-loaded `c` module and its generated dispatch.
//! The dispatch wraps the target's translated header and must not link the native archive.

const std = @import("std");

/// Must match the `runtime/sync.c` macro and symbol names in `runtime/library.zig`; change both for another instance.
const sync_prefix = "predicates_rt";

/// No translated libc exports: the header includes no system headers; provider-internal POSIX `random()` resolves against its linked libc.
/// Other declared exports are routed and required, so header changes that add libc externs must update this list.
const libc_noise = "";

/// No exports are optional; the header has no conditional entry points.
const provider_optional = "";

/// No provider exports are excluded; all 40 functions and 15 globals are required.
const provider_excluded = "";

/// Creates the shared loader core for linked builds, exposing the public request and error types.
/// Runtime dispatch builds create and re-export their own core; do not import another instance.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // Runtime loading uses libc for `dlopen`; the C artifact also needs it for POSIX `random()`.
        .link_libc = true,
    });
}

/// Creates the runtime-loaded `c` module from this target's translation and configuration.
/// The generated dispatch follows the selected header without linking the native archive.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);
    // The dispatch re-exports translated types from `c_native`, preserving their nominal identity.
    // The patched translation routes nested `__root` references to wrappers, never native externs.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Runs the host generator on this target's translation so the dispatch matches its selected headers and configuration.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("predicates-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("predicates");
    run.addArg("--translate");
    run.addFileArg(translate.getOutput());
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg("native.zig");
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg("dispatch.zig");
    return .{ .native = native_source, .dispatch = dispatch_source };
}
