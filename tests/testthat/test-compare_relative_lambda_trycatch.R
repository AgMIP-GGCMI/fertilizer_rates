# tests/testthat/test-compare_relative_lambda_trycatch.R
#
# Covers compare_relative_lambda's tryCatch error handler (lines 1353-1358)
# by feeding rel + lambda NetCDFs whose 12 cells have pairwise-distinct
# (trend_rel, trend_lambda) signatures. The 40x40 bin histogram in
# plot_density_heatmap then puts every point in its own bin, so
# range(z, na.rm = TRUE) = c(1, 1), zlim collapses, and image.plot fails
# with "increasing 'x' and 'y' values expected" — caught by the handler.

test_that("compare_relative_lambda's tryCatch catches plot_density_heatmap zlim collapse", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)

  lon <- seq(-179.75, by = 0.5, length.out = 4)
  lat <- seq(-89.75, by = 0.5, length.out = 3)
  rel_dir <- file.path(tmp, "histsoc", "relative")
  lambda_dir <- file.path(tmp, "histsoc", "lambda")
  dir.create(rel_dir, recursive = TRUE)
  dir.create(lambda_dir, recursive = TRUE)

  # Build per-cell trends that are all distinct across the 12 cells so
  # plot_density_heatmap's bin counts stay flat at 1.
  nyears <- 165
  rel_data <- array(0, dim = c(4, 3, nyears))
  lambda_data <- array(0, dim = c(4, 3, nyears))
  for (i in seq_len(4)) for (j in seq_len(3)) for (t in seq_len(nyears)) {
    rel_data[i, j, t]    <- 100 + (i + 0.1 * j) * t
    lambda_data[i, j, t] <- 100 + (0.1 * i + j) * t
  }

  make_ts_nc(
    file.path(rel_dir, "n-fertilizer_mai_histsoc_relative_annual_1850_2014.nc"),
    var_name = "fertl_mai", lon = lon, lat = lat,
    nyears = nyears, start_year = 1850, data = rel_data
  )
  make_ts_nc(
    file.path(lambda_dir, "n-fertilizer_mai_histsoc_lambda_annual_1850_2014.nc"),
    var_name = "fertl_mai", lon = lon, lat = lat,
    nyears = nyears, start_year = 1850, data = lambda_data
  )

  out <- capture.output(
    compare_relative_lambda("mai", "histsoc", output_dir = tmp)
  )
  expect_true(any(grepl("ERROR IN compare_relative_lambda", out)))
  expect_true(any(grepl("increasing 'x' and 'y' values expected", out)))
})
