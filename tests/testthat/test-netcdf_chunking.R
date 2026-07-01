# Tests for NetCDF chunking choices used by write_netcdf_file() in
# fertilizer_scaling_functions.R.

test_that("NetCDF variable chunking is full-space x single-time", {
  tmp <- withr::local_tempfile(fileext = ".nc")

  lon <- seq(-179.75, by = 0.5, length.out = 4)
  lat <- seq(-89.75, by = 0.5, length.out = 3)
  yrs <- 2015:2017

  dim_lon <- ncdf4::ncdim_def("lon", "degrees_east", lon)
  dim_lat <- ncdf4::ncdim_def("lat", "degrees_north", lat)
  dim_time <- ncdf4::ncdim_def(
    "time",
    "years since 2014-1-1 00:00:00",
    yrs - 2014
  )

  # Match the production writer's chunking contract:
  # [lon, lat, time] -> chunks [nlon, nlat, 1].
  chunk_sizes <- c(length(lon), length(lat), 1)

  ncv <- ncdf4::ncvar_def(
    name = "fertl_mai",
    units = "kg ha-1 yr-1",
    dim = list(dim_lon, dim_lat, dim_time),
    missval = 1.e+20,
    prec = "float",
    compression = 9,
    chunksizes = chunk_sizes,
    verbose = FALSE
  )

  nc <- ncdf4::nc_create(tmp, list(ncv), verbose = FALSE)
  on.exit(ncdf4::nc_close(nc), add = TRUE)

  arr <- array(seq_len(length(lon) * length(lat) * length(yrs)),
               dim = c(length(lon), length(lat), length(yrs)))
  ncdf4::ncvar_put(nc, varid = ncv, arr)
  on.exit(NULL, add = FALSE)
  ncdf4::nc_close(nc)

  nc2 <- ncdf4::nc_open(tmp)
  on.exit(ncdf4::nc_close(nc2), add = TRUE)

  actual <- nc2$var[["fertl_mai"]]$chunksizes
  expect_equal(actual, chunk_sizes)
})
