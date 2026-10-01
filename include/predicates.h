/*****************************************************************************/
/*  Aggregate public declaration header for Shewchuk's predicates.c.         */
/*                                                                           */
/*  This header is a fork-authored addition. The canonical distribution is   */
/*  a single source file, predicates.c, with no companion header: its        */
/*  prototypes live in comment blocks at the top of that file. Consumers     */
/*  (C, and `zig build translate-c` through `pub const c = @import("c")`)     */
/*  need machine-readable declarations, so they are transcribed here.        */
/*                                                                           */
/*  No declaration below is invented. Every name, parameter list and         */
/*  return type is transcribed from the K&R definitions in src/predicates.c  */
/*  (revision of May 18, 1996), which are visible at the line numbers noted  */
/*  in FORK-NOTES.md. The definitions in src/predicates.c are NOT rewritten   */
/*  to match this header; upstream is kept byte-identical, so nothing here    */
/*  can drift the compiled behaviour. What can drift is this file, and the    */
/*  coverage for it is compilation, not a text comparison: the CI native job */
/*  compiles and links a C translation unit against the installed header and */
/*  the installed archive, calling every routine declared below and reading   */
/*  every global, so a wrong type fails to compile and a missing definition   */
/*  fails to link. The provenance job checks the upstream digest instead.     */
/*                                                                           */
/*  COMPILATION REQUIREMENTS (see FORK-NOTES.md, item 1):                    */
/*    * Compile with floating-point contraction disabled. `Two_Product` and  */
/*      `Two_Two_Diff` are error-free transformations that assume each      */
/*      multiply and each subtract is separately rounded. A fused            */
/*      multiply-add silently changes those results and the predicates stop */
/*      being robust. Pass -ffp-contract=off.                                 */
/*    * Do NOT enable fast math, finite-math-only, or any reassociation.      */
/*    * Do NOT evaluate in excess precision. On x87 this would break the     */
/*      Dekker splitting; upstream's escape hatch is to #define INEXACT      */
/*      volatile, which the fork leaves as upstream wrote it (empty).        */
/*    * Compile with the optimizer ON, as upstream requires.                 */
/*                                                                           */
/*  THREADING: `exactinit()` writes the file-scope globals `splitter`,       */
/*  `epsilon` and the error bounds. Call it exactly once, before any other   */
/*  routine. Calling it concurrently from two threads is a data race on      */
/*  those globals even though the values written are identical. The Zig      */
/*  facade in this package does not expose that hazard: its `init()` runs     */
/*  `exactinit()` under a once-guard.                                         */
/*****************************************************************************/

#ifndef FOUNDATION_PREDICATES_PREDICATES_H
#define FOUNDATION_PREDICATES_PREDICATES_H

/* Upstream hard-codes `#define REAL double`. Callers that re-declare these
   prototypes must use `double` too; the macro below exists so a caller can
   spell the coordinate type once and stay in step with the C file. */
#ifndef PREDICATES_REAL
#define PREDICATES_REAL double
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
   Initialization.

   exactinit() must run once, before any arithmetic function or geometric
   predicate. It computes `splitter` and `epsilon` for the running
   floating-point format and derives the roundoff error bounds used by the
   adaptive predicates. Before it runs, every file-scope constant is zero and
   every robust predicate returns a wrong answer.
   ------------------------------------------------------------------------- */
extern void exactinit(void);

/* -------------------------------------------------------------------------
   Debug helpers for random floating-point values.

   Present and callable in the canonical source; used only by the timing
   harness that upstream ships commented out. They call random(), which is
   POSIX rather than ISO C: that is why this library needs libc, and it is why
   a C library without random() cannot build this source at all. mingw-w64 has
   none, so x86_64-windows-gnu is not a supported target for this package.
   See README.md and FORK-NOTES.md section 21.
   ------------------------------------------------------------------------- */
extern double doublerand(void);
extern double narrowdoublerand(void);
extern double uniformdoublerand(void);
extern float floatrand(void);
extern float narrowfloatrand(void);
extern float uniformfloatrand(void);

/* -------------------------------------------------------------------------
   Expansion arithmetic.

   An expansion is an array of PREDICATES_REAL sorted from smallest to largest
   magnitude, with possible interspersed zeros. Its length is passed separately
   and must be >= 1. Every function below returns the length of the output
   expansion `h`. Those ending in _zeroelim remove zero components and are
   recommended over their counterparts.

   Aliasing rules are upstream's, not this fork's, and are noted per routine:
   upstream's comments warn that most of its macros require distinct argument
   variables.
   ------------------------------------------------------------------------- */

/* h = e + b. `e` and `h` may be the same array. */
extern int grow_expansion(int elen, PREDICATES_REAL *e, PREDICATES_REAL b, PREDICATES_REAL *h);

/* h = e + b, zero-eliminated. `e` and `h` may be the same array. */
extern int grow_expansion_zeroelim(int elen, PREDICATES_REAL *e, PREDICATES_REAL b, PREDICATES_REAL *h);

