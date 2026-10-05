// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored. `FORK-LICENSE.md` says what that identifier
// covers and on whose authority, and `NOTICE.md` carries the file inventory.
// `src/predicates.c` is Shewchuk's own public-domain file and is outside this
// identifier entirely; nothing below grants anything over it.
//
// What this build graph delivers, and the options that shape it:
//
//   * `-Dlinkage=static` (the default, and what this package has always
//     installed) puts `libpredicates.a` in `zig-out/lib`. `-Dlinkage=dynamic`
//     puts a shared object there instead. `static` names the *library
//     artifact*; nothing here promises a wholly static executable, and the
//     artifact still needs a libc because `src/predicates.c` calls POSIX
//     `random()`.
//   * `-Druntime` (default false) chooses how the facade reaches the natives.
//     It is orthogonal to `-Dlinkage`: the flag decides whether the symbols
//     arrive through the link line or through the platform loader, and the
//     artifact that gets built and installed is the same either way.
//   * `-Dtarget=x86_64-windows-gnu` is refused before anything is
//     configured, and the reason is printed. The canonical source calls POSIX
//     `random()`, which mingw-w64 and the UCRT do not provide, so that target
//     has no build here; `zig build check` covers the five targets that do
//     build, and asking for the refused one ends at `refusalFor` rather than
//     at the compiler's diagnostics.
//   * `-Doptimize` is Zig's standard option and is left alone.
//
// The two delivery configurations
// --------------------------------
// `false`, the ordinary build: `c` is the translated header itself and the C
// artifact is linked into the facade. The facade still imports the loader core
// as `rt`, because `LoadSource` and `LoadError` are this SDK's public types and
// a consumer must be able to name the same types whichever configuration it
// was built against. That is the whole cost: two declarations, no code.
//
// `true`: `c` becomes the dispatch module the API role's `runtime/graph.zig`
// generates from this build's own translation output, and the C artifact is
// NOT linked into the facade — linking it as well would let the linker satisfy
// the references statically and quietly turn the runtime route back into a
// linked one. The artifact is still compiled and still installed, because the
// point of the option is how the symbols are reached, not whether the library
// exists. A provider for `load` has to be a complete shared object, which is
// `-Dlinkage=dynamic` compiled from this same tree; the two options name
// different things and neither implies the other.
//
// Exactly one loader core is created in either configuration, never two.
// `createModule` builds the one the dispatch re-exports from, and the facade
// does not import `rt` in that mode, so `LoadSource` and `LoadError` stay one
// type rather than two nominally distinct ones.
//
// What the native side already provides for the loader: all fifteen
// file-scope globals (`splitter`, `epsilon` and the twelve error bounds) are
// real definitions in the shared object's data segment, and all forty
// functions are exported, so a loaded image resolves their addresses in place.
// No build step here copies a value out of them, and none may be added: a
// loader handed a copy of `epsilon` is reading a snapshot, not the image.
// POSIX `random()` is the one external call in the library and it is not
// declared in `include/predicates.h`, so it is not a table entry — it is the
// provider's own libc dependency, resolved inside the provider's image.

const std = @import("std");

const manifest = @import("build.zig.zon");

// The API role's build half of the runtime route. It creates the dispatch
// module a `-Druntime=true` build gives the facade as its `c`, and the loader
// core a linked build gives it as `rt`. Imported unconditionally: the option
// chooses between two call sites below, and a build that does not take the
// runtime route never instantiates either function.
const runtime_graph = @import("runtime/graph.zig");

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

/// The compile-only targets `check` walks when it was not given a `-Dtarget`.
/// None of them is run.
///
/// Every row here builds: `src/predicates.c`, the facade, the test binary and
/// the example compile and link for all five. Each row is written as the triple
/// `-Dtarget=` accepts, so this list and the command line cannot come to mean
/// two different targets.
///
/// The same list serves both linkages, and that is a claim that both work on
/// every row of it. `-Dlinkage=dynamic` compiles this list against a shared
/// object instead of an archive; `addGraph` records what a PE/COFF export
/// surface would additionally need from a source this fork does not edit.
const supported_check_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "aarch64-macos-none",
    "riscv64-linux-gnu",
    "wasm32-wasi",
};

