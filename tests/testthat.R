library(testthat)

# Resolve this script's directory so `Rscript tests/testthat.R` works from
# either the repo root or the tests/ directory.
script_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1) {
    dirname(normalizePath(sub("^--file=", "", file_arg)))
  } else {
    # Interactive source() fallback.
    getwd()
  }
})

testthat::test_dir(file.path(script_dir, "testthat"))
