# Compute test coverage of fertilizer_scaling_functions.R using covr.
#
# Usage: Rscript tests/coverage.R [threshold]
#
# Where [threshold] is an optional integer/numeric percentage (0-100). If
# given, the script exits with status 1 when line coverage is below that
# value. Intended for CI use.
#
# Run from the repo root. setup.R files are intentionally NOT passed as
# test files: covr instruments fertilizer_scaling_functions.R and sources
# it into the coverage environment, and setup.R's source() of the same
# file would overwrite those instrumented bindings with the plain ones,
# yielding 0% coverage.
#
# Both fast (tests/testthat) and slow (tests/testthat-slow) test files
# are included. The slow PNG-regression tests exercise main() and the
# downstream plotting/comparison functions end-to-end; they are required
# for the reported coverage number to reflect actual coverage of those
# I/O+plotting code paths.

suppressPackageStartupMessages(library(testthat))

if (!requireNamespace("covr", quietly = TRUE)) {
  stop("covr is not installed. Install with `renv::install(\"covr\")`.")
}

src_file <- "fertilizer_scaling_functions.R"
if (!file.exists(src_file)) {
  stop(sprintf(
    "Run tests/coverage.R from the repo root (missing: %s in %s)",
    src_file, getwd()))
}

args <- commandArgs(trailingOnly = TRUE)
threshold <- if (length(args) >= 1) as.numeric(args[[1]]) else NA_real_
helpers    <- list.files("tests/testthat", pattern = "^helper-.*\\.R$", full.names = TRUE)
tests_fast <- list.files("tests/testthat", pattern = "^test-.*\\.R$", full.names = TRUE)
tests_slow <- list.files("tests/testthat-slow", pattern = "^test-.*\\.R$", full.names = TRUE)

# Slow test bootstrap files. covr does not source setup.R (see header
# comment), so we inject the bits the slow tests need into covr's env via
# the test_files list:
#   * fertilizer_scaling_settings.R defines library() loads and the
#     constants (crop_to_inputfile etc.) that main() reads at runtime.
#   * tools/diagnostics_png_harness.R defines render_diagnostics_to_png().
#     The slow test file also sources it via source(...) (no local=TRUE),
#     which would land it in globalenv — outside covr's env, breaking
#     lookup of main(). Sourcing it here through covr's sys.source(envir =
#     env) puts it in env first, where its later test-file source() can't
#     dislodge it from env-rooted lookups.
slow_bootstrap <- c(
  "fertilizer_scaling_settings.R",
  "tools/diagnostics_png_harness.R"
)

# NOT_CRAN is required for testthat 3 expect_snapshot_file() under the slow
# tests; it is also set inside tests/testthat-slow/setup.R for direct
# test_dir() runs, but covr does not source setup.R (see header comment),
# so we set it here as well.
Sys.setenv(NOT_CRAN = "true")

# Slow test file calls testthat::local_edition(3) at top level, but covr
# wraps test-file evaluation in withr scopes that pop the edition before
# the test_that() body runs. testthat reads TESTTHAT_EDITION as a
# non-package fallback (no DESCRIPTION here), so set it for this run.
Sys.setenv(TESTTHAT_EDITION = "3")

cov <- covr::file_coverage(
  source_files = src_file,
  test_files   = c(helpers, slow_bootstrap, tests_fast, tests_slow)
)

print(cov)

pct <- covr::percent_coverage(cov, by = "line")
cat(sprintf("\nLine coverage: %.2f%%\n", pct))

# Per-line HTML report, gitignored. Skipped when DT/htmltools aren't
# available — those are covr::report()'s rendering deps, locked in
# renv.lock, so `renv::restore()` provides them.
if (requireNamespace("DT", quietly = TRUE) &&
    requireNamespace("htmltools", quietly = TRUE)) {
  covr::report(cov, file = "coverage.html", browse = FALSE)
  cat("HTML report: coverage.html\n")
} else {
  cat("HTML report skipped: install DT and htmltools to enable.\n")
}

if (!is.na(threshold)) {
  if (pct < threshold) {
    cat(sprintf("FAIL: coverage %.2f%% is below threshold %.2f%%\n", pct, threshold))
    quit(status = 1)
  } else {
    cat(sprintf("OK: coverage %.2f%% meets threshold %.2f%%\n", pct, threshold))
  }
}

invisible(cov)
