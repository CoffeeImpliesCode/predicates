# Canonical development environment for the predicates SDK.
#
# `packages` holds tools only: entering a shell must not require building this
# SDK. The SDK itself is reached through the lazy `outputs` below, built on
# demand with `devenv build outputs.static` / `outputs.shared`.
#
# Every task body reaches this SDK's own directory before it runs anything,
# either by changing to it or by handing that path to a tool which resolves its
# own root: devenv runs a task as a generated shell program that inherits the
# working directory of the project the environment was entered from, and that
# project is not this SDK: it holds `.devenv/` and `devenv.lock` and none of
# `build.zig`, `consumer/` or `tools/`. `./.` is relative to the module that
# writes it, so it is this module's own directory whatever the caller started
# from. `$DEVENV_ROOT` is never used to find it: that names the project
# directory, which is the thing that is already wrong.
#
# A command that installs a delivery passes `--prefix` to a subdirectory of the
# local cache the caller exported, so a delivery never lands in the working
# tree. `build.zig` writes its whole install closure - the artifact, the public
# header, the generated pkg-config file and the three licence records -
# wherever `--prefix` points, so the prefix is an input that graph honours
# rather than a rewrite of its layout, and a `--prefix` the caller passed on
# the command line is passed through untouched rather than overridden.
#
# Every Zig build task runs chooseCaches itself and supplies fixed -j8 before
# any forwarded arguments. devenv 2.4 tasks run cannot forward caller flags;
# "$@" is retained for direct invocation of a generated task program.
#
# Outputs and flake.nix call the same ./package.nix.
#
# devenv.lock is not written here: the driver owns locks.
#
# No devenv, nix or zig command has been run against this revision of this
# file. Every statement about the build graph is SOURCE-CONFIRMED by reading
# `build.zig`, `consumer/build.zig` and `package.nix`; the tasks, the shell and
# the derivations are PENDING-VERIFICATION.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain

{ pkgs, lib, ... }:

let
  zig = pkgs.zig_0_16;
  mk = linkage: pkgs.callPackage ./package.nix { inherit linkage; zig = zig; };

  # This SDK's own directory, and the two paths below it, each as one shell
  # word. `./.` is relative to the module that writes it, so it resolves to the
  # directory holding this file rather than to the caller's working directory.
  # `builtins.toString` and not a bare path interpolated into a string: a path
  # that keeps its string context can be copied into the read-only Nix store,
  # and a task that then changed into that copy would be building somewhere it
  # cannot write. `lib.escapeShellArg` is the Nix library's own shell quoting,
  # so quoting each path once here means no body below re-quotes one by hand.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);
  consumerDir = lib.escapeShellArg (builtins.toString ./. + "/consumer");
  provenanceScript = lib.escapeShellArg (builtins.toString ./. + "/tools/check-provenance.sh");

  # Defaults for the two Zig caches, and never overrides: a value the caller
  # already exported wins and is never overwritten or unset here. The locations
  # are read out of the environment when the shell is entered, not interpolated
  # at evaluation time, so nothing in this file can name a path on the machine
  # that evaluates it. `$XDG_CACHE_HOME` is where a cache belongs by the Base
  # Directory Specification and `$TMPDIR` is the host's scratch policy; a caller
  # that set neither is told so on stderr rather than handed a location this
  # file does not get to invent, and the tasks that install then refuse rather
  # than write a delivery into the checkout.
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

  # The one delivery body both linkage variants run. A default `zig build`
  # installs: `build.zig:679` puts the artifact behind the install step,
  # `build.zig:689-691` the generated pkg-config file, `build.zig:703-705` the
  # three licence records and `build.zig:722` the smoke program's compilation.
  # A task that ran the default step with no `--prefix` of its own therefore
  # wrote a delivery tree into this checkout, on a filesystem that may be a
  # network mount, so the prefix is a subdirectory of the local cache instead.
  # A `--prefix` the caller passed on the command line is detected and used
  # unchanged, and every other argument reaches `zig build` as written.
  #
  # `test` (`build.zig:744`), `smoke` (`build.zig:730-731`), `check`
  # (`build.zig:758-781`) and the consumer package do not depend on the install
  # step - `build.zig:724-727` says so for `smoke`, and the consumer's `run`
  # step (`consumer/build.zig:78-79`) installs nothing either - so those bodies
  # carry no prefix, and none of them needs one to keep the tree clean.
  deliveryBuild = linkageFlag: subdirectory: ''
    cd ${sdkRoot}
    ${chooseCaches}
    prefix="''${ZIG_LOCAL_CACHE_DIR:?not set; export it, or enter the devenv shell, which fills it from XDG_CACHE_HOME or TMPDIR}/predicates/${subdirectory}"

    # A caller that named its own prefix keeps it: `--prefix P` and `-p P` are
    # two spellings of one option, and `--prefix=P` is a third. Zig takes the
    # last `--prefix` on the command line, so passing ours first and the
    # caller's arguments after it would also work; it is detected here instead
    # because that does not depend on which of the two wins.
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
      assertion = zig.version == "0.16.0";
      message = "predicates requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  outputs = {
    static = mk "static";
    shared = mk "dynamic";
    default = mk "static";
  };

  # Defaults for the two Zig caches when the caller named none, and nothing
  # else. `chooseCaches` is the same text the Zig build tasks run, so the
  # interactive shell and `devenv tasks run` cannot disagree about where a
  # delivery prefix lands.
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
      # The script resolves the repository from its own `$0`
      # (`tools/check-provenance.sh:28`), so this SDK's path is handed to it
      # directly instead of being assumed to be the working directory.
      exec = ''
        cd ${sdkRoot}
        bash ${provenanceScript} "$@"
      '';
    };
  };
}