/* h = e + f, keeping zeros. `e` and `h` or `f` and `h` may be the same. */
extern int expansion_sum(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e + f, zero-eliminated, order 1. `e` and `h` or `f` and `h` may match. */
extern int expansion_sum_zeroelim1(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e + f, zero-eliminated, order 2. `e` and `h` or `f` and `h` may match. */
extern int expansion_sum_zeroelim2(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e + f, round-to-odd style fast sum. `h` cannot be `e` or `f`. */
extern int fast_expansion_sum(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e + f, fast and zero-eliminated. `h` cannot be `e` or `f`. */
extern int fast_expansion_sum_zeroelim(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e + f for expansions of nonoverlapping components. `h` cannot be e/f. */
extern int linear_expansion_sum(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e + f, linear and zero-eliminated. `h` cannot be `e` or `f`. */
extern int linear_expansion_sum_zeroelim(int elen, PREDICATES_REAL *e, int flen, PREDICATES_REAL *f, PREDICATES_REAL *h);

/* h = e * b. `e` and `h` cannot be the same array. */
extern int scale_expansion(int elen, PREDICATES_REAL *e, PREDICATES_REAL b, PREDICATES_REAL *h);

/* h = e * b, zero-eliminated. `e` and `h` cannot be the same array. */
extern int scale_expansion_zeroelim(int elen, PREDICATES_REAL *e, PREDICATES_REAL b, PREDICATES_REAL *h);

/* h = compress(e): removes zero components. `e` and `h` may be the same. */
extern int compress(int elen, PREDICATES_REAL *e, PREDICATES_REAL *h);

/* Returns an estimate of the nonoverlapping length of the expansion e. */
extern PREDICATES_REAL estimate(int elen, PREDICATES_REAL *e);

/* -------------------------------------------------------------------------
   Geometric predicates.

   Every point argument is an array of 2 or 3 coordinates in the order
   x, y (, z). No routine allocates, and no routine modifies its inputs.

   Naming, per upstream:
     <name>fast   approximate, non-robust, no error analysis.
     <name>exact  non-adaptive exact arithmetic. Slow; upstream keeps it for
                  timing and for use as a reference.
     <name>slow   another exact implementation, same purpose.
     <name>adapt  the adaptive-precision engine. Takes the caller-computed
                  error bound as an argument; it is a helper of <name>, not
                  an entry point.
     <name>       adaptive precision, robust. The routine to call.

   The unsuffixed routines return a value whose SIGN is guaranteed correct.
   Its MAGNITUDE is an approximation of a determinant, computed by scaling
   down the permanent of the filtered result. Do not read a magnitude out of
   them; read the sign.

   Callers that also use the *exact or *slow variants must initialize them
   exactly once with the same call the unsuffixed variants need, and must
   keep the corresponding expanarg arrays large enough for the worst case
   documented at each routine.
   ------------------------------------------------------------------------- */

extern PREDICATES_REAL orient2dfast(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc);
extern PREDICATES_REAL orient2dexact(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc);
extern PREDICATES_REAL orient2dslow(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc);
extern PREDICATES_REAL orient2dadapt(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, PREDICATES_REAL detsum);
extern PREDICATES_REAL orient2d(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc);

extern PREDICATES_REAL orient3dfast(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);
extern PREDICATES_REAL orient3dexact(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);
extern PREDICATES_REAL orient3dslow(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);
extern PREDICATES_REAL orient3dadapt(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, PREDICATES_REAL permanent);
extern PREDICATES_REAL orient3d(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);

extern PREDICATES_REAL incirclefast(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);
extern PREDICATES_REAL incircleexact(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);
extern PREDICATES_REAL incircleslow(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);
extern PREDICATES_REAL incircleadapt(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, PREDICATES_REAL permanent);
extern PREDICATES_REAL incircle(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd);

extern PREDICATES_REAL inspherefast(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, const PREDICATES_REAL *pe);
extern PREDICATES_REAL insphereexact(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, const PREDICATES_REAL *pe);
extern PREDICATES_REAL insphereslow(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, const PREDICATES_REAL *pe);
extern PREDICATES_REAL insphereadapt(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, const PREDICATES_REAL *pe, PREDICATES_REAL permanent);
extern PREDICATES_REAL insphere(const PREDICATES_REAL *pa, const PREDICATES_REAL *pb, const PREDICATES_REAL *pc, const PREDICATES_REAL *pd, const PREDICATES_REAL *pe);

/* -------------------------------------------------------------------------
   Compile-time constants of the C translation unit.

   Declared here so that a caller can assert the library was built for the
   floating-point format it expects. `splitter` is 0 and `epsilon` is 0 until
   exactinit() runs.
   ------------------------------------------------------------------------- */
extern PREDICATES_REAL splitter;
extern PREDICATES_REAL epsilon;
extern PREDICATES_REAL resulterrbound;
extern PREDICATES_REAL ccwerrboundA;
extern PREDICATES_REAL ccwerrboundB;
extern PREDICATES_REAL ccwerrboundC;
extern PREDICATES_REAL o3derrboundA;
extern PREDICATES_REAL o3derrboundB;
extern PREDICATES_REAL o3derrboundC;
extern PREDICATES_REAL iccerrboundA;
extern PREDICATES_REAL iccerrboundB;
extern PREDICATES_REAL iccerrboundC;
extern PREDICATES_REAL isperrboundA;
extern PREDICATES_REAL isperrboundB;
extern PREDICATES_REAL isperrboundC;

#ifdef __cplusplus
}
#endif

#endif /* FOUNDATION_PREDICATES_PREDICATES_H */