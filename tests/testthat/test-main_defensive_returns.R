# tests/testthat/test-main_defensive_returns.R
#
# Covers main()'s handling of missing inputs.
#
# Early returns (main() prints the message and returns NULL):
#   - 5-arcmin input file missing        -> "Input file does not exist"
#   - histsoc TS file missing, histsoc run
#                                        -> "Time series file does not exist"
#   - neither funcgroup nor alt_name in the TS file
#                                        -> "ERROR: Neither ... nor ... found in file"
#
# Errors (future scenario; raised by read_timeseries_nc() via read_timeseries_year_slice()):
#   - histsoc TS file missing            -> "Time series file does not exist: <path>"
#   - funcgroup variable missing from the histsoc TS file
#                                        -> "Variable <funcgroup> not found in time series file: <path>"
#
# Each test points main()'s base paths at fresh tempdirs. Early-return tests
# capture main()'s printed output and grep it for the message; error tests
# wrap main() in expect_error() and match the condition message.

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

test_that("main errors when historical TS file is missing for a future scenario", {
  p <- setup_paths()
  # Provide the spatial input so main gets past the 5-arcmin input check.
  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize",
    lon = seq(-179.75, by = 0.5, length.out = 4),
    lat = seq(-89.75, by = 0.5, length.out = 3)
  )
  expect_error(
    capture.output(main("mai", "ssp126", iam = "image", gcm = "gfdl-esm4")),
    "Time series file does not exist: .*/histsoc/n-fertilizer-5crops_histsoc_annual_1850_2014\\.nc"
  )
})

test_that("main errors when funcgroup variable is not in the historical TS file", {
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
  expect_error(
    capture.output(main("mai", "ssp126", iam = "image", gcm = "gfdl-esm4")),
    "Variable fertl_c4ann not found in time series file",
    fixed = TRUE
  )
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
