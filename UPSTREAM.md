# Upstream

## Canonical source

| | |
|---|---|
| Project | Shewchuk's Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates |
| Author | Jonathan Richard Shewchuk, School of Computer Science, Carnegie Mellon University |
| Revision | May 18, 1996, the date in the file header. There is no tag or commit identifier to record: the file is served from an AFS directory, not a repository. |
| Canonical URL | <https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c> |
| Project page | <http://www.cs.cmu.edu/~quake/robust.html> |
| Technical report | CMU-CS-96-140, "Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates" |
| Licence | Public domain. The file header reads: "Placed in the public domain by Jonathan Richard Shewchuk". There is no LICENSE file to preserve because there is no licence to preserve. |
| SHA256 | `f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029` |
| MD5 | `4f199d0294b91b89f2decff591ffa305` |
| Size | 171536 bytes, 4262 lines, ASCII |

The file is stored here as `src/predicates.c`. It was fetched from the canonical
URL above, and the SHA256 in the table is what the copy in this tree hashes to
— recomputed during this documentation pass over the 171536 bytes present, not
transcribed from elsewhere. A CI job recomputes it again on every run, so the
table and the compiled file cannot drift apart unnoticed. The digest states
what this repository contains; it is not a promise about what the remote serves
at some later moment.

## What upstream is

One C file. Not a package, not a library with a build system: a single
translation unit intended to be dropped into a project and compiled with the
optimizer on. Its prototypes live in comment blocks at the top of the file
rather than in a header, and the author says so explicitly. `src/predicates.c`
is that file and nothing else.

## Import mechanism

There is no upstream Git history to import, and no upstream release tarball. The
CMU copy is served from an AFS directory, not a repository, so there is no
commit, tag or revision identifier to record.

The import is therefore a plain file fetch with a recorded checksum:

```
curl -sSfL -o src/predicates.c \
  https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c
sha256sum src/predicates.c   # must equal the SHA256 above
```

Re-syncing means fetching again and checking the checksum. If the checksum moves,
the file changed and this table, `NOTICE.md` and `CHANGELOG.md` all need a new
entry. Nothing in this repository needs re-editing beyond that, because the C is
never patched: see below.

## The C is never patched

`src/predicates.c` is byte-identical to upstream and stays that way. Everything
this fork needed on top of it — a header, a build, a facade, tests, an example —
is a new file alongside it. That is a deliberate constraint rather than an
accident: a 4262-line file of error-free transformations is not something to
carry a merge conflict in, and keeping it pristine means the checksum above is a
complete statement of what was compiled.

Three upstream properties decide whether this file compiles at all. Two are
handled at the build level; the third is a platform limit and is not.

* The K&R function definitions require C17 or earlier; `-std=gnu17` pins that
  rather than taking clang's default.
* Contraction and fast-math must be off or the predicates stop being robust;
  `-ffp-contract=off` and `-fno-fast-math` are passed on every compile.
* The file calls `random()`, which is POSIX and not ISO C, from the six
  random-value helpers (`doublerand`, `narrowdoublerand`,
  `uniformdoublerand`, `floatrand`, `narrowfloatrand`, `uniformfloatrand`).
  Those six share one translation unit with the predicates, so a C library
  without `random()` cannot build the file at all, and this fork has no flag
  that changes that. mingw-w64 does not provide it, which is why
  x86_64-windows-gnu is not a supported target. Recorded in `FORK-NOTES.md`
  section 21, with the diagnostics and the header files that settle it.

The first two are documented where they are applied, in `build.zig` and at the
top of `include/predicates.h`.

## Prior fork: recorded, not readable, not imported

The project inventory records a previously completed fork of this library at
`/home/janis/projects/foundation-predicates`. Checked again while writing this
file: that path does not exist on this host, and neither does `/home/janis`
itself, so no copy of that tree is under the account's home, downloads or
project roots. During the import, a lookup of
`CoffeeImpliesCode/foundation-predicates` returned HTTP 404 and an account-wide
repository scan found no predicates repository under any name; those two
results are recorded as they were observed at import time and have not been
re-queried since.

What follows from that is a statement about this repository, not about the
inventory entry: **no earlier work was carried forward**. This is a fresh
import from the canonical source. There is no predecessor history to preserve,
no predecessor test suite to inherit and no predecessor divergence list to
continue; nothing here was "recovered" from the earlier fork, because nothing
from it was readable. If that fork is later recovered, this section is the
first thing to correct, and the merge is a new commit rather than a
reinterpretation of this one.

## Third-party material in this repository

None. There is no vendored dependency, no generated table, no downloaded header.
Every file here except `src/predicates.c` is written for this fork.