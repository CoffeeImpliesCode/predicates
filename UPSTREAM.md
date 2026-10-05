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

> **Ordering constraint on this file.** `tools/check-provenance.sh`, and the CI
> provenance job that mirrors it, take the *first* run of 64 hexadecimal digits
> in this file and compare it with the digest of `src/predicates.c`. The SHA256
> row above must therefore stay the first 64-hex-digit string in this document.
> Nothing that looks like a digest may be inserted above it.

The file is stored here as `src/predicates.c`. It was fetched from the canonical
URL above, and the SHA256 in the table is what the copy in this tree hashes to
— recomputed during this documentation pass over the 171536 bytes present, not
transcribed from elsewhere. The same pass re-derived the MD5, the byte count and
the line count, and all four matched the values recorded here; none of them is
copied from a second source that could agree with itself. `tools/check-provenance.sh`
recomputes the SHA256 again on demand, and CI runs it on every commit, so the
table and the compiled file cannot drift apart unnoticed. The digest states
what this repository contains; it is not a promise about what the remote serves
at some later moment.

## What upstream is

One C file. Not a package, not a library with a build system: a single
translation unit intended to be dropped into a project and compiled with the
optimizer on. Its prototypes live in comment blocks at the top of the file
rather than in a header, and the author says so explicitly. `src/predicates.c`
is that file and nothing else.

What upstream does **not** ship is recorded here as precisely as what it does,
because each absence forced a decision in this fork:

| Absent upstream | What this fork did about it |
|---|---|
| A public header | `include/predicates.h`, transcribed from the prototypes in the file's own comment blocks. Nothing invented, nothing omitted. |
| A build system, or any documented compile line | `-std=gnu17 -ffp-contract=off -fno-fast-math` are stated in `build.zig` as correctness requirements. Upstream states them in prose and leaves them to the caller. |
| A licence file | The dedication in the file header is the grant. `NOTICE.md` reproduces it; no `LICENSE` is manufactured. |
| A README | There is no upstream README, so there is no `README.upstream.md` in this repository and `README.md` is this fork's own document from first line to last. See the next section. |
| CI or any continuous-integration configuration | `.github/workflows/verify.yml` is written for this fork. No upstream workflow was retargeted, because none exists. |
| A version, tag or release series | The only revision identifier available is the date in the header. The package version `0.1.0` in `build.zig.zon` is this fork's own and means nothing upstream. |

### The exported surface, as a completeness cross-check

`src/predicates.c` publishes 40 functions and 15 mutable globals.
`include/predicates.h` declares exactly those 40 and exactly those 15. Both
numbers were obtained by scanning the comment-stripped source, and they agree
in both directions: no definition is undeclared and no declaration is undefined.
This independently reproduces the "forty old-style definitions" that
`FORK-NOTES.md` section 21 arrived at by a different route, which is worth
recording because the two counts were not derived from each other.

The full inventory, with line numbers, is in `NOTICE.md`. The three debug
printers upstream ships commented out (`doubleprint`, `floatprint`,
`expansion_print`) are not part of that 40: they are not compiled, and the file
links without them.

## The per-file baseline

`UPSTREAM-BASELINE.sha256` is the machine-checkable record of every upstream byte
this package carries, one SHA-256 per path, with the pin, the derivation and the
counts in its own header. It is verified from the repository root by

```sh
tools/check-provenance.sh
```

which the `provenance` CI job runs. The record is one manifest line long, and
that is the whole of the upstream scope: one algorithm source, no header, no
internal header, no test, no test data, no generated-table input or generator, no
data file, no vendored third-party file, no build file, and no licence file. The
grant is inside the C file's own header, so the single entry covers the licence
text as well as the code.

One line would be a weak record on its own, because it cannot say whether the
path set is still complete. So the record also lists all 39 fork-owned paths
this package carries alongside it, and the gate fails on any carried path that
is neither in the manifest nor declared fork work. That is what makes the claim
checkable in both directions: a new file cannot appear under `src/` or anywhere
else without a decision, and a declared file that has gone is a stale record
rather than a silent pass. The gate also holds this document and the record to
the same digest, the same MD5, the same revision date and the same canonical URL.

Every value in the record was taken from a fresh fetch of the canonical URL on
2026-10-04 rather than from this working tree; the exact commands are in the
record's header. The fetched file is byte-identical to the one this package
compiles, and its SHA-256, MD5, size (171536 bytes) and line count (4262) are the
four values the table at the top of this document already carried.

There is no divergence from the pin to record, because the C is never patched.
`README.upstream.md` is recorded as a path that must not exist: the canonical
distribution ships no README, so manufacturing one under that name would create
a record of upstream bytes that do not exist. `sha256sum -c
UPSTREAM-BASELINE.sha256` is a valid but narrower check, because it verifies the
carried bytes and nothing about completeness.

## There is no upstream README to preserve

This is stated as its own section because the rest of this project's
documentation set preserves an upstream README where one exists, and its
absence here would otherwise look like a missing file.

The canonical distribution is a single C file with no README of any kind, so
there are no upstream bytes to preserve separately, no `README.upstream.md`, and
no digest for one. `README.md` in this repository is fork-authored from end to
end. It must not be described as upstream in any form, in any file, and it must
not be copied under another name to manufacture a record that does not exist.

## Import mechanism

There is no upstream Git history to import, and no upstream release tarball.
The CMU copy is served from an AFS directory, not a repository, so there is no
commit, tag or revision identifier to record.

The import is therefore a plain file fetch with a recorded checksum:

```
curl -sSfL -o src/predicates.c \
  https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c
sha256sum src/predicates.c   # must equal the SHA256 above
```

`tools/check-provenance.sh` is that check as an executable file. Re-syncing
means fetching again and checking the checksum. If the checksum moves, the file
changed and this table, `NOTICE.md` and `CHANGELOG.md` all need a new entry.
Nothing in this repository needs re-editing beyond that, because the C is never
patched: see below.

## The C is never patched

`src/predicates.c` is byte-identical to upstream and stays that way. Everything
this fork needed on top of it — a header, a build, a facade, tests, an example,
a Nix package — is a new file alongside it. That is a deliberate constraint
rather than an accident: a 4262-line file of error-free transformations is not
something to carry a merge conflict in, and keeping it pristine means the
checksum above is a complete statement of what was compiled.

Three upstream properties decide whether this file compiles at all. Two are
handled at the build level; the third is a platform limit and is not.

* The K&R function definitions require C17 or earlier; `-std=gnu17` pins that
  rather than taking clang's default.
* Contraction and fast-math must be off or the predicates stop being robust;
  `-ffp-contract=off` and `-fno-fast-math` are passed on every compile.
* The file calls `random()`, which is POSIX and not ISO C, from the six
  random-value helpers (`doublerand`, `narrowdoublerand`,
  `uniformdoublerand`, `floatrand`, `narrowfloatrand`, `uniformfloatrand`) at 13
  call sites in total. Those six share one translation unit with the predicates,
  so a C library without `random()` cannot build the file at all, and this fork
  has no flag that changes that. mingw-w64 does not provide it, which is why
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