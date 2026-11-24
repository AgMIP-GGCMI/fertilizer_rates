# Compute test coverage of the support library files using covr and the
# fast test suite only.
#
# Usage: Rscript tests/coverage_fast.R [threshold]
#
# Where [threshold] is an optional integer/numeric percentage (0-100). If
# given, the script exits with status 1 when overall line coverage is
# below that value. Intended for CI use.
#
# Run from the repo root.
#
# Scope: instruments the support library files that are sourced as part
# of the production runtime path or used by the PNG-regression tooling.
# Excludes CLI scripts (fertilizer_scaling.R, tools/render_diagnostics_png.R,
# tools/accept_diagnostics_baseline.R) because they execute at top level
# and can't be safely sourced into covr's evaluation env. Coverage of
# fertilizer_scaling_functions.R itself is measured by tests/coverage.R.
#
# This is "fast" because only tests/testthat/ files are used; the slow
# PNG-regression suite (which is what currently exercises the helper
# functions end-to-end) is skipped. Expect 0% until fast unit tests are
# added for the support helpers — the headline number is forward-looking
# scaffolding rather than a current-coverage signal.

suppressPackageStartupMessages(library(testthat))

if (!requireNamespace("covr", quietly = TRUE)) {
  stop("covr is not installed. Install with `renv::install(\"covr\")`.")
}

source_files <- c(
  "fertilizer_scaling_settings.R",
  "fertilizer_scaling_plot_diagnostics_functions.R",
  "tools/diagnostics_png_harness.R"
)

missing <- source_files[!file.exists(source_files)]
if (length(missing) > 0) {
  stop(sprintf(
    "Run tests/coverage_fast.R from the repo root (missing: %s in %s)",
    paste(missing, collapse = ", "), getwd()))
}

args <- commandArgs(trailingOnly = TRUE)
threshold <- if (length(args) >= 1) as.numeric(args[[1]]) else NA_real_

helpers    <- list.files("tests/testthat", pattern = "^helper-.*\\.R$", full.names = TRUE)
tests_fast <- list.files("tests/testthat", pattern = "^test-.*\\.R$", full.names = TRUE)

# Bootstrap: fertilizer_scaling_functions.R is loaded via test_files so
# its main(), plot_diagnostics(), and friends are reachable from fast
# tests. Order matters — covr loads source_files first (instrumenting
# them into env), then test_files. functions.R's inner source() of
# fertilizer_scaling_plot_diagnostics_functions.R puts a plain copy in
# globalenv, but env-rooted lookups from instrumented callers find the
# instrumented copy in env first, so coverage counts accumulate
# correctly.
fn_bootstrap <- "fertilizer_scaling_functions.R"

cov <- covr::file_coverage(
  source_files = source_files,
  test_files   = c(helpers, fn_bootstrap, tests_fast)
)

print(cov)

pct <- covr::percent_coverage(cov, by = "line")
cat(sprintf("\nLine coverage (support files, fast tests): %.2f%%\n", pct))

# Per-line HTML report, gitignored. Skipped when DT/htmltools aren't
# available — those are covr::report()'s rendering deps, locked in
# renv.lock, so `renv::restore()` provides them.
if (requireNamespace("DT", quietly = TRUE) &&
    requireNamespace("htmltools", quietly = TRUE)) {
  covr::report(cov, file = "coverage_fast.html", browse = FALSE)
  cat("HTML report: coverage_fast.html\n")
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
