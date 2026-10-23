// SPDX-License-Identifier: LicenseRef-PublicDomain
//
// Fork-authored; see FORK-LICENSE.md and NOTICE.md for grant scope and inventory.
// Upstream `src/predicates.c` is Shewchuk's public-domain file, outside this identifier.
//
//! Predicates' runtime-loader descriptor: namespaced synchronization and provider validation.
//! All 40 functions and 15 writable binary64 globals in `include/predicates.h` are required; providers must match this target's C ABI.
//! Validation checks `exactinit`'s binary64 constants but cannot prove compiler flags; use `-ffp-contract=off`, no fast-math, and no excess precision.

const rt = @import("rt");

/// Namespaced synchronization binding for the process-global loader.
/// Names must match `RT_SYNC_PREFIX=predicates_rt` in `runtime/graph.zig`; mismatches fail to link.
pub const Sync = struct {
    extern fn predicates_rt_lock() void;
    extern fn predicates_rt_unlock() void;
    extern fn predicates_rt_wait() void;
    extern fn predicates_rt_broadcast() void;
    // C `unsigned long long` maps to `u64` on every supported target ABI.
    extern fn predicates_rt_thread_self() u64;

    pub fn lock() void {
        predicates_rt_lock();
    }
    pub fn unlock() void {
        predicates_rt_unlock();
    }
    pub fn wait() void {
        predicates_rt_wait();
    }
    pub fn broadcast() void {
        predicates_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return predicates_rt_thread_self();
    }
};

/// `exactinit`'s binary64 epsilon result (`src/predicates.c`).
const binary64_epsilon: f64 = 0x1p-53;

/// `exactinit`'s binary64 splitter result: `2^27 + 1` (`src/predicates.c`).
const binary64_splitter: f64 = 0x1p27 + 1.0;

/// Builds the loader descriptor for the generated dispatch.
/// The type parameter keeps descriptor and dispatch dependencies one-way.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Used in the pre-load panic.
        pub const library_name = "predicates";

        /// Dispatch table and required symbols from the translated header.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Initializes and checks the candidate's own constants after symbol resolution, before publication.
        /// Returns a refusal reason when the provider does not match binary64 expectations.
        pub fn validate(dst: *const table) ?[]const u8 {
            // The candidate table is private until the loader publishes readiness.
            dst.exactinit();

            const epsilon = dst.epsilon.*;
            if (epsilon != binary64_epsilon) {
                return "exactinit() left epsilon at a value other than 2^-53, so " ++
                    "this provider was not built for IEEE 754 binary64 REAL, or " ++
                    "the fifteen file-scope globals are not the provider's own " ++
                    "writable storage";
            }

            const splitter = dst.splitter.*;
            if (splitter != binary64_splitter) {
                return "exactinit() left splitter at a value other than 2^27 + 1, " ++
                    "so this provider was not built for IEEE 754 binary64 REAL, or " ++
                    "the fifteen file-scope globals are not the provider's own " ++
                    "writable storage";
            }

            // `resulterrbound` is checked against its binary64 formula (`src/predicates.c`).
            const expected = (3.0 + 8.0 * binary64_epsilon) * binary64_epsilon;
            if (dst.resulterrbound.* != expected) {
                return "resulterrbound does not match the value exactinit() " ++
                    "derives from a binary64 epsilon, so the constants this " ++
                    "provider published were not produced by one exactinit run";
            }

            return null;
        }
    };
}
