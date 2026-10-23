# Zig facade API

## Initialization

```zig
predicates.init();
```

Call `init()` before any facade predicate or initialization-constant accessor. It runs `exactinit()` once per process; concurrent callers wait for completion, and later calls do no work. Predicate and constant-accessor calls panic before native access if initialization is missing, including the `*fast` variants. Predicate calls can run concurrently after initialization. `isInitialized()` reports whether this module observed completion.

## Types and errors

```zig
pub const Point2 = struct { x: f64, y: f64 };
pub const Point3 = struct { x: f64, y: f64, z: f64 };
pub const Sign = enum { negative, zero, positive };
```

Points are passed by value; predicates allocate nothing and transfer no ownership. Coordinates are checked when a predicate is called. `Sign.negate()` swaps positive and negative and preserves zero. Facade predicates return `Error!f64`; sign wrappers return `Error!Sign`. `Error.NonFiniteCoordinate` is returned for any NaN or infinite coordinate before calling C, in every optimization mode.

## Robust predicates

| Function | Arguments | Positive means |
|---|---|---|
| `orient2d` | three `Point2` | `pa`, `pb`, `pc` are counterclockwise |
| `orient3d` | four `Point3` | `pd` is below the oriented plane through the first three |
| `incircle` | four `Point2` | `pd` is inside the circle through the first three |
| `insphere` | five `Point3` | `pe` is inside the sphere through the first four |

`incircle` requires its first three points counterclockwise. `insphere` requires its first four points ordered so `orient3d` on them is positive. These are oriented predicates: reversing the defining-point orientation reverses the sign.

Each predicate has a `*Sign` wrapper (`orient2dSign`, `orient3dSign`, `incircleSign`, `insphereSign`) and an upstream `*fast` counterpart. `*fast` has no error analysis and may return the wrong sign near degeneracy. All variants still require `init()`.

The adaptive sign guarantee applies only to well-scaled finite inputs whose filter products remain within the binary64 range. The facade does not enforce a scale bound. Outside it, `Sign.zero` can also represent an underflowed zero or an overflowed NaN. Returned magnitudes are upstream determinant approximations; the facade guarantees the sign, not the magnitude.

## Initialization constants

These accessors require `init()` and read the initialized values from the active provider:

| Function | Result |
|---|---|
| `epsilon()` | `f64` roundoff unit |
| `splitter()` | `f64` Dekker splitting factor |
| `resultErrorBound()` | `f64` result error bound |
| `orientationErrorBounds()` | `[3]f64` 2D orientation bounds A/B/C |
| `orientation3dErrorBounds()` | `[3]f64` 3D orientation bounds A/B/C |
| `incircleErrorBounds()` | `[3]f64` in-circle bounds A/B/C |
| `insphereErrorBounds()` | `[3]f64` in-sphere bounds A/B/C |

## Runtime provider API

`runtime_loaded` is a compile-time boolean. In a runtime-loaded build, `LoadSource` accepts an absolute `.path` or a `.system` basename; paths are not converted to names, and there is no implicit fallback.

```zig
if (comptime predicates.runtime_loaded) {
    try predicates.load(.{ .path = provider_path });
}
```

The provider must match the target's C ABI, export all declared functions and globals, and use IEEE binary64. Preserve the source's arithmetic with optimization enabled, fused contraction disabled, no fast-math, and no excess precision. These build properties cannot be validated from a loaded binary.

`load()` resolves all functions and globals, runs the candidate's `exactinit()`, and validates its binary64 constants before publication. Call `init()` before using the facade after loading. A successful handle is retained for the process lifetime; there is no unload or reset. Repeating the same request is idempotent; a different request returns `ProviderMismatch`. Failed loads publish nothing and can be retried explicitly. Same-request concurrent callers share an attempt; recursive loading returns `ReentrantLoad`.

`LoadError` includes `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, and `ReentrantLoad`. `loadedSource()` returns the retained successful request, or null before success and in a linked build. Calling `load()` in a linked build panics.

## Raw C namespace

```zig
const c = predicates.c;
```

`c` exposes the unmodified translated C surface: expansion arithmetic, `*exact`, `*slow`, `*adapt`, random helpers, `exactinit()`, and the fifteen globals. Direct calls bypass the facade's initialization and non-finite checks; in a runtime-loaded build, load a provider first. Call raw `exactinit()` once before raw predicate calls; it is not synchronized, so concurrent calls race. The `*exact` and `*slow` predicates take point arguments and use local scratch; `*adapt` helpers take caller-computed error bounds.