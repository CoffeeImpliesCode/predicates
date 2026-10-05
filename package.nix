# Source-only derivation for the predicates SDK. Consumed by flake.nix and
# devenv.nix so the two entry points cannot describe different builds.
#
# The build graph owns the C flags, the source list and the entire installed
# layout — artifact, header, pkg-config file and licence records. This file
# selects optimize, cpu and linkage and points the prefix at the output; it
# installs nothing itself.
#
# No lock file is created here. The driver owns locks.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain

{ lib
, stdenv
, zig
, linkage ? "static" # Zig's std.builtin.LinkMode spelling; .static is native policy
, optimize ? "ReleaseSafe"
}:

# No -Dtarget is passed, so a Nix cross package would build this graph for the
# build system's own host. Compare platforms directly: builtins.currentSystem is
# impure and unusable in evaluation.
assert stdenv.hostPlatform.system == stdenv.buildPlatform.system
  || throw "predicates builds natively: hostPlatform and buildPlatform differ";

let
  # Build outputs, developer state and version control, at any depth. Named
  # rather than allow-listed so a later source file needs no edit here.
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _type:
      let name = builtins.baseNameOf (toString path);
      in !(lib.elem name [
        ".git" ".jj" ".direnv" ".devenv" ".devenv.flake.nix"
        ".zig-cache" "zig-cache" "zig-out" "zig-pkg"
      ] || name == "result" || lib.hasPrefix "result-" name);
  };
in

stdenv.mkDerivation {
  pname = "predicates";
  version = "0.1.0";

  inherit src;

  strictDeps = true;
  dontPatch = true;
  dontConfigure = true;
  # This derivation has one real phase. Leaving the hook's build phase enabled
  # would compile the graph once with default flags and again at install.
  # dontInstall is deliberately NOT set: that would disable the phase below.
  dontBuild = true;

  nativeBuildInputs = [ zig ];

  # src/predicates.c calls POSIX random() from six published helpers, so the
  # installed library really does need libc. Nothing else is propagated; the
  # file calls nothing from libm, which is why the generated .pc has an empty
  # Libs.private.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  # Verification is the driver's. A check phase here would be a gate nobody ran
  # with a receipt; README.md lists the commands that do verify this package.
  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Nix supplies TMPDIR; the caches belong under it and outside $src.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    zig build install \
      -j"''${NIX_BUILD_CORES:-1}" \
      --prefix "$out" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  enableParallelBuilding = true;

  meta = {
    description = "Shewchuk's adaptive-precision geometric predicates (orient2d, orient3d, incircle, insphere)";
    license = lib.licenses.publicDomain;
    # x86_64-windows-gnu is excluded because src/predicates.c calls POSIX
    # random(), which mingw-w64 and the UCRT do not provide. See README.md.
    platforms = lib.platforms.unix;
  };
}