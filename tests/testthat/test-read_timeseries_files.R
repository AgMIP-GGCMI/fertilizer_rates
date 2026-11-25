# tests/testthat/test-read_timeseries_files.R
#
# Tests for read_timeseries_files() in fertilizer_scaling_functions.R.

lon <- c(0.25, 0.75); lat_desc <- c(0.75, 0.25)

test_that("files are concatenated along time and lat is flipped to ascending", {
  tmp <- withr::local_tempdir()
  a <- array(c(1, 2, 3, 4), dim = c(2, 2, 1))           # [lon, lat(desc), 1]
  b <- array(c(5, 6, 7, 8, 9, 10, 11, 12), dim = c(2, 2, 2))
  f1 <- make_ts_nc(file.path(tmp, "a.nc"), "c4ann_fertl", lon, lat_desc, 1, 2018, a)
  f2 <- make_ts_nc(file.path(tmp, "b.nc"), "c4ann_fertl", lon, lat_desc, 2, 2019, b)
  ts <- read_timeseries_files(c(f1, f2), list(2018L, 2019:2020), "c4ann_fertl")
  expect_equal(dim(ts$data), c(2L, 2L, 3L))
  expect_equal(ts$lat, c(0.25, 0.75))
  expect_equal(ts$years, 2018:2020)
  expect_equal(ts$data[, , 1], a[, 2:1, 1])
  expect_equal(ts$data[, , 3], b[, 2:1, 2])
})

test_that("wrong year count, differing grids and non-contiguous years are errors", {
  tmp <- withr::local_tempdir()
  f <- make_ts_nc(file.path(tmp, "a.nc"), "c4ann_fertl", lon, lat_desc, 2, 2018)
  g <- make_ts_nc(file.path(tmp, "g.nc"), "c4ann_fertl", c(0.25, 1.25), lat_desc, 2, 2020)
  h <- make_ts_nc(file.path(tmp, "h.nc"), "c4ann_fertl", lon, lat_desc, 2, 2021)
  expect_error(read_timeseries_files(f, list(2018L), "c4ann_fertl"),
               "has 2 time steps but 1 years were expected")
  expect_error(read_timeseries_files(c(f, g), list(2018:2019, 2020:2021), "c4ann_fertl"),
               "grids differ between files")
  expect_error(read_timeseries_files(c(f, h), list(2018:2019, 2021:2022), "c4ann_fertl"),
               "years are not contiguous")
})

test_that("grids differing only in lat are an error", {
  tmp <- withr::local_tempdir()
  f <- make_ts_nc(file.path(tmp, "a.nc"), "c4ann_fertl", lon, lat_desc, 1, 2018)
  g <- make_ts_nc(file.path(tmp, "g.nc"), "c4ann_fertl", lon, c(1.25, 0.25), 1, 2019)
  expect_error(read_timeseries_files(c(f, g), list(2018L, 2019L), "c4ann_fertl"),
               "grids differ between files")
})

test_that("malformed arguments are errors", {
  tmp <- withr::local_tempdir()
  f <- make_ts_nc(file.path(tmp, "a.nc"), "c4ann_fertl", lon, lat_desc, 2, 2018)
  expect_error(read_timeseries_files(f, 2018:2019, "c4ann_fertl"),
               "read_timeseries_files: years_list must be a list")
  expect_error(read_timeseries_files(character(0), list(), "c4ann_fertl"),
               "read_timeseries_files: no files given")
  expect_error(read_timeseries_files(f, list(c(2018L, NA)), "c4ann_fertl"),
               "read_timeseries_files: years contain NA")
})
