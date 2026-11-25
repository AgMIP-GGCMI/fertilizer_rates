# Tests for read_timeseries_nc() and mask_fill_values() in
# fertilizer_scaling_functions.R.

make_desc_lat_ts <- function(path, nyears = 4, missval = 1e20, data = NULL) {
  lon <- seq(-179.75, by = 0.5, length.out = 3)
  lat <- c(10, 5)
  if (is.null(data)) {
    data <- array(seq_len(3 * 2 * nyears), dim = c(3, 2, nyears))
  }
  make_ts_nc(path, var_name = "fertl_c4ann", lon = lon, lat = lat,
             nyears = nyears, start_year = 2000, data = data,
             missval = missval)
  list(lon = lon, lat = lat, data = data)
}

test_that("read_timeseries_nc flips a descending lat and the data with it", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  src <- make_desc_lat_ts(path)

  res <- read_timeseries_nc(path, "fertl_c4ann")

  expect_equal(res$lat, c(5, 10))
  expect_equal(res$lon, src$lon)
  expect_equal(dim(res$data), c(3, 2, 4))
  expect_equal(res$data, src$data[, 2:1, ], ignore_attr = TRUE)
})

test_that("read_timeseries_nc reads only the requested time steps", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  src <- make_desc_lat_ts(path)

  res <- read_timeseries_nc(path, "fertl_c4ann", time_start = 2, time_count = 2)

  expect_equal(dim(res$data), c(3, 2, 2))
  expect_equal(res$data, src$data[, 2:1, 2:3], ignore_attr = TRUE)
})

test_that("read_timeseries_nc keeps a single time step 3-D", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  src <- make_desc_lat_ts(path)

  res <- read_timeseries_nc(path, "fertl_c4ann", time_start = 3, time_count = 1)

  expect_equal(dim(res$data), c(3, 2, 1))
  expect_equal(res$data[, , 1], src$data[, 2:1, 3], ignore_attr = TRUE)
})

test_that("read_timeseries_nc masks a 1e20 cell and a custom _FillValue cell", {
  tmp <- withr::local_tempdir()

  data <- array(1, dim = c(3, 2, 2))
  data[1, 1, 1] <- 1e20
  path_big <- file.path(tmp, "big.nc")
  make_desc_lat_ts(path_big, nyears = 2, data = data)
  res_big <- read_timeseries_nc(path_big, "fertl_c4ann")
  # lat is flipped, so source lat index 1 is now index 2
  expect_true(is.na(res_big$data[1, 2, 1]))
  expect_equal(sum(is.na(res_big$data)), 1)

  data[1, 1, 1] <- -9999
  path_fill <- file.path(tmp, "fill.nc")
  make_desc_lat_ts(path_fill, nyears = 2, missval = -9999, data = data)
  res_fill <- read_timeseries_nc(path_fill, "fertl_c4ann")
  expect_true(is.na(res_fill$data[1, 2, 1]))
  expect_equal(sum(is.na(res_fill$data)), 1)
})

test_that("mask_fill_values masks the variable's _FillValue and |x| >= 1e19", {
  path <- file.path(withr::local_tempdir(), "fill.nc")
  make_desc_lat_ts(path, missval = -9999)
  nc <- ncdf4::nc_open(path)
  withr::defer(ncdf4::nc_close(nc))

  x <- c(1, -9999, 2, 1e19, -3e20, 5)
  expect_equal(mask_fill_values(x, nc, "fertl_c4ann"),
               c(1, NA, 2, NA, NA, 5))
})

test_that("read_timeseries_nc errors on a missing file", {
  path <- file.path(withr::local_tempdir(), "absent.nc")
  expect_error(read_timeseries_nc(path, "fertl_c4ann"),
               paste("Time series file does not exist:", path),
               fixed = TRUE)
})

test_that("read_timeseries_nc errors on a missing variable", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_desc_lat_ts(path)
  expect_error(read_timeseries_nc(path, "nope"),
               paste0("Variable nope not found in time series file: ", path),
               fixed = TRUE)
})

test_that("read_timeseries_nc errors when the steps are out of range", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_desc_lat_ts(path, nyears = 4)
  expect_error(read_timeseries_nc(path, "fertl_c4ann", time_start = 3, time_count = 3),
               paste0("Time steps 3-5 are outside the 4 time steps in ", path),
               fixed = TRUE)
  expect_error(read_timeseries_nc(path, "fertl_c4ann", time_start = 0, time_count = 1),
               "outside the 4 time steps", fixed = TRUE)
})

test_that("read_timeseries_nc errors when time_start is past the end with the default count", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_desc_lat_ts(path, nyears = 4)
  expect_error(read_timeseries_nc(path, "fertl_c4ann", time_start = 5),
               "outside the 4 time steps", fixed = TRUE)
})

test_that("read_timeseries_nc errors on a time_count of 0 or below -1", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_desc_lat_ts(path, nyears = 4)
  expect_error(read_timeseries_nc(path, "fertl_c4ann", time_start = 1, time_count = 0),
               "time_count must be -1", fixed = TRUE)
  expect_error(read_timeseries_nc(path, "fertl_c4ann", time_start = 1, time_count = -2),
               "time_count must be -1", fixed = TRUE)
})

test_that("read_timeseries_nc reads a 1x1 grid as a 1x1x1 array", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_ts_nc(path, var_name = "fertl_c4ann", lon = 10, lat = 20, nyears = 3,
             start_year = 2000, data = array(c(7, 8, 9), dim = c(1, 1, 3)))
  res <- read_timeseries_nc(path, "fertl_c4ann", time_start = 2, time_count = 1)
  expect_equal(dim(res$data), c(1, 1, 1))
  expect_equal(res$data[1, 1, 1], 8)
  expect_equal(res$lon, 10)
  expect_equal(res$lat, 20)
})
