# predicates

Shewchuk's adaptive-precision geometric predicates, packaged for Zig 0.17.0.
Upstream is the May 18, 1996 source revision; it has no tag or release series. This fork's package version is `0.1.0`.

## Source deviations from upstream

| Path | Change |
|---|---|
| `src/predicates.c` | Unmodified canonical source; algorithms and C ABI remain upstream's. |
| `include/predicates.h` | Added because upstream ships no header; declares 40 functions and 15 globals without rewriting the K&R definitions. |
| `src/root.zig` | Added typed facade with once-only initialization, sign wrappers, and checked non-finite inputs. |
| `runtime/` | Added optional runtime dispatch for one explicit provider. |
| `test/`, `examples/`, `consumer/` | Added tests, deterministic example, and a separate dependent package. |

`UPSTREAM.md` records the source identity and digest. `NOTICE.md` and `FORK-LICENSE.md` record licence scope.

## Build deviations

Upstream is one C translation unit with no header or build system. The Zig build translates the added header, builds the C artifact, and exposes the `predicates` module with that artifact carried as a dependency.

The C source is compiled with `-std=gnu17` for its K&R definitions, `-ffp-contract=off` to preserve separately rounded arithmetic, and `-fno-fast-math` to retain the error analysis. It calls POSIX `random()`, so libc is required; it does not call libm. No system-library mode is provided: the package builds the canonical source.

`-Dlinkage` selects the installed native artifact. The default is `libpredicates.a`; `-Dlinkage=dynamic` produces `libpredicates.so`, with no soname series. Both variants install `include/predicates.h` and `lib/pkgconfig/predicates.pc`. Nix entry points use the same `package.nix` and build graph.

`-Druntime` is independent of `-Dlinkage` and leaves the native artifact built and installed. Runtime-loaded programs must choose a provider explicitly.

## Support matrix

These target triples are in the build graph's compile/link matrix. Runtime loading is also unavailable on Emscripten and freestanding targets.

| Target | Build graph |
|---|---|
| `x86_64-linux-gnu` | Accepted |
| `aarch64-linux-gnu` | Accepted |
| `aarch64-macos-none` | Accepted |
| `riscv64-linux-gnu` | Accepted |
| `wasm32-wasi` | Accepted; runtime loading is unavailable |
| Windows, including `x86_64-windows-gnu` | Refused before compilation: upstream calls POSIX `random()`, and PE/COFF shared libraries also need export declarations absent from the source. |

## Consumption

### Zig dependency

This checkout is not published. Use a relative path in `build.zig.zon`:

```zig
.dependencies = .{
    .predicates = .{ .path = "../predicates" },
},
```

Then import the module; it carries the native library, so no separate link step is needed:

```zig
const dep = b.dependency("predicates", .{ .target = target, .optimize = optimize });
exe_mod.addImport("predicates", dep.module("predicates"));
```

Set `.link_libc = true` on the consumer module. The facade module name is `predicates`; `dep.artifact("predicates")` returns the native artifact for a C consumer. The installed `predicates.h` is on its include path. The generated pkg-config file is `lib/pkgconfig/predicates.pc` (`-I${includedir}`, `-L${libdir} -lpredicates`; no private libm dependency).

### Build options

| Option | Default | Effect |
|---|---|---|
| `-Dlinkage=static\|dynamic` | `static` | Selects the native artifact; `static` does not promise a wholly static executable. |
| `-Druntime=true\|false` | `false` | Selects loader dispatch or direct linking; independent of `linkage`. |
| `-Dtarget=<triple>` | Zig host target | Selects a target; Windows targets are refused. |
| `-Doptimize=<mode>` | Zig default | Uses Zig's standard optimization option. |

Zig tests read `PREDICATES_TEST_PROVIDER`; the smoke and consumer programs accept `--provider <path>`. See `README.zig.md` for runtime loading and facade contracts.

### Nix

The Nix outputs require a Nixpkgs revision that provides Zig 0.17.0. The checked-in lock does not provide it.

```sh
nix build .#static
nix build .#shared
```

Both variants use the same source-only derivation and install layout.
