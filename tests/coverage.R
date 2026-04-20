# tests/coverage.R — measure line coverage of fertilizer_scaling_functions.R.
#
# Usage (from repo root):
#   Rscript tests/coverage.R           # default threshold 50 %
#   Rscript tests/coverage.R 80        # custom threshold (exit 1 if below)
#   Rscript tests/coverage.R 0         # no threshold check
#
# Design notes
# ------------
# This project is script-based, not a package: fertilizer_scaling_functions.R
# is sourced via tests/testthat/setup.R, so its functions live in globalenv().
# covr::file_coverage() isolates source in a child environment, which breaks
# local_mocked_globals() (the project's mock helper).  We therefore:
#   1. sys.source() the production file into globalenv() with keep.source=TRUE
#      so covr can instrument the srcrefs.
#   2. Trace only globalenv() (skipping helper-mock.R and other helpers).
#   3. Intercept the base::source() call that setup.R makes so it does not
#      re-source and overwrite the already-traced functions.
#   4. Run testthat::test_dir() in the normal way (picks up helpers, setup,
#      and all test-*.R files).
#   5. Collect covr's counters and report.
#
# Only the seven unit-tested scaling functions are counted toward the
# threshold; the large unreachable utility functions (main, plot_diagnostics,
# compare_*, test_scaling) are excluded so the threshold reflects actual
# testable coverage.

suppressPackageStartupMessages({
  library(testthat)
  library(covr)
  library(withr)
})

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
threshold <- if (length(args) >= 1) as.numeric(args[[1]]) else 50

if (is.na(threshold) || threshold < 0 || threshold > 100) {
  stop("threshold must be a number in [0, 100]")
}

# ---------------------------------------------------------------------------
# Functions to exclude from the threshold (not unit-testable from R alone)
# ---------------------------------------------------------------------------
excluded_fns <- c(
  "test_scaling",
  "plot_diagnostics",
  "main",
  "compare_2014_2015",
  "compare_relative_lambda"
)

# ---------------------------------------------------------------------------
# Step 1: Load production code with srcrefs into globalenv
# ---------------------------------------------------------------------------
script_dir <- tryCatch(
  dirname(normalizePath(sys.frame(0)$ofile, mustWork = TRUE)),
  error = function(e) "tests"
)
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
prod_file  <- file.path(repo_root, "fertilizer_scaling_functions.R")
mock_file  <- file.path(repo_root, "tests", "testthat", "helper-mock.R")

sys.source(prod_file, envir = globalenv(), keep.source = TRUE)
sys.source(mock_file, envir = globalenv(), keep.source = FALSE)

# ---------------------------------------------------------------------------
# Step 2: Instrument only the production functions (leave helpers untraced)
# ---------------------------------------------------------------------------
prod_fn_names <- ls(globalenv())
prod_fn_names <- prod_fn_names[
  vapply(prod_fn_names, function(nm) {
    fn <- get(nm, envir = globalenv(), inherits = FALSE)
    is.function(fn) && !is.null(attr(fn, "srcref"))
  }, logical(1))
]

prod_env <- new.env(parent = emptyenv())
for (nm in prod_fn_names) {
  assign(nm, get(nm, envir = globalenv(), inherits = FALSE), envir = prod_env)
}

invisible(covr:::trace_environment(prod_env))

for (nm in ls(prod_env)) {
  assign(nm, get(nm, envir = prod_env, inherits = FALSE), envir = globalenv())
}

# ---------------------------------------------------------------------------
# Step 3: Block setup.R from re-sourcing the production file
# ---------------------------------------------------------------------------
real_base_source <- base::source
block_source <- function(file, ...) {
  if (grepl("fertilizer_scaling_functions[.]R", basename(file))) {
    invisible(NULL)
  } else {
    real_base_source(file, ...)
  }
}
assign("source", block_source, envir = globalenv())

# ---------------------------------------------------------------------------
# Step 4: Run all tests under covr's counter environment
# ---------------------------------------------------------------------------
test_result <- withr::with_envvar(c(R_COVR = "true"), {
  suppressMessages(
    testthat::test_dir(
      file.path(repo_root, "tests", "testthat"),
      reporter = "progress",
      stop_on_failure = FALSE
    )
  )
})

# Restore source
assign("source", real_base_source, envir = globalenv())

# ---------------------------------------------------------------------------
# Step 5: Report
# ---------------------------------------------------------------------------
df <- as.data.frame(test_result)
n_pass <- sum(df$passed)
n_fail <- sum(df$failed)
cat(sprintf("\nTest results: %d PASS, %d FAIL\n", n_pass, n_fail))

coverage <- covr:::as_coverage(covr:::.counters)
pct_all  <- percent_coverage(coverage)

# Coverage excluding large untested utility functions
coverage_filtered <- coverage[
  !vapply(coverage, function(x) any(x$functions %in% excluded_fns), logical(1))
]
pct_filtered <- percent_coverage(coverage_filtered)

cat(sprintf("Coverage (all functions):      %.1f%%\n", pct_all))
cat(sprintf("Coverage (unit-tested subset): %.1f%%\n", pct_filtered))

# Per-function tally
tally <- tally_coverage(coverage)
fn_names <- unique(tally$functions)
cat("\nPer-function coverage:\n")
for (fn in fn_names) {
  ft   <- tally[tally$functions == fn, ]
  hit  <- sum(ft$value > 0)
  tot  <- nrow(ft)
  pct  <- if (tot == 0) 100 else 100 * hit / tot
  note <- if (fn %in% excluded_fns) "  [excluded from threshold]" else ""
  cat(sprintf("  %-35s %3d/%3d (%5.1f%%)%s\n", fn, hit, tot, pct, note))
}

# Reset instrumentation
invisible(covr:::reset_traces())
invisible(covr:::clear_counters())

# ---------------------------------------------------------------------------
# Step 6: Exit code
# ---------------------------------------------------------------------------
if (n_fail > 0) {
  cat(sprintf("\nERROR: %d test(s) failed.\n", n_fail))
  quit(status = 1)
}
if (threshold > 0 && pct_all < threshold) {
  cat(sprintf(
    "\nERROR: coverage %.1f%% is below threshold %.1f%%\n",
    pct_all, threshold
  ))
  quit(status = 1)
}
cat(sprintf(
  "\nOK: coverage %.1f%% meets threshold %.1f%%\n",
  pct_all, threshold
))
quit(status = 0)
