# Shared package derivation for the flake and devenv.
# SPDX-License-Identifier: LicenseRef-PublicDomain

{ lib
, stdenv
, zig
, linkage ? "static" # Zig's std.builtin.LinkMode spelling; .static is native policy
, optimize ? "ReleaseSafe"
}:

# This derivation supports native builds only.
assert stdenv.hostPlatform.system == stdenv.buildPlatform.system
  || throw "predicates builds natively: hostPlatform and buildPlatform differ";

let
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
  # Run the build during installation with the selected package flags.
  dontBuild = true;

  nativeBuildInputs = [ zig ];

  # Upstream calls POSIX random(), so consumers need libc.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the source tree.
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
    # Windows lacks POSIX random(), which upstream calls.
    platforms = lib.platforms.unix;
  };
}