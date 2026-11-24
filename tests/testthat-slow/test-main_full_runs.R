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
  # compare_relative_lambda's plot_density_heatmap bins 12 grid cells into
  # 40x40 bins; each point lands in a unique bin, so range(z) = c(1,1) and
  # image.plot dies. The crash is caught by the tryCatch handler, but that
  # would accidentally cover the tryCatch error handler in compare_relative_lambda() from these end-to-end tests.
  # Stub it out so coverage of the handler comes from the targeted test at
  # tests/testthat/test-compare_relative_lambda_trycatch.R.
  # Under the production setting (lambda only) main() skips compare_relative_lambda(), so the stub only matters when both methods are enabled.
  noop_compare <- function(...) invisible(NULL)
  local_mocked_globals(
    base_path_5min = spatial,
    base_path_timeseries = ts,
    output_base_path = out,
    aggregate_to_halfdegree = passthrough,
    compare_relative_lambda = noop_compare,
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
  # lambda NetCDF is present, proving main() ran to completion.
  expect_true(file.exists(file.path(
    p$out, "histsoc", "lambda",
    "n-fertilizer_mai_histsoc_lambda_annual_1850_2014.nc"
  )))
})

test_that("main() falls back to fertl_<type> alt name when funcgroup uses <type>_fertl", {
  p <- setup_full_run()
  lon <- seq(-179.75, by = 0.5, length.out = 4)
  lat <- seq(-40, by = -10, length.out = 3)

  # Override crop_to_funcgroup so mai maps to the non-"fertl_"-prefixed
  # form, forcing the else branch in main() (the `startsWith(funcgroup, "fertl_")` check fails, so the else branch builds the
  # alt_name = "fertl_c4ann").
  local_mocked_globals(
    crop_to_funcgroup = modifyList(crop_to_funcgroup, list(mai = "c4ann_fertl"))
  )

  make_5min_spatial_nc(
    file.path(p$spatial, "maizeNapprate_gadm_subnational.nc"),
    input_crop = "maize", lon = lon, lat = lat,
    data = array(seq(50, 150, length.out = 4 * 3), dim = c(4, 3))
  )
  histsoc_dir <- file.path(p$ts, "histsoc")
  dir.create(histsoc_dir, recursive = TRUE)
  # The TS file has the "fertl_c4ann" variable, so main() must build
  # alt_name = "fertl_c4ann" via main()'s alt_name fallback and find it.
  make_ts_nc(
    file.path(histsoc_dir, "n-fertilizer-5crops_histsoc_annual_1850_2014.nc"),
    var_name = "fertl_c4ann",
    lon = lon, lat = lat, nyears = 165, start_year = 1850,
    data = array(seq(25, 75, length.out = 4 * 3 * 165), dim = c(4, 3, 165))
  )

  out <- capture.output(main("mai", "histsoc"))
  expect_true(any(grepl("not found, using fertl_c4ann instead", out)))
  expect_true(file.exists(file.path(
    p$out, "histsoc", "lambda",
    "n-fertilizer_mai_histsoc_lambda_annual_1850_2014.nc"
  )))
})
