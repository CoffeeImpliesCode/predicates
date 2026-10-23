# Package entry points share package.nix. The dev shell contains tools only.
# SPDX-License-Identifier: LicenseRef-PublicDomain

{
  description = "Shewchuk's adaptive-precision geometric predicates, packaged for Zig 0.16";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
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
          zig = pkgs.zig_0_16;
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
          packages = [ pkgs.zig_0_16 pkgs.gnumake pkgs.pkg-config ];
        };
      });
    };
}