# tests/testthat/test-main_defensive_returns.R
#
# Covers main()'s defensive early-returns:
#   632-633  input 5-min spatial file does not exist
#   689-690  historical TS file missing for a future scenario
#   698-700  funcgroup variable not in historical TS file
#   724-725  histsoc TS file does not exist
#   765-768  neither funcgroup nor alt_name found in TS file
#
# Each test points main()'s base paths at fresh tempdirs and asserts
# main() returns NULL silently after printing the relevant error.

setup_paths <- function(envir = parent.frame()) {
  spatial <- withr::local_tempdir(.local_envir = envir)
  ts <- withr::local_tempdir(.local_envir = envir)
  out <- withr::local_tempdir(.local_envir = envir)
  local_mocked_globals(
    base_path_5min = spatial,
    base_path_timeseries = ts,
    output_base_path = out,
    aggregate_to_halfdegree = function(data, lon, lat) {
      nlon <- 720; nlat <- 360
      list(
        data = matrix(1, nrow = nlon, ncol = nlat),
        lon  = seq(-179.75, 179.75, by = 0.5),
        lat  = seq(-89.75,  89.75,  by = 0.5)
      )
    },
    .envir = envir
  )
  list(spatial = spatial, ts = ts, out = out)
}

test_that("main returns when 5-min spatial input file is missing", {
  p <- setup_paths()
  out <- capture.output(main("mai", "histsoc"))
  expect_true(any(grepl("Input file does not exist", out)))
})

test_that("main returns when historical TS file is missing for a future scenario", {
  p <- setup_paths()
  # Provide the spatial input so main gets past 632-633.
  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3)
  )
  out <- capture.output(
    main("mai", "ssp126", iam = "image", gcm = "gfdl-esm4")
  )
  expect_true(any(grepl("Historical time series file not found", out)))
})

test_that("main returns when funcgroup variable is not in the historical TS file", {
  p <- setup_paths()
  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3)
  )
  histsoc_dir <- file.path(p$ts, "histsoc")
  dir.create(histsoc_dir, recursive = TRUE)
  make_ts_nc(
    file.path(histsoc_dir, "n-fertilizer-5crops_histsoc_annual_1850_2014.nc"),
    var_name = "completely_wrong_name",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3),
    nyears = 165, start_year = 1850
  )
  out <- capture.output(
    main("mai", "ssp126", iam = "image", gcm = "gfdl-esm4")
  )
  expect_true(any(grepl("not found in historical file", out)))
})

test_that("main returns when histsoc TS file is missing", {
  p <- setup_paths()
  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3)
  )
  out <- capture.output(main("mai", "histsoc"))
  expect_true(any(grepl("Time series file does not exist", out)))
})

test_that("main returns when neither funcgroup nor alt_name found in TS file", {
  p <- setup_paths()
  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3)
  )
  histsoc_dir <- file.path(p$ts, "histsoc")
  dir.create(histsoc_dir, recursive = TRUE)
  make_ts_nc(
    file.path(histsoc_dir, "n-fertilizer-5crops_histsoc_annual_1850_2014.nc"),
    var_name = "junk_variable_xyz",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3),
    nyears = 165, start_year = 1850
  )
  out <- capture.output(main("mai", "histsoc"))
  expect_true(any(grepl("ERROR: Neither.*nor.*found in file", out)))
})
