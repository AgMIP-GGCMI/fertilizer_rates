# Tests for read_timeseries_year_slice() in fertilizer_scaling_functions.R.
#
# This regression ensures the new single-year extraction path returns the
# same [lon, lat] slice that the previous full historical read would have
# produced after canonicalizing latitude and then selecting the base year.

test_that("read_timeseries_year_slice matches the old full-read base-year slice", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "n-fertilizer-5crops_histsoc_annual_1850_2014.nc")

  lon <- seq(-179.75, by = 0.5, length.out = 3)
  lat <- seq(10, by = -5, length.out = 2)
  nyears <- 5
  start_year <- 1850
  base_year <- 1852
  base_idx <- base_year - start_year + 1

  data <- array(seq_len(length(lon) * length(lat) * nyears),
                dim = c(length(lon), length(lat), nyears))
  make_ts_nc(path, var_name = "fertl_c4ann", lon = lon, lat = lat,
             nyears = nyears, start_year = start_year, data = data)

  helper_slice <- read_timeseries_year_slice(path, "fertl_c4ann", base_year, start_year)

  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  full_data <- ncdf4::ncvar_get(nc, "fertl_c4ann")
  full_lat <- ncdf4::ncvar_get(nc, "lat")
  if (any(diff(full_lat) < 0)) {
    full_data <- full_data[, dim(full_data)[2]:1, ]
  }
  expected_slice <- full_data[, , base_idx]

  expect_equal(helper_slice, expected_slice)
})

test_that("read_timeseries_year_slice names the year when it is outside the file", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_ts_nc(path, var_name = "fertl_c4ann", lon = c(0, 1, 2), lat = c(10, 5),
             nyears = 5, start_year = 1850)
  expect_error(read_timeseries_year_slice(path, "fertl_c4ann", 1855, 1850),
               "Year 1855 is outside the time series range in", fixed = TRUE)
  expect_error(read_timeseries_year_slice(path, "fertl_c4ann", 1849, 1850),
               "Year 1849 is outside the time series range in", fixed = TRUE)
})

test_that("read_timeseries_year_slice passes missing file and variable errors through", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  expect_error(read_timeseries_year_slice(path, "fertl_c4ann", 1850, 1850),
               paste("Time series file does not exist:", path), fixed = TRUE)
  make_ts_nc(path, var_name = "fertl_c4ann", lon = c(0, 1, 2), lat = c(10, 5),
             nyears = 2, start_year = 1850)
  expect_error(read_timeseries_year_slice(path, "nope", 1850, 1850),
               "Variable nope not found in time series file", fixed = TRUE)
})

test_that("read_timeseries_year_slice keeps [lon, lat] dims for a 1xN grid", {
  path <- file.path(withr::local_tempdir(), "ts.nc")
  make_ts_nc(path, var_name = "fertl_c4ann", lon = 0, lat = c(10, 5, 0),
             nyears = 2, start_year = 1850,
             data = array(1:6, dim = c(1, 3, 2)))
  res <- read_timeseries_year_slice(path, "fertl_c4ann", 1851, 1850)
  expect_equal(dim(res), c(1, 3))
  expect_equal(as.vector(res), c(6, 5, 4))
})
