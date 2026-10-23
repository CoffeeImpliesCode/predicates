# Package entry points share package.nix. The dev shell contains tools only.
# SPDX-License-Identifier: LicenseRef-PublicDomain

{
  description = "Shewchuk's adaptive-precision geometric predicates, packaged for Zig 0.17";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
  };

  outputs = { self, nixpkgs }:
    let
      # Exclude Windows because upstream calls POSIX random().
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let mk = linkage: pkgs.callPackage ./package.nix {
          inherit linkage;
          zig = pkgs.zig_0_17;
        };
        in
        {
          static = mk "static";
          # Artifact name "shared" selects Zig's dynamic linkage.
          shared = mk "dynamic";
          default = mk "static";
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.zig_0_17 pkgs.gnumake pkgs.pkg-config ];
        };
      });
    };
}