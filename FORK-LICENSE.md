# Fork licence

Terms for the material **this fork wrote**. `NOTICE.md` holds the file
inventory and `UPSTREAM.md` the source provenance.

## The native file

`src/predicates.c` is Jonathan Richard Shewchuk's file, dated May 18, 1996,
fetched from the canonical Carnegie Mellon URL and never edited. Its own header
states its terms:

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

That text is the grant. Upstream ships no `LICENSE` file, and none is
manufactured here; `NOTICE.md` reproduces the notice so a reader does not have
to open C source to find it. The file ships as fetched, and `UPSTREAM.md` records
the SHA-256 of the copy in this repository.

## The fork-authored files

Every other file in this repository — build files, the aggregate header, the
Zig facade, the runtime-loading route under `runtime/`, the tests, the example,
the consumer package, the Nix packaging and this documentation — was written for
this fork. `src/predicates.c` is the only file that is not.

**These fork-authored files are released into the public domain, matching the
primary upstream term of this project.**

### Authority

The repository owner authorized per-project licensing for fork-authored
additions as part of the SDK contract migration, with terms chosen to match each
project's primary upstream terms. That direct authorization is the basis recorded
here. No copyright holder is named, because no source in this repository or
upstream names one.

### SPDX identifier

`LicenseRef-PublicDomain`

A custom SPDX reference: no standardised identifier names a bare public-domain
dedication, and `CC-PDDC` denotes a Creative Commons instrument that was never
granted here. The identifier appears in the SPDX headers of the fork-authored
build, packaging, runtime-route and test files: every file in `runtime/`, and
among the tests `test/support.zig` and `test/raw_surface_test.zig`.

The identifier names the terms above; it is not a condition of them. A
fork-authored file with no SPDX header of its own — `src/root.zig` and
`include/predicates.h` are both in that position — is released on exactly the
same terms as one that carries the identifier, and `NOTICE.md` is the inventory
that says which files exist.

### Scope limits

* It does not re-license `src/predicates.c`, which keeps the terms quoted above.
* It does not attribute any fork-authored file to Shewchuk or to Carnegie Mellon
  University, and claims no permission from them over it.
* It does not reach the compiled output's link metadata, a downstream
  consumer's own code, or anything outside this repository.
* The Nix derivation republishes these same files under these same terms.

## Material carried but not authored here

None. This repository vendors no third-party code, no generated table, no
downloaded header and no external data file, so there is no per-file licence
exception to enumerate. The canonical distribution also ships no CI, so
`.github/workflows/verify.yml` is this fork's own and falls under this file.

`include/predicates.h` transcribes upstream's function names, parameter types
and return types from the prototype comments in `src/predicates.c`. That
interface text is upstream material under the grant quoted above; the header
itself is this fork's file.