# Flake interface for the predicates SDK. Portable counterpart to devenv.nix;
# both call ./package.nix, so the two cannot describe different builds.
#
# devenv.nix is the canonical development environment. This flake exists so the
# SDK can be built off this host, and its devShell is tools-only parity.
#
# flake.lock is not written here: the driver owns locks.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain

{
  description = "Shewchuk's adaptive-precision geometric predicates, packaged for Zig 0.16";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs = { self, nixpkgs }:
    let
      # No Windows system: src/predicates.c calls POSIX random(), which mingw-w64
      # and the UCRT do not provide. README.md carries the boundary.
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let mk = linkage: pkgs.callPackage ./package.nix {
          inherit linkage;
          zig = pkgs.zig_0_16;
        };
        in
        {
          static = mk "static";
          # "shared" names the artifact; the flag is Zig's -Dlinkage=dynamic.
          shared = mk "dynamic";
          default = mk "static";
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.zig_0_16 pkgs.gnumake pkgs.pkg-config ];
        };
      });
    };
}