# tests/testthat/test-compare_relative_lambda_missing_files.R
#
# Covers the two file-existence early-returns at the top of
# compare_relative_lambda() (lines 955-956 and 959-960 in
# fertilizer_scaling_functions.R).

test_that("compare_relative_lambda returns early when relative file is missing", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)
  out <- capture.output(
    compare_relative_lambda("mai", "histsoc", output_dir = tmp)
  )
  expect_true(any(grepl("Relative file not found", out)))
})

test_that("compare_relative_lambda returns early when only lambda file is missing", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)
  # Create just the relative file so the first check passes and the
  # second one fires.
  rel_dir <- file.path(tmp, "histsoc", "relative")
  dir.create(rel_dir, recursive = TRUE)
  make_ts_nc(
    file.path(rel_dir, "n-fertilizer_mai_histsoc_relative_annual_1850_2014.nc"),
    var_name = "fertl_mai",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3),
    nyears = 165, start_year = 1850
  )
  out <- capture.output(
    compare_relative_lambda("mai", "histsoc", output_dir = tmp)
  )
  expect_true(any(grepl("Lambda file not found", out)))
})
