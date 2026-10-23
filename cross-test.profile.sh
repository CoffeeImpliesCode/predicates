# Cross-test sources this settings-only file in Bash.
# Leave target selection to the harness's active matrix.
# The default linkage is static; use a separate run for shared linkage.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=3600
CROSS_TIMEOUT=1800