# tests/testthat/test-plot_diagnostics_fallback_name.R
#
# Covers the fallback plot_file naming path in plot_diagnostics()
# (lines 558-559) — fires when a non-histsoc scenario is passed
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
