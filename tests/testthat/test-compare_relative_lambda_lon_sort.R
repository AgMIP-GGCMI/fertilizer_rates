# tests/testthat/test-compare_relative_lambda_lon_sort.R
#
# Covers the lon-coords-not-monotonically-increasing sort path at
# the `any(diff(lon) <= 0)` block in compare_relative_lambda().

test_that("compare_relative_lambda sorts when lon coords are decreasing", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)

  # Build rel + lambda histsoc files with strictly DECREASING lon.
  lon_dec <- rev(seq(-179.75, by = 0.5, length.out = 4))
  lat <- seq(-89.75, by = 0.5, length.out = 3)
  rel_dir <- file.path(tmp, "histsoc", "relative")
  lambda_dir <- file.path(tmp, "histsoc", "lambda")
  dir.create(rel_dir, recursive = TRUE)
  dir.create(lambda_dir, recursive = TRUE)

  make_ts_nc(
    file.path(rel_dir, "n-fertilizer_mai_histsoc_relative_annual_1850_2014.nc"),
    var_name = "fertl_mai", lon = lon_dec, lat = lat,
    nyears = 165, start_year = 1850
  )
  make_ts_nc(
    file.path(lambda_dir, "n-fertilizer_mai_histsoc_lambda_annual_1850_2014.nc"),
    var_name = "fertl_mai", lon = lon_dec, lat = lat,
    nyears = 165, start_year = 1850
  )

  out <- capture.output(
    compare_relative_lambda("mai", "histsoc", output_dir = tmp)
  )
  expect_true(any(grepl("lon coordinates not increasing", out)))
  # The function should have produced a comparison PDF after sorting.
  expect_true(file.exists(file.path(tmp, "comparison_relative_lambda_mai_histsoc.pdf")))
})
