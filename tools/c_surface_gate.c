/* The public C surface gate for this fork.
 *
 * This translation unit is the coverage for `include/predicates.h`, and it is
 * a link-level gate rather than a textual one. It includes the *installed*
 * header, calls every routine that header declares and reads every global it
 * declares, and it is linked against the *installed* artifact. A declaration
 * whose type is wrong fails to compile. A declaration the artifact does not
 * define fails to link — and when the artifact is a shared object, it fails to
 * link only if the symbol is missing from that object's dynamic export table,
 * which is exactly what a runtime loader later resolves against.
 *
 * The reason this lives in a file rather than in a shell heredoc is that both
 * delivery variants need it. `-Dlinkage=static` links it against
 * `libpredicates.a`; `-Dlinkage=dynamic` links the same file against
 * `libpredicates.so`. Two copies of this program would be two definitions of
 * the same gate, and the two would drift.
 *
 * Nothing here re-implements a predicate and nothing checks a value that a
 * predicate computed, except the one sign assertion below, which is certain by
 * hand. The rest of the calls exist so that the optimizer cannot delete them.
 *
 * SPDX-License-Identifier: LicenseRef-PublicDomain
 */

#include <predicates.h>
#include <stdio.h>

/* volatile so no optimizer can delete a call: the compile and the
   link are the assertions, not the values. */
static volatile double sink;

int main(void) {
    double a[2] = { 0.0, 0.0 };
    double b[2] = { 1.0, 0.0 };
    double c[2] = { 0.0, 1.0 };
    double dd[2] = { 0.0, 0.0 };
    double p[3] = { 0.0, 0.0, 0.0 };
    double q[3] = { 1.0, 0.0, 0.0 };
    double r[3] = { 0.0, 1.0, 0.0 };
    double s[3] = { 0.0, 0.0, 1.0 };
    double t[3] = { 0.0, 0.0, 0.5 };
    double one[1] = { 1.0 };
    double two[2] = { 0.0, 1.0 };
    double h[8];
    double g[8];

    exactinit();

    /* The one asserted result: counterclockwise is positive. */
    if (orient2d(a, b, c) <= 0.0) return 1;

    sink = orient2dfast(a, b, c);
    sink = orient2dexact(a, b, c);
    sink = orient2dslow(a, b, c);
    sink = orient2dadapt(a, b, c, 1.0);

    sink = orient3dfast(p, q, r, s);
    sink = orient3dexact(p, q, r, s);
    sink = orient3dslow(p, q, r, s);
    sink = orient3dadapt(p, q, r, s, 1.0);
    sink = orient3d(p, q, r, t);

    sink = incirclefast(b, c, dd, a);
    sink = incircleexact(b, c, dd, a);
    sink = incircleslow(b, c, dd, a);
    sink = incircleadapt(b, c, dd, a, 1.0);
    sink = incircle(b, c, dd, a);

    sink = inspherefast(q, r, s, p, t);
    sink = insphereexact(q, r, s, p, t);
    sink = insphereslow(q, r, s, p, t);
    sink = insphereadapt(q, r, s, p, t, 1.0);
    sink = insphere(q, r, s, p, t);

    sink = (double)grow_expansion(1, one, 0.5, h);
    sink = (double)grow_expansion_zeroelim(1, one, 0.5, h);
    sink = (double)expansion_sum(1, one, 1, one, h);
    sink = (double)expansion_sum_zeroelim1(1, one, 1, one, h);
    sink = (double)expansion_sum_zeroelim2(1, one, 1, one, h);
    sink = (double)fast_expansion_sum(1, one, 1, one, h);
    sink = (double)fast_expansion_sum_zeroelim(1, one, 1, one, h);
    sink = (double)linear_expansion_sum(1, one, 1, one, h);
    sink = (double)linear_expansion_sum_zeroelim(1, one, 1, one, h);
    sink = (double)scale_expansion(1, one, 2.0, g);
    sink = (double)scale_expansion_zeroelim(1, one, 2.0, g);
    sink = (double)compress(2, two, h);
    sink = estimate(1, one);

    sink = doublerand();
    sink = narrowdoublerand();
    sink = uniformdoublerand();
    sink = floatrand();
    sink = narrowfloatrand();
    sink = uniformfloatrand();

    sink = splitter + epsilon + resulterrbound + ccwerrboundA +
           ccwerrboundB + ccwerrboundC + o3derrboundA + o3derrboundB +
           o3derrboundC + iccerrboundA + iccerrboundB + iccerrboundC +
           isperrboundA + isperrboundB + isperrboundC;

    printf("public C surface compiled, linked and ran\n");
    return 0;
}