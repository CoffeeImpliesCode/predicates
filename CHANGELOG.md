# Changelog

## Unreleased

- Port to Zig 0.17.0.
- Updated test, example and consumer calls to Zig 0.16's typed two-argument `std.math.ldexp` API.
- Changed the Zig dependency example to the local path used by `consumer/build.zig.zon`.
- Documented `x86_64-windows-gnu` as unsupported: upstream calls POSIX `random()` and declares no PE/COFF exports.
- Documented the extreme-exponent limits of the filtered predicates; exact signs are not guaranteed near the floating-point range limits.
- Added static and shared Nix outputs; static remains the default. Runtime-loaded builds resolve functions and mutable globals through the same provider.

## 0.1.0 - 2026-09-30

- Added the Zig `predicates` module and static library, with typed `orient2d`, `orient3d`, `incircle` and `insphere` predicates, sign and fast variants, and the raw `predicates.c` surface.
- Added `init()` to initialize upstream constants once per process and `error.NonFiniteCoordinate` for NaN or infinite facade inputs.
- Added the Zig build manifest, C declaration header and consumer package.
