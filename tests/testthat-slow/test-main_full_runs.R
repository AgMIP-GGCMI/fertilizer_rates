# tests/testthat-slow/test-main_full_runs.R
#
# End-to-end main() runs that exercise branches reachable only by
# completing the workflow. aggregate_to_halfdegree is mocked to a
# pass-through so the test can use tiny synthetic grids.

setup_full_run <- function(envir = parent.frame()) {
  spatial <- withr::local_tempdir(.local_envir = envir)
  ts <- withr::local_tempdir(.local_envir = envir)
  out <- withr::local_tempdir(.local_envir = envir)
  # The real aggregate_to_halfdegree sorts lat South->North; the 5-min NetCDF
  # stores lat North->South (decreasing). sort() here mirrors what the real
  # aggregator does so plot_aggregation_comparison receives increasing lat for
  # the 0.5-degree arg while rev()ing the still-decreasing lat_5min arg.
  passthrough <- function(data_5min, lon_5min, lat_5min) {
    list(data = data_5min, lon = lon_5min, lat = sort(lat_5min))
  }
  local_mocked_globals(
    base_path_5min = spatial,
    base_path_timeseries = ts,
    output_base_path = out,
    aggregate_to_halfdegree = passthrough,
    .envir = envir
  )
  list(spatial = spatial, ts = ts, out = out)
}

test_that("main() handles a 3D 5-min spatial variable (slices first time step)", {
  p <- setup_full_run()
  lon <- seq(-179.75, by = 0.5, length.out = 4)
  # Real 5-min files store lat North->South (decreasing); rev() in
  # plot_aggregation_comparison expects that ordering.
  lat <- seq(-40, by = -10, length.out = 3)
  # 3D spatial: lon x lat x time, time length 2 so ncvar_get does NOT
  # collapse the degenerate dim.
  spatial_3d <- array(seq(50, 150, length.out = 4 * 3 * 2), dim = c(4, 3, 2))
  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize", lon = lon, lat = lat,
    data = spatial_3d, time = c(1, 2)
  )
  histsoc_dir <- file.path(p$ts, "histsoc")
  dir.create(histsoc_dir, recursive = TRUE)
  make_ts_nc(
    file.path(histsoc_dir, "n-fertilizer-5crops_histsoc_annual_1850_2014.nc"),
    var_name = "fertl_c4ann",
    lon = lon, lat = lat, nyears = 165, start_year = 1850,
    data = array(seq(25, 75, length.out = 4 * 3 * 165), dim = c(4, 3, 165))
  )

  expect_no_error(main("mai", "histsoc"))
  # main() writes outputs at output_base_path; confirm the histsoc
  # relative NetCDF is present, proving main() ran to completion.
  expect_true(file.exists(file.path(
    p$out, "histsoc", "relative",
    "n-fertilizer_mai_histsoc_relative_annual_1850_2014.nc"
  )))
})
