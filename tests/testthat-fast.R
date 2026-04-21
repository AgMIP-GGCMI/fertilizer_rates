source(sub("testthat(-fast)?\\.R$", "_runner_common.R", sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
run_tests(fast_only = TRUE)
