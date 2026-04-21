# Shared runner logic for tests/testthat.R (full) and
# tests/testthat-fast.R (skips slow PNG-regression tests).

library(testthat)

run_tests <- function(fast_only = FALSE) {
  tests_dir <- dirname(normalizePath(sub("^--file=", "",
    grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
  testthat::test_dir(file.path(tests_dir, "testthat"))
  slow_dir <- file.path(tests_dir, "testthat-slow")
  if (!fast_only && dir.exists(slow_dir)) {
    testthat::test_dir(slow_dir)
  }
}
