# Fork licence

Terms for fork-authored files in this repository.

## Upstream file

The unchanged `src/predicates.c` header states these terms:

```
  May 18, 1996

  Placed in the public domain by
  Jonathan Richard Shewchuk
  School of Computer Science
  Carnegie Mellon University
  5000 Forbes Avenue
  Pittsburgh, Pennsylvania  15213-3891
  jrs@cs.cmu.edu
```

## Fork-authored files

Every other repository file is fork-authored and released into the public domain under the terms above; only `src/predicates.c` is upstream.

SPDX identifier: `LicenseRef-PublicDomain`. It appears on fork-authored build, packaging, runtime and test files, including all of `runtime/`, `test/support.zig` and `test/raw_surface_test.zig`. `src/root.zig` and `include/predicates.h` have no SPDX header but share these terms.

`include/predicates.h` transcribes upstream function names, parameter and return types from comments in `src/predicates.c`. The interface text is upstream material under its quoted grant; the header itself is fork-authored.

## Scope limits

- The grant does not relicense `src/predicates.c`, which retains its quoted terms.
- It does not attribute fork-authored files to Shewchuk or Carnegie Mellon University, or claim their permission.
- It does not cover compiled output link metadata, downstream consumer code or material outside this repository.
- The Nix derivation republishes covered files under the same terms.
- No other third-party code, generated tables, downloaded headers or external data files are carried.
