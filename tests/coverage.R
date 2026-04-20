# Compute test coverage of fertilizer_scaling_functions.R using covr.
#
# Usage: Rscript tests/coverage.R [threshold]
#
# Where [threshold] is an optional integer/numeric percentage (0-100). If
# given, the script exits with status 1 when line coverage is below that
# value. Intended for CI use.
#
# Run from the repo root. tests/testthat/setup.R is intentionally NOT passed
# as a test file: covr instruments fertilizer_scaling_functions.R and sources
# it into the coverage environment, and setup.R's source() of the same file
# would overwrite those instrumented bindings with the plain ones, yielding
# 0% coverage.

suppressPackageStartupMessages(library(testthat))

if (!requireNamespace("covr", quietly = TRUE)) {
  stop("covr is not installed. Install with `renv::install(\"covr\")`.")
}

args <- commandArgs(trailingOnly = TRUE)
threshold <- if (length(args) >= 1) as.numeric(args[[1]]) else NA_real_

src_file <- "fertilizer_scaling_functions.R"
helpers  <- list.files("tests/testthat", pattern = "^helper-.*\\.R$", full.names = TRUE)
tests    <- list.files("tests/testthat", pattern = "^test-.*\\.R$",    full.names = TRUE)

cov <- covr::file_coverage(
  source_files = src_file,
  test_files   = c(helpers, tests)
)

print(cov)

pct <- covr::percent_coverage(cov, by = "line")
cat(sprintf("\nLine coverage: %.2f%%\n", pct))

if (!is.na(threshold)) {
  if (pct < threshold) {
    cat(sprintf("FAIL: coverage %.2f%% is below threshold %.2f%%\n", pct, threshold))
    quit(status = 1)
  } else {
    cat(sprintf("OK: coverage %.2f%% meets threshold %.2f%%\n", pct, threshold))
  }
}

invisible(cov)
