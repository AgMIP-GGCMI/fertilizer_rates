#!/usr/bin/env Rscript
# ============================================================================
# accept_diagnostics_baseline.R
# ============================================================================
# Accept the current plot_diagnostics_regression PNG snapshots as the new
# baseline. Run after intentionally changing diagnostic output. Expects
# to be run from the repo root.
# ============================================================================

script_path <- sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
setwd(file.path(repo_root, "tests"))

library(testthat)
testthat::snapshot_accept("plot_diagnostics_regression")
