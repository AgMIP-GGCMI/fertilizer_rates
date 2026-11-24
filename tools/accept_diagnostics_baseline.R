#!/usr/bin/env Rscript
# ============================================================================
# accept_diagnostics_baseline.R
# ============================================================================
# Accept the current tests/testthat-slow/_snaps/plot_diagnostics_regression/ PNG snapshots as the new
# baseline. Run after intentionally changing diagnostic output. Can be
# invoked from any working directory — the repo root is resolved from
# the script's own path.
# ============================================================================

file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
repo_root <- if (length(file_arg) == 1) {
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), ".."))
} else {
  # Interactive source() fallback.
  dirname(getwd())
}

library(testthat)
testthat::snapshot_accept("plot_diagnostics_regression/", path = file.path(repo_root, "tests", "testthat-slow"))
