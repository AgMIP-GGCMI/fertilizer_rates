# Tests for write_fertilizer_netcdf() in fertilizer_scaling_functions.R:
# the chunking and compression choices of the output variable, the global
# attributes, and that the caller's array is left unmodified.

make_writer_inputs <- function() {
  lon <- seq(-179.75, by = 0.5, length.out = 4)
  lat <- seq(-89.75, by = 0.5, length.out = 3)
  yrs <- 2015:2017
  dim_time <- ncdf4::ncdim_def("time", "years since 2014-1-1 00:00:00", yrs - 2014)
  arr <- array(as.numeric(seq_len(length(lon) * length(lat) * length(yrs))),
               dim = c(length(lon), length(lat), length(yrs)))
  list(lon = lon, lat = lat, dim_time = dim_time, arr = arr)
}

test_that("NetCDF variable chunking is full-space x single-time", {
  tmp <- withr::local_tempfile(fileext = ".nc")
  x <- make_writer_inputs()

  write_fertilizer_netcdf(x$arr, x$lon, x$lat, x$dim_time, tmp, "mai",
                          list(source = "test source"))

  nc <- ncdf4::nc_open(tmp)
  on.exit(ncdf4::nc_close(nc), add = TRUE)

  expect_equal(nc$var[["fertl_mai"]]$chunksizes, c(length(x$lon), length(x$lat), 1))
  expect_equal(nc$var[["fertl_mai"]]$compression, 6)
  expect_equal(ncdf4::ncatt_get(nc, 0, "source")$value, "test source")
})

test_that("write_fertilizer_netcdf creates the directory and returns the path invisibly", {
  tmp <- file.path(withr::local_tempdir(), "a", "b", "out.nc")
  x <- make_writer_inputs()

  res <- withVisible(write_fertilizer_netcdf(x$arr, x$lon, x$lat, x$dim_time, tmp, "mai", list(k = "v")))

  expect_false(res$visible)
  expect_equal(res$value, tmp)
  expect_true(file.exists(tmp))
})

test_that("write_fertilizer_netcdf does not modify the caller's array", {
  tmp <- withr::local_tempfile(fileext = ".nc")
  x <- make_writer_inputs()
  x$arr[2, 2, 2] <- NA
  # `+ 0` forces a real copy; a plain assignment would share memory with x$arr and weaken this test.
  before <- x$arr + 0

  write_fertilizer_netcdf(x$arr, x$lon, x$lat, x$dim_time, tmp, "mai", list(k = "v"))

  expect_true(is.na(x$arr[2, 2, 2]))
  expect_identical(x$arr, before)
})
