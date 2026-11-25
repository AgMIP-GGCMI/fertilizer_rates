# tests/testthat/test-plot_relative_lambda_comparison.R
#
# Covers plot_relative_lambda_comparison(), the array-based plotter behind compare_relative_lambda(): it writes the requested PDF, restores preferRaster, and runs to completion both when ref_year lies inside start_year..end_year and when it does not. The function's tryCatch swallows plotting errors and leaves a PDF behind, so each test also asserts its output contains no "ERROR IN".

# Per-cell and per-time variation keeps the trend and rate density panels from collapsing to a single value.
make_rel <- function() {
  idx <- seq_len(6 * 5 * 3)
  array(10 + 90 * idx / length(idx) + 5 * sin(idx^2), dim = c(6, 5, 3))
}

test_that("plot_relative_lambda_comparison writes the requested PDF", {
  tmp <- withr::local_tempdir()
  lon <- seq(-179.75, by = 0.5, length.out = 6)
  lat <- seq(-40, by = 10, length.out = 5)
  rel <- make_rel()
  lam <- rel * 1.1
  f <- file.path(tmp, "cmp.pdf")
  out <- capture.output(
    plot_relative_lambda_comparison(rel, lam, lon, lat, 2019, 2021, "mai",
                                    plot_file = f, ref_year = 2020)
  )
  expect_true(file.exists(f))
  expect_false(any(grepl("ERROR IN", out)))
})

test_that("plot_relative_lambda_comparison leaves preferRaster as it found it", {
  withr::local_options(preferRaster = FALSE)
  tmp <- withr::local_tempdir()
  lon <- seq(-179.75, by = 0.5, length.out = 6)
  lat <- seq(-40, by = 10, length.out = 5)
  rel <- make_rel()
  out <- capture.output(
    plot_relative_lambda_comparison(rel, rel * 1.1, lon, lat, 2019, 2021, "mai",
                                    plot_file = file.path(tmp, "cmp.pdf"), ref_year = 2020)
  )
  expect_false(getOption("preferRaster"))
  expect_false(any(grepl("ERROR IN", out)))
})

test_that("plot_relative_lambda_comparison completes when ref_year is outside the series", {
  tmp <- withr::local_tempdir()
  lon <- seq(-179.75, by = 0.5, length.out = 6)
  lat <- seq(-40, by = 10, length.out = 5)
  rel <- make_rel()
  f <- file.path(tmp, "cmp.pdf")
  out <- capture.output(
    plot_relative_lambda_comparison(rel, rel * 1.1, lon, lat, 2019, 2021, "mai",
                                    plot_file = f, ref_year = 2000)
  )
  expect_true(file.exists(f))
  expect_false(any(grepl("ERROR IN", out)))
})

test_that("plot_relative_lambda_comparison labels the base-year panels with ref_year", {
  tmp <- withr::local_tempdir()
  lon <- seq(-179.75, by = 0.5, length.out = 6)
  lat <- seq(-40, by = 10, length.out = 5)
  rel <- make_rel()
  out <- capture.output(
    plot_relative_lambda_comparison(rel, rel * 1.1, lon, lat, 2019, 2021, "mai",
                                    plot_file = file.path(tmp, "cmp.pdf"), ref_year = 2020)
  )
  expect_true(any(grepl("Plotting Year 2020 maps", out)))
  expect_true(any(grepl("Year 2020 equality count", out)))
  expect_false(any(grepl("Year 2000", out)))
})
