# tests/testthat/test-compare_relative_lambda_files.R
#
# Tests for compare_relative_lambda_files() in fertilizer_scaling_functions.R,
# with the plotter mocked to capture its arguments.

lat_desc <- c(0.75, 0.25)

# plot_file and ref_year are formals after `...`, so the mock only accepts them by name.
capture_plotter <- function(env) {
  function(rel_data, lambda_data, lon, lat, ..., plot_file, ref_year) {
    env$args <- c(list(rel_data = rel_data, lambda_data = lambda_data, lon = lon, lat = lat,
                       plot_file = plot_file, ref_year = ref_year), list(...))
  }
}

test_that("series split across files are concatenated and passed to the plotter", {
  tmp <- withr::local_tempdir()
  lon <- c(0.25, 0.75)
  a <- array(1:4, dim = c(2, 2, 1)); b <- array(5:12, dim = c(2, 2, 2))
  mk <- function(dir, offset) {
    dir.create(file.path(tmp, dir))
    c(make_ts_nc(file.path(tmp, dir, "a.nc"), "v", lon, lat_desc, 1, 2018, a + offset),
      make_ts_nc(file.path(tmp, dir, "b.nc"), "v", lon, lat_desc, 2, 2019, b + offset))
  }
  rel <- mk("rel", 0); lam <- mk("lam", 100)
  cap <- new.env()
  local_mocked_globals(plot_relative_lambda_comparison = capture_plotter(cap))
  compare_relative_lambda_files(rel, lam, list(2018L, 2019:2020), "v", "mai",
                                "out.pdf", ref_year = 2019)
  expect_equal(dim(cap$args$rel_data), c(2L, 2L, 3L))
  expect_equal(cap$args$rel_data[, , 3], b[, 2:1, 2] + 0)
  expect_equal(cap$args$lambda_data[, , 1], a[, 2:1, 1] + 100)
  expect_equal(cap$args$lat, c(0.25, 0.75))
  expect_equal(cap$args$start_year, 2018L)
  expect_equal(cap$args$end_year, 2020L)
  expect_equal(cap$args$crop, "mai")
  expect_equal(cap$args$plot_file, "out.pdf")
  expect_equal(cap$args$ref_year, 2019)
})

test_that("files whose lon decreases are sorted before plotting", {
  tmp <- withr::local_tempdir()
  d <- array(1:4, dim = c(2, 2, 1))
  r <- make_ts_nc(file.path(tmp, "r.nc"), "v", c(0.75, 0.25), lat_desc, 1, 2018, d)
  l <- make_ts_nc(file.path(tmp, "l.nc"), "v", c(0.75, 0.25), lat_desc, 1, 2018, d)
  cap <- new.env()
  local_mocked_globals(plot_relative_lambda_comparison = capture_plotter(cap))
  expect_output(
    compare_relative_lambda_files(r, l, list(2018L), "v", "mai", "out.pdf", ref_year = 2018),
    "lon coordinates not increasing")
  expect_equal(cap$args$lon, c(0.25, 0.75))
  expect_equal(cap$args$rel_data[, , 1], d[2:1, 2:1, 1])
  expect_equal(cap$args$lambda_data[, , 1], d[2:1, 2:1, 1])
})

test_that("relative and lambda files on different grids are an error", {
  tmp <- withr::local_tempdir()
  r <- make_ts_nc(file.path(tmp, "r.nc"), "v", c(0.25, 0.75), lat_desc, 1, 2018)
  l <- make_ts_nc(file.path(tmp, "l.nc"), "v", c(0.25, 1.25), lat_desc, 1, 2018)
  l_lat <- make_ts_nc(file.path(tmp, "l_lat.nc"), "v", c(0.25, 0.75), c(1.25, 0.25), 1, 2018)
  local_mocked_globals(plot_relative_lambda_comparison = function(...) stop("should not plot"))
  expect_error(
    compare_relative_lambda_files(r, l, list(2018L), "v", "mai", "out.pdf", ref_year = 2018),
    "grids differ")
  expect_error(
    compare_relative_lambda_files(r, l_lat, list(2018L), "v", "mai", "out.pdf", ref_year = 2018),
    "grids differ")
})