/// The rest of the matrix, refused by name rather than attempted.
///
/// `x86_64-windows-gnu` is here, and neither quietly dropped nor left to fail
/// with the compiler's diagnostics: a target this package cannot build is a
/// result it reports, and it reports it by refusing the target before anything
/// is configured — `refusalFor` holds the reason, `refuseTarget` prints it and
/// fails. So `zig build check` is green over the five rows that do build, and
/// `zig build check -Dtarget=x86_64-windows-gnu` fails with that explanation
/// instead of with the 39 C errors the attempt produced.
///
/// An intended target and a supported target are different claims.
/// `supported_check_targets` records the rows this fork has built and linked;
/// this array records the one matrix row that is intended and not built, and
/// `checkMatrixPartition` fails any build if either list stops agreeing with
/// `refusalFor`.
const refused_check_targets = [_][]const u8{
    "x86_64-windows-gnu",
};

/// Why a target has no buildable predicates, or null when it has one.
const Refusal = struct {
    /// One line, printed with the target triple in front of it.
    summary: []const u8,
    /// The long form, printed before the build exits.
    detail: []const u8,
};

/// This build's decision about a target, keyed on the resolved operating
/// system rather than on a triple.
///
/// The one row with evidence behind it is `x86_64-windows-gnu`, and the
/// evidence is not about that ABI: POSIX `random()` is absent from mingw-w64
/// and from the UCRT alike, and a PE/COFF image exports a symbol only when the
/// source marks it. Both are properties of the platform, so a Windows target
/// this package has never attempted refuses with the same explanation instead
/// of compiling it and reporting what the compiler says. No other operating
/// system has a decision recorded against it here.
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

/// Prints why `target` cannot be built, and fails the build.
///
/// This is a refusal and not a warning: nothing is compiled, nothing is
/// installed and no artifact is produced for a target this package has said it
/// cannot build. The text printed is the reason, and it is the same text
/// whether the caller asked for the target with `zig build`, with `zig build
/// check` or with `zig build check -Dtarget=<this target>`.
fn refuseTarget(b: *std.Build, target: std.Build.ResolvedTarget) error{UnsupportedTarget} {
    const refusal = refusalFor(target.result.os.tag) orelse
        @panic("build.zig internal error: refusalFor returned null for a target this build refused");
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    std.log.err("predicates: {s}: {s}\n{s}", .{ triple, refusal.summary, refusal.detail });
    return error.UnsupportedTarget;
}

/// Resolves a target triple written the way `-Dtarget=` writes it.
///
/// Parsed through `std.Build.parseTargetQuery`, which is the same entry point
/// `standardTargetOptions` uses, so a row named in this file and the same row
/// named on the command line are one target rather than two.
fn parseTriple(b: *std.Build, triple: []const u8) std.Target.Query {
    return std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch |err| {
        @panic(b.fmt("build.zig: {s} is not a target triple: {s}", .{ triple, @errorName(err) }));
    };
}

/// Keeps the two halves of the matrix honest against each other.
///
/// Naming `refused_check_targets` is what stops the refused row from being
/// quietly dropped, and naming `supported_check_targets` is what makes each of
/// its rows a claim rather than a wish. Both are re-derived here through the
/// same `refusalFor` that `build()` and `refuseTarget` use, on every invocation
/// and not only on `check`, so a row that stops resolving, or a target that
/// moves between the two lists, fails any build of this package rather than
/// quietly changing what `check` proves.
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

/// Where the terms that have to travel with a redistributed binary are
/// installed, and what each of those files is.
///
/// There is no `LICENSE` to copy because upstream ships none: the grant is the
/// public-domain dedication in the header of `src/predicates.c`, reproduced
/// verbatim in `NOTICE.md`. `FORK-LICENSE.md` carries the terms this fork's own
/// files were released under, and `UPSTREAM.md` carries the canonical URL, the
/// revision and the digest of the native file. For a public-domain project the
/// notice *is* the grant, so a package that installed the library without these
/// three would hand a recipient nothing that states its terms.
const licence_material = [_][]const u8{
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
};

/// Where those three land under the install prefix, so a reader looking for a
/// public-domain grant finds it where a package's terms normally are rather
/// than having to know that this project has no LICENSE file. `package.nix`
/// gets the same path by running this graph with `--prefix $out`.
const licence_dest_dir = "share/licenses/predicates";

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
///
/// `linkage` selects the artifact and nothing else. The compile flags, the
/// translation and the facade are identical in both modes, so a consumer cannot
/// get different arithmetic out of a shared build than out of the static one.
///
/// `runtime` selects how the facade reaches the natives. It is a separate axis
/// from `linkage`: `-Dlinkage=dynamic -Druntime=false` delivers a shared
/// object that the facade links, and `-Dlinkage=static -Druntime=true` builds
/// an archive for a caller to load while the facade resolves through the table.
/// Both combinations are real configurations and neither is refused.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime: bool,
    public: bool,
) Graph {
    // Declared with its type spelled out, because `true` and `null` in the same
    // conditional would otherwise be peer-resolved rather than coerced, and the
    // field is a `?bool`.
    const pic: ?bool = if (linkage == .dynamic) true else null;

    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // libc, because `src/predicates.c` includes <stdio.h> and <stdlib.h>
        // and the random-value helpers it publishes call random().
        .link_libc = true,
        // Position-independent code, and only in the shared mode.
        //
        // `src/predicates.c` has to be position-independent for a shared
        // object. A static archive does not, and leaving the field null there
        // keeps that compile line byte-for-byte what it has always been, so
        // the default variant of this build is not changed by the option that
        // selects it.
        //
        // `-fPIC` reaches the C compiler through
        // `Module.appendZigProcessFlags`, which emits `-fPIC` for a `true` and
        // nothing at all for a `null` (lib/std/Build/Module.zig:554). It is
        // stated here rather than left to the compiler driver's own default
        // because that default is not part of the shipped standard library and
        // this file cannot cite it. Whether every target in
        // `supported_check_targets` accepts the flag is a driver observation,
        // not a claim: those five rows are compiled by `zig build check
        // -Dlinkage=dynamic`, and what each one does with it is recorded
        // there.
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
    //
    // No `.version` is set, and that is a decision rather than an omission.
    // A version turns the artifact into a soname series: Zig names the file
    // `libpredicates.so.<major>` and installs `libpredicates.so` as a symlink
    // to it (lib/std/Build/Step/Compile.zig:491-505 and
    // lib/std/Build/Step/InstallArtifact.zig:143-145). `UPSTREAM.md` records
    // that upstream has no version, tag or release series for this file, and
    // `build.zig.zon`'s 0.1.0 is this fork's own. Publishing a soname major
    // derived from it would state an ABI compatibility promise that no source
    // record supports, so the shared object is installed under its plain name
    // and `-lpredicates` resolves it.
    //
    // Export surface. `src/predicates.c` declares no `static` function and no
    // `static` file-scope object: all forty externally visible definitions and
    // all fifteen globals have external linkage, and none of them is marked
    // with a visibility attribute. Every ELF and Mach-O target therefore
    // exports the whole declared surface from a shared object with no export
    // list, no version script and no `-fvisibility=hidden`. Adding hidden
    // visibility here — which spglib's graph does, because spglib has its own
    // export macro — would make the shared object export nothing at all, and
    // the fifteen globals are what a runtime loader later resolves by address.
    //
    // One target cannot deliver a shared object from this source, and it is
    // named rather than worked around: `x86_64-windows-gnu` does not build
    // `src/predicates.c` at all, because the file calls POSIX `random()`, which
    // mingw-w64 and the UCRT do not provide. A Windows DLL would also need an
    // explicit export declaration, since PE/COFF exports nothing by default
    // and this source carries no `__declspec(dllexport)`. That is a boundary of
    // the canonical file, not something a build flag can change.
    // It is refused rather than attempted: `refused_check_targets` names that
    // row and `refusalFor` holds the printed reason for both of these
    // boundaries, so no linkage option reaches past either one.
    //
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
    // Keep the translated module private. The facade binds it as `c` with
    // addImport below and carries the native library. Publishing `dep.module("c")`
    // would expose declarations without that linkage; the raw route is
    // `@import("predicates").c`.
    //
    // Runtime dispatch instead imports this translation privately as `c_native`.
    // `public` controls only the facade's package-registry entry.
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
    // The facade's bindings, and the one place the two configurations differ.
    //
    // `c` is the translated header in a linked build and the dispatch table in
    // a runtime one. Both are bound inside the facade under the same import name.
    module.addImport("c", c_module);

    // The loader core is the linked configuration's `rt`. `src/root.zig` reads
    // `rt.LoadSource` and `rt.LoadError` to publish this SDK's own versions of
    // those two types, and a consumer has to name the same types it was built
    // against. In a runtime build those reads are on the dead side of a
    // comptime-known `if`, so the declaration is never analysed and the import
    // is never registered — registering it there would be the second instance
    // `runtime/graph.zig` explicitly warns against, because the dispatch already
    // re-exports the types from the core it made for itself.
    //
    // What makes this safe is a property of the facade, not of this file:
    // `src/root.zig` reaches `rt` only through `if (runtime_loaded) c.X else
    // rt.X`, and `runtime_loaded` is a `pub const bool` with a comptime-known
    // initializer, so the untaken branch is never analysed. This option and
    // those two declarations are load-bearing together. If either side is
    // "simplified" — an unconditional `rt.LoadSource`, or a reference outside
    // the conditional — a `-Druntime=true` build starts failing on a module it
    // no longer registers, with an error that names this file's choice rather
    // than the change that caused it. If that happens, the fix is to restore the
    // conditional in `src/root.zig`, not to register a second core here: two
    // instances would mean two `LoadSource` types, and a consumer would be
    // naming one while `load` expects the other.
    if (!runtime) {
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));

        // And only here. The C artifact is linked into the facade when the
        // natives are reached through the link line, and not when they are
        // reached through the loader: a module that both imports the dispatch
        // and links the archive lets the linker satisfy the references
        // statically, and the runtime route becomes a linked one with no
        // diagnostic anywhere. The artifact itself is still built and
        // installed in both configurations — `-Druntime` changes how the symbols
        // are reached, not whether the library exists — and `c_lib` is still
        // returned below so `build()` installs it either way.
        module.linkLibrary(c_lib);
    }

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
    linkage: std.builtin.LinkMode,
    runtime: bool,
) void {
    // `linkage` and `runtime` are both passed through rather than pinned here.
    // A `check` that silently analysed a different configuration than the rest
    // of the build produces would be checking something nobody asked for:
    // `zig build check -Dlinkage=dynamic` and `zig build check -Druntime=true`
    // are requests to compile the facade, the tests and the example the way the
    // native graph was built, and this is where that request is honoured.
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

/// The link metadata for the installed library, generated rather than copied.
///
/// The installed library is `libpredicates.a` in the static variant and
/// `libpredicates.so` in the shared one; `Libs: -L${libdir} -lpredicates`
/// resolves either, because no soname series is published (see `addGraph`), so
/// one `.pc` is correct for both variants and it takes no linkage argument.
/// Whether the linker opens an archive or a shared object from that name is the
/// consumer's and the linker's business, not something this file states.
///
/// `Cflags:` carries the include path and nothing else. `-std=gnu17`,
/// `-ffp-contract=off` and `-fno-fast-math` are requirements of the translation
/// unit that *implements* the predicates, and that unit is `src/predicates.c`,
/// compiled here with exactly those flags. A caller's own object file computes
/// no determinant: every predicate it calls returns a value the library has
/// already computed. Propagating a code-generation flag into every consumer
/// would be a side effect this library has no reason to impose, so the flags
/// stay where they are needed and `include/predicates.h` states the
/// requirement for the file that needs it.
///
/// `Libs.private:` is empty, and that states the dependency closure rather than
/// omitting one. The library calls exactly one external function that is not a
/// macro: POSIX `random()`, from the six published debug helpers. That is libc,
/// which every C consumer links whether or not a `.pc` says so. The file
/// includes `<math.h>` but calls nothing from libm — `Absolute` is defined as a
/// comparison, and the only `fabs` in the file is inside a comment — so `-lm`
/// would name a dependency this library does not have.
///
/// `prefix` is derived from this file's own directory, which is what makes the
/// metadata correct wherever the prefix lands. Both `zig build install
/// --prefix X` and a Nix `$out` place this file at
/// `$prefix/lib/pkgconfig/predicates.pc`, three levels below the prefix. That
/// spelling needs pkg-config 0.29 or newer, or pkgconf, and the file says so
/// rather than hardcoding `/usr/local`.
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

    // Every row of the matrix, supported or refused, is re-derived before
    // anything is configured and on every invocation, not only on `check`.
    checkMatrixPartition(b);

    // And then the requested target, refused before a graph is built and before
    // any compiler runs. It is here rather than inside the option parsing
    // below because no option this file offers can turn a refused target into
    // a different one: `-Dlinkage` and `-Druntime` change how an artifact is
    // built, and neither of them provides POSIX `random()` to a C library that
    // has none. `zig build check -Dtarget=x86_64-windows-gnu` therefore fails
    // with the printed reason and not with the 39 diagnostics the compile
    // produced, and no compiler is invoked at all.
    if (refusalFor(target.result.os.tag) != null) return refuseTarget(b, target);

    // Which artifact this build installs and links. Static is the default and
    // is what this package has always delivered, so every command that exists
    // today still produces the artifact it produced before this option did;
    // adding it changes nothing for anyone who does not pass it.
    //
    // The spelling is the enum's own, so the CLI values are `static` and
    // `dynamic` (`std.builtin.LinkMode`, lib/std/builtin.zig:870-873). It is
    // the same option name spglib, pcre2 and lmdb use for their own libraries,
    // deliberately: one option with one set of values across the whole
    // workspace is worth more than a locally invented synonym.
    //
    // `static` names the library artifact. It is not a claim that a program
    // linking it is wholly static: the artifact still calls POSIX `random()`,
    // so it needs a libc at run time.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Install the native artifact as a static archive (default) or as a shared library",
    ) orelse .static;

    // Whether the facade reaches the natives through the link line or through
    // the platform loader. False is the ordinary build and stays the default,
    // so every command that exists today still builds what it built before
    // this option did.
    //
    // A plain boolean with one spelling, `true`/`false`, and no default that is
    // inferred from anything else. It is deliberately *not* derived from
    // `-Dlinkage`: a shared object is a thing a caller can also simply link,
    // and a caller that wants to load one at run time is a different question
    // from a caller that wants a `.so` on disk. The two combine freely, and
    // neither combination is refused.
    //
    // There is no third state here and no "auto". A build either resolves its
    // symbols through the dispatch table or it does not, and a consumer can
    // tell which from the facade's `runtime_loaded` constant at comptime.
    const runtime = b.option(
        bool,
        "runtime",
        "Resolve the native symbols through the runtime loader instead of through the link line (default: link them)",
    ) orelse false;

    // The native artifact is compiled and installed in both configurations.
    // Nothing below is allowed to make `-Druntime=true` build less of a
    // library: the option changes how the facade reaches the symbols, and the
    // loader needs a real provider to load.

    // The version the generated `.pc` reports. Read out of the manifest rather
    // than written into the generated text, so the metadata cannot describe a
    // different release from the package it sits in. This is the fork's own
    // 0.1.0 and means nothing upstream: `UPSTREAM.md` records that this file
    // has no version, tag or release series.
    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };

    const graph = addGraph(b, target, optimize, linkage, runtime, true);

    // `zig-out/lib` gets the artifact — `libpredicates.a`, or the shared
    // object under `-Dlinkage=dynamic`. `zig-out/include/predicates.h` is
    // installed by `addGraph` through `installHeader`, which attaches the header
    // to this artifact rather than to the install step alone, so it is also on
    // the include path of everything that links the library.
    //
    // Installed under `-Druntime=true` as well. The facade does not link it in
    // that configuration, but the loader has nothing to load without it, and a
    // build option that quietly stopped producing the library would make the
    // runtime route untestable rather than faster.
    b.installArtifact(graph.c_lib);

    // `zig-out/lib/pkgconfig/predicates.pc`, so a C consumer's build system can
    // ask where the library is instead of guessing `-lpredicates`. Same file
    // for both variants; `pkgConfigFile` says why.
    //
    // The dependency on the install step is written out because
    // `Build.addInstallFile` creates the step without attaching it
    // (lib/std/Build/Step/InstallFile.zig:15-36). `Build.installFile` does
    // attach it, but it takes a repository path, and this file is generated.
    b.getInstallStep().dependOn(
        &b.addInstallFile(pkgConfigFile(b, package_version), "lib/pkgconfig/predicates.pc").step,
    );

    // The terms that travel with a redistributed binary. `UPSTREAM.md` records
    // that upstream ships no licence file because there is none to ship, and
    // that is not an exemption: the public-domain dedication is in the header
    // of `src/predicates.c` and in `NOTICE.md`, and a recipient of the library
    // needs to be able to find it. These are copies of files already in this
    // repository, byte for byte; nothing is rewritten on the way out.
    //
    // `package.nix` installs nothing by hand and just runs this graph with
    // `--prefix $out`, so the Nix output and a plain `zig build install` produce
    // one layout rather than two.
    for (licence_material) |file| {
        b.installFile(file, b.fmt("{s}/{s}", .{ licence_dest_dir, file }));
    }

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
    if (b.args) |args| run_example.addArgs(args);
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
    //
    // The step description names the configuration, because the two linkages and
    // the two delivery routes are four different builds and a reader of a CI
    // log needs to know which one produced the line they are looking at. It
    // names the matrix too: this walks the rows that build, so a green `check`
    // is green over every target this package supports, and the refused row is
    // named there rather than being a target the run silently skips.
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
    // Given a `-Dtarget`, this checks that one target and nothing else; without
    // one it walks `supported_check_targets`. The refused row is neither
    // compiled nor omitted: `build()` re-derived both lists above and refused
    // this target if it was that one, and naming it on the command line ends at
    // `refuseTarget` with the reason rather than at the compiler.
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, target.query, optimize, linkage, runtime);
    } else {
        for (supported_check_targets) |triple| {
            addTargetCheck(b, check_step, parseTriple(b, triple), optimize, linkage, runtime);
        }
    }
}
