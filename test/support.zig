// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// This file is fork-authored. `FORK-LICENSE.md` says what that identifier
// covers and on whose authority, and `NOTICE.md` carries the file inventory.
//
//! What a test binary has to do before it touches the library, in either of the
//! two configurations this package is published in.
//!
//! In a linked build that is one call: `predicates.init()`. In a
//! runtime-loading build the library is not there yet, so the provider has to be
//! named explicitly and loaded, and a test run that did not do so is a
//! configuration error rather than a silent fallback onto some other library.
//!
//! The provider is named by the `PREDICATES_TEST_PROVIDER` environment
//! variable. There is no `--provider` flag here and no default path, for the
//! ordinary reason that a test binary has no `main` to parse one: Zig's test
//! runner owns it. `examples/smoke.zig` and `consumer/src/main.zig` do have a
//! `main`, and both accept `--provider <path>` as well, because a recorded
//! command line beats a recorded environment for reproducing a run.

const std = @import("std");

const predicates = @import("predicates");

/// The environment variable naming the provider for a runtime-loading test run.
pub const provider_env_var = "PREDICATES_TEST_PROVIDER";

/// Load the named provider when this is a runtime-loading build, then run
/// `exactinit` under the facade's once-guard.
///
/// Returns an error, rather than skipping or defaulting, when the build needs a
/// provider and none was named: a green test run that never reached the library
/// would say nothing about the library, and a run that quietly opened something
/// else would say something false.
///
/// Calling it more than once is fine and cheap. `load` answers a repeated
/// request for the same provider with a no-op, and `init` is idempotent, so
/// every test in this package can establish the precondition itself instead of
/// depending on which test the runner happened to run first.
pub fn ready() !void {
    if (comptime predicates.runtime_loaded) {
        const path = environmentValue(provider_env_var) orelse {
            std.debug.print(
                "test: this is a runtime-loading build. Export {s} with the path to a " ++
                    "shared object exporting the forty functions and the fifteen globals " ++
                    "of include/predicates.h. Nothing is loaded by default and no other " ++
                    "file is tried.\n",
                .{provider_env_var},
            );
            return error.ProviderNotConfigured;
        };

        // The loader keeps its own copy of the request for the life of the
        // process, so nothing here has to outlive the call.
        predicates.load(.{ .path = path }) catch |err| {
            std.debug.print("test: load(.{{ .path = \"{s}\" }}) failed: {t}\n", .{ path, err });
            return err;
        };
    }
    predicates.init();
}

/// Reads `name` from the C environment block, or returns null when unset. Test
/// binaries lack `std.process.Init` because the runner owns `main`; the result
/// borrows that block for the process lifetime.
///
/// This function is only reachable from the runtime-loading branch in `ready`,
/// which a comptime-known condition prunes in a linked build, so a linked build
/// never looks at the C environment at all.
fn environmentValue(name: []const u8) ?[]const u8 {
    var index: usize = 0;
    while (std.c.environ[index]) |entry| : (index += 1) {
        // `startsWith` decides the length first, and `and` is short-circuiting,
        // so a shorter entry never reaches the subscript.
        const value = std.mem.span(entry);
        if (value.len > name.len and std.mem.startsWith(u8, value, name) and value[name.len] == '=') {
            return value[name.len + 1 ..];
        }
    }
    return null;
}