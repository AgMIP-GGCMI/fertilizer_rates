# testthat edition 3's expect_snapshot_file() auto-skips on CRAN, and
# on_cran() defaults to TRUE in non-interactive R unless NOT_CRAN is
# set. This repo is not a package and isn't on CRAN, so advertise that
# to testthat for the duration of the slow-test run.
# Kept out of .Renviron to avoid leaking into interactive and fast-test sessions.
Sys.setenv(NOT_CRAN = "true")

source(
  testthat::test_path("..", "..", "fertilizer_scaling_functions.R"),
  chdir = TRUE
)
