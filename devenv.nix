# Development environment and tasks share package.nix with the flake.
# SPDX-License-Identifier: LicenseRef-PublicDomain

{ pkgs, lib, ... }:

let
  zig = pkgs.zig_0_17;
  mk = linkage: pkgs.callPackage ./package.nix { inherit linkage; zig = zig; };

  # Resolve the SDK's absolute path from this module, not the caller's directory.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);
  consumerDir = lib.escapeShellArg (builtins.toString ./. + "/consumer");
  provenanceScript = lib.escapeShellArg (builtins.toString ./. + "/tools/check-provenance.sh");

  # Preserve exported Zig caches; otherwise use XDG_CACHE_HOME or TMPDIR.
  chooseCaches = ''
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        predicates_cache_root="$XDG_CACHE_HOME"
      elif [ -n "''${TMPDIR:-}" ]; then
        predicates_cache_root="$TMPDIR"
      else
        predicates_cache_root=
      fi

      if [ -n "$predicates_cache_root" ]; then
        : "''${ZIG_GLOBAL_CACHE_DIR:=$predicates_cache_root/zig-global-cache}"
        : "''${ZIG_LOCAL_CACHE_DIR:=$predicates_cache_root/zig-local-cache}"
        export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
        mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
      else
        echo "predicates devenv: XDG_CACHE_HOME and TMPDIR are both unset and no" >&2
        echo "Zig cache location was exported, so none is chosen here. Export" >&2
        echo "ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR at approved scratch." >&2
        exit 1
      fi
      unset predicates_cache_root
    fi
  '';

  # Delivery tasks use a cache prefix unless the caller supplies --prefix.
  deliveryBuild = linkageFlag: subdirectory: ''
    cd ${sdkRoot}
    ${chooseCaches}
    prefix="''${ZIG_LOCAL_CACHE_DIR:?not set; export it, or enter the devenv shell, which fills it from XDG_CACHE_HOME or TMPDIR}/predicates/${subdirectory}"

    # Preserve a caller-supplied prefix in any Zig option spelling.
    caller_prefix=
    previous=
    for argument in "$@"; do
      case "$argument" in
        --prefix=*) caller_prefix="''${argument#--prefix=}" ;;
      esac
      if [ "$previous" = "--prefix" ] || [ "$previous" = "-p" ]; then
        caller_prefix="$argument"
      fi
      previous="$argument"
    done

    if [ -n "$caller_prefix" ]; then
      mkdir -p "$caller_prefix"
      zig build ${linkageFlag} -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
    else
      mkdir -p "$prefix"
      zig build ${linkageFlag} -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all --prefix "$prefix" "$@"
    fi
  '';
in
{
  packages = [ zig pkgs.gnumake pkgs.pkg-config ];

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "predicates requires Zig 0.17.0; nixpkgs resolved zig_0_17 to ${zig.version}";
    }
  ];

  outputs = {
    static = mk "static";
    shared = mk "dynamic";
    default = mk "static";
  };

  enterShell = ''
    ${chooseCaches}

    echo "predicates 0.1.0 - Shewchuk's predicates, canonical C unmodified"
    echo "  compiler:  zig ${zig.version}"
    echo "  sdk root:  ${sdkRoot}"
    echo "  gates:     devenv tasks run sdk:build | sdk:test | sdk:test-release-safe"
    echo "             | sdk:smoke | sdk:check | sdk:check-shared | sdk:consumer"
    echo "             | sdk:provenance"
    echo "  variant:   sdk:build-shared  (delivery prefix under ''${ZIG_LOCAL_CACHE_DIR:-unset})"
    echo "  package:   devenv build outputs.static | outputs.shared"
  '';

  tasks = {
    "sdk:build" = {
      description = "Compile the native library and the example; the delivery installs under $ZIG_LOCAL_CACHE_DIR";
      exec = deliveryBuild "" "static";
    };

    "sdk:build-shared" = {
      description = "Compile the native library as a shared object; the delivery installs under $ZIG_LOCAL_CACHE_DIR";
      exec = deliveryBuild "-Dlinkage=dynamic" "shared";
    };

    "sdk:test" = {
      description = "Run the behavioural tests";
      exec = ''
        cd ${sdkRoot}
        ${chooseCaches}
        zig build test -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
      '';
    };

    "sdk:test-release-safe" = {
      description = "Run the behavioural tests in ReleaseSafe";
      exec = ''
        cd ${sdkRoot}
        ${chooseCaches}
        zig build test -Doptimize=ReleaseSafe -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        cd ${sdkRoot}
        ${chooseCaches}
        zig build smoke -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
      '';
    };

    "sdk:check" = {
      description = ''
        Attempt all six compile-only targets. Exits non-zero on
        x86_64-windows-gnu: src/predicates.c calls POSIX random(), which
        mingw-w64 and the UCRT do not provide. See FORK-NOTES.md section 21.
      '';
      exec = ''
        cd ${sdkRoot}
        ${chooseCaches}
        zig build check -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
      '';
    };

    "sdk:check-shared" = {
      description = "Attempt all six compile-only targets against a shared object";
      exec = ''
        cd ${sdkRoot}
        ${chooseCaches}
        zig build check -Dlinkage=dynamic -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
      '';
    };

    "sdk:consumer" = {
      description = "Build and run the separate consumer package";
      exec = ''
        cd ${consumerDir}
        ${chooseCaches}
        zig build run -j8 --cache-dir "$ZIG_LOCAL_CACHE_DIR" --summary all "$@"
      '';
    };

    "sdk:provenance" = {
      description = "Check the recorded upstream digest and the licence notice";
      exec = ''
        cd ${sdkRoot}
        bash ${provenanceScript} "$@"
      '';
    };
  };
}
