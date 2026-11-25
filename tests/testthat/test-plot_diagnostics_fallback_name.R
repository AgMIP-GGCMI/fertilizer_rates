# tests/testthat/test-plot_diagnostics_fallback_name.R
#
# Covers plot_diagnostics() file naming and plotting options:
#   - the fallback plot_file naming path (below),
#   - preferRaster being restored on exit,
#   - an explicit plot_file being used as given.
#
# The fallback naming path is the `else` branch of the iam/gcm check that builds the `_annual_1850_2100_diagnostics.pdf` name; it fires when a non-histsoc scenario is passed
# without iam/gcm. This branch is not reachable from main(), which
# always supplies both iam and gcm for future scenarios.

test_that("plot_diagnostics uses the no-iam/gcm fallback filename", {
  tmp <- withr::local_tempdir()
  nlon <- 8; nlat <- 6; ntime <- 5
  base_rate <- matrix(seq(50, 150, length.out = nlon * nlat), nrow = nlon, ncol = nlat)
  scaled_data <- array(seq(50, 150, length.out = nlon * nlat * ntime),
                       dim = c(nlon, nlat, ntime))
  timeseries <- array(seq(25, 75, length.out = nlon * nlat * ntime),
                      dim = c(nlon, nlat, ntime))
  lon <- seq(-179.75, by = 0.5, length.out = nlon)
  lat <- seq(-60, by = 10, length.out = nlat)

  plot_diagnostics(
    base_rate = base_rate,
    scaled_data = scaled_data,
    timeseries = timeseries,
    lon = lon, lat = lat,
    start_year = 1998, end_year = 2002,
    crop = "mai",
    scenario = "ssp126",
    output_dir = tmp,
    method = "relative",
    iam = NULL, gcm = NULL
  )

  expected <- file.path(tmp,
    "n-fertilizer_mai_ssp126_relative_annual_1850_2100_diagnostics.pdf")
  expect_true(file.exists(expected))
})

test_that("plot_diagnostics leaves preferRaster as it found it", {
  withr::local_options(preferRaster = FALSE)
  tmp <- withr::local_tempdir()
  nlon <- 8; nlat <- 6; ntime <- 5
  base_rate <- matrix(seq(50, 150, length.out = nlon * nlat), nrow = nlon, ncol = nlat)
  scaled_data <- array(seq(50, 150, length.out = nlon * nlat * ntime),
                       dim = c(nlon, nlat, ntime))
  timeseries <- array(seq(25, 75, length.out = nlon * nlat * ntime),
                      dim = c(nlon, nlat, ntime))
  lon <- seq(-179.75, by = 0.5, length.out = nlon)
  lat <- seq(-60, by = 10, length.out = nlat)

  plot_diagnostics(
    base_rate = base_rate,
    scaled_data = scaled_data,
    timeseries = timeseries,
    lon = lon, lat = lat,
    start_year = 1998, end_year = 2002,
    crop = "mai",
    scenario = "ssp126",
    output_dir = tmp,
    method = "relative",
    iam = NULL, gcm = NULL
  )

  expect_false(getOption("preferRaster"))
})

test_that("plot_diagnostics writes to plot_file when one is given", {
  tmp <- withr::local_tempdir()
  nlon <- 8; nlat <- 6; ntime <- 5
  base_rate <- matrix(seq(50, 150, length.out = nlon * nlat), nrow = nlon, ncol = nlat)
  scaled_data <- array(seq(50, 150, length.out = nlon * nlat * ntime),
                       dim = c(nlon, nlat, ntime))
  timeseries <- array(seq(25, 75, length.out = nlon * nlat * ntime),
                      dim = c(nlon, nlat, ntime))
  lon <- seq(-179.75, by = 0.5, length.out = nlon)
  lat <- seq(-60, by = 10, length.out = nlat)
  f <- file.path(tmp, "explicit.pdf")
  plot_diagnostics(base_rate = base_rate, scaled_data = scaled_data,
                   timeseries = timeseries, lon = lon, lat = lat,
                   start_year = 2018, end_year = 2022, crop = "mai",
                   scenario = "4b-histsoc", output_dir = tmp,
                   method = "lambda", plot_file = f, ref_year = 2020)
  expect_true(file.exists(f))
  expect_length(list.files(tmp), 1)
})
