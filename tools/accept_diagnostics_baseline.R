#!/usr/bin/env Rscript
# ============================================================================
# accept_diagnostics_baseline.R
# ============================================================================
# Accept the current plot_diagnostics_regression PNG snapshots as the new
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
setwd(file.path(repo_root, "tests"))

library(testthat)
testthat::snapshot_accept("plot_diagnostics_regression")
