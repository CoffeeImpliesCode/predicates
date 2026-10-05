# cross-test settings profile for predicates.
#
# `cross-test` looks for this file at the root of the project it is run from
# (or names it with --profile; --no-profile ignores it). It is trusted Bash that
# the harness `source`s, so this file is *settings only*: ordinary variable
# assignments and nothing else. No command runs, no compiler is probed, and no
# path in here names a host.
#
# There is deliberately no CROSS_MATRIX. The published 53-platform Zig 0.16
# Tier 1/2 table is the matrix this package is checked against, and a matrix
# named here would replace it. There is no TARGETS array either, for the same
# reason: a subset selected here would narrow the run rather than add to it.
# Both belong on the command line, where --targets selects from the active
# matrix and never adds to it.
#
# CROSS_BUILD_STEP stays the standard `test` step, which is what this profile
# states explicitly. There are no `cross_build_command` / `cross_artifact`
# hooks here, so the harness keeps its standard Zig-build mode and runs
# `zig build test -Dtarget=TARGET` per target with a fresh cache. What that
# means for a given target is the harness's decision, not this package's: a
# host target runs, a foreign target runs under whatever executor the harness
# detects (QEMU user mode, Wine, wasmtime), and a foreign target with no
# executor is reported as build-only coverage -- compiled, never executed, and
# never counted as a pass. `build.zig` gives the test binary a Run step for
# every target, which is what leaves that choice open.
#
# No `-Dlinkage` is passed here, so each cell builds the static artifact this
# package has always delivered. That is a statement about this profile, not a
# limit the harness imposes: `-Dlinkage` is an ordinary build option and a
# separate run with it appended exercises the shared variant on whichever
# targets the matrix selects.
#
# A target graph compiles one translation unit, `src/predicates.c`, and
# translates `include/predicates.h` beside the facade and the test root. There
# is no fixture corpus and no data file to read at test time, so the default
# per-test timeout is the binding constraint rather than corpus size; the
# bounds below are the standard ones from the sibling profiles, kept so a
# loaded host is not mistaken for a slow one.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=3600
CROSS_TIMEOUT=1800