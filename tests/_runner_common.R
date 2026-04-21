# Shared runner logic for tests/testthat.R (full) and
# tests/testthat-fast.R (skips slow PNG-regression tests).

library(testthat)

run_tests <- function(fast_only = FALSE) {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  tests_dir <- if (length(file_arg) == 1) {
    dirname(normalizePath(sub("^--file=", "", file_arg)))
  } else {
    getwd()  # Interactive source() fallback.
  }
  testthat::test_dir(file.path(tests_dir, "testthat"))
  slow_dir <- file.path(tests_dir, "testthat-slow")
  if (!fast_only && dir.exists(slow_dir)) {
    testthat::test_dir(slow_dir)
  }
}
