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
