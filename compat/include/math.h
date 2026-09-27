#ifndef COMPAT_MATH_H
#define COMPAT_MATH_H
double fmod(double x, double y);
double pow(double x, double y);
double sqrt(double x);
double sin(double x);
double cos(double x);
double tan(double x);
double log(double x);
double exp(double x);
double fabs(double x);
double floor(double x);
double ceil(double x);

/* The emitted C calls isfinite(), and a freestanding build has no <math.h>
 * macro for it. Spelled out rather than pulled from a libc: NaN fails the
 * self-comparison and infinities fail the bound, so the three cases are
 * distinguished without relying on x - x not being folded away. */
#define isfinite(x) \
    (((x) == (x)) && \
     ((x) <= 1.7976931348623157e308) && \
     ((x) >= -1.7976931348623157e308))
#endif
