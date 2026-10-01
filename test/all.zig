//! Test root.
//!
//! `zig build test` compiles this file, not the individual suites. The imports
//! below are what put the tests in those files into the binary: without them
//! the test runner discovers nothing here, exits zero, and proves nothing.
//!
//! The oracle comes first so its own self-checks run before anything compares
//! itself against it. Test order is not a contract, but failing inside the
//! oracle is easier to read than a mismatch reported three files away.

test {
    _ = @import("exact_oracle.zig");
    _ = @import("predicates_test.zig");
    _ = @import("expansion_test.zig");
}
