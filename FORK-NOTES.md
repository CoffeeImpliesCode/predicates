# Fork notes

This package wraps Shewchuk's single-file `predicates.c`. That C file is unchanged; all other source files below are fork additions.

## Source files

| File | Change and reason |
|---|---|
| `src/predicates.c` | Unchanged byte-for-byte to preserve the canonical implementation and its checksum. |
| `include/predicates.h` | Adds the 40 function prototypes and 15 globals embedded in upstream comments, for `translate-c` and C consumers. |
| `src/root.zig` | Adds typed Zig entry points, a process-wide once guard for `exactinit()`, and a non-finite-coordinate error; raw C remains available. |
| `runtime/loader.zig` | Adds a reusable explicit-provider loader with synchronization, validation, and platform loading; successful providers remain loaded. |
| `runtime/library.zig` | Defines this library's runtime ABI and validates its 40 functions, 15 writable globals, and initialized binary64 constants. |
| `runtime/graph.zig` | Wires the loader, library descriptor, generated dispatch, and namespaced synchronization into the runtime module. |
| `runtime/generate.zig` | Generates wrappers and data accessors from Zig's translated header output, avoiding handwritten ABI signatures. |
| `runtime/sync.h` | Declares prefixed lock, wait, wake, and thread-identity functions so loader instances do not share symbols accidentally. |
| `runtime/sync.c` | Implements the prefixed synchronization with pthreads, Windows synchronization, or WASI/Emscripten no-ops. |
| `test/all.zig` | Imports each suite because the Zig test root must reference test-bearing files. |
| `test/support.zig` | Establishes the test precondition by loading an explicit provider when needed and then calling `init()`. |
| `test/predicates_test.zig` | Checks facade signs against the independent oracle without asserting unguaranteed determinant magnitudes. |
| `test/raw_surface_test.zig` | Exercises the raw C routines and globals that have no typed facade wrapper. |
| `test/expansion_test.zig` | Tests the published expansion-arithmetic routines and their zero-elimination behavior. |
| `test/exact_oracle.zig` | Adds an arbitrary-precision integer oracle independent of the C filters and error bounds. |
| `examples/smoke.zig` | Adds a deterministic runnable example for the facade and native library. |
| `consumer/build.zig.zon` | Adds a local path dependency on this package so downstream resolution needs no published release. |
| `consumer/build.zig` | Builds an outside-style executable through `dep.module("predicates")` and forwards the linkage and runtime options. |
| `consumer/src/main.zig` | Checks hand-computed predicate signs and a raw expansion routine through the published API. |

## Build graph

- `build.zig` compiles the unchanged C source with `-std=gnu17`, `-ffp-contract=off`, and `-fno-fast-math`; these preserve its K&R definitions and separate-rounding arithmetic.
- The package module and native artifact are both named `predicates`. Static linkage is the default; `-Dlinkage=dynamic` selects a shared artifact.
- `-Druntime=true` independently routes facade calls through a generated dispatch table. The native artifact is still built and installed, but is not linked into that facade; a provider must export the functions and mutable globals from the same image.
- There is no system-library option: upstream provides neither an installed library nor a stable header/ABI pairing to select.
- `build.zig` installs the artifact, `include/predicates.h`, a generated `lib/pkgconfig/predicates.pc`, and the licence/provenance files. `package.nix` reuses that layout; `flake.nix` and `devenv.nix` call the same derivation, which builds for the native platform only.
- The locked nixpkgs revision provides Zig 0.16.0 only; the Nix outputs require a revision that provides Zig 0.17.0.
- The cross-target `check` compiles and links the C library, facade, tests, and example; it does not run cross-built binaries. Cross-target graphs use private modules so target-specific modules do not overwrite the public module registration.
- Explicit `check` targets retain the requested target query. The runtime generator uses Zig 0.17's lowercase `.debug` optimization tag.

## Platform and caller boundaries

- `random()` is POSIX and is called by six published helpers, so the C library needs libc. Windows targets are refused before compilation; Windows does not provide `random()`, and a PE/COFF shared library would also need explicit export declarations absent from the upstream source.
- The compile/link check supports `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `riscv64-linux-gnu`, and `wasm32-wasi`. The WASI concurrency test returns `error.SkipZigTest` because that target has no threads.
- Call `predicates.init()` before any facade routine or constant accessor. It runs `exactinit()` once and publishes the initialized globals; direct calls through the raw C namespace retain upstream's unguarded contract.
- Facade predicates reject NaN and infinity with `error.NonFiniteCoordinate`. Finite extreme coordinates are not range-checked: subnormal products can underflow before exact fallback, and overflow can form `inf - inf`; no result is claimed beyond the source-supported range. Upstream guarantees the sign, not determinant magnitude.
- `doublerand`'s comment claims an exponent range of `[0, 511]`, but its loop compounds multipliers through `2^512`; the source-derived result can reach `2^53 * 2^513` and be negative, so that comment is not a range contract.
