source(testthat::test_path("..", "..", "tools", "netcdf_compare.R"), chdir = TRUE)

# Writes a 2x2x2 float variable `fertl_mai` with one NA cell.
write_tiny_nc <- function(path, values = NULL, na_index = 1, scaling_method = "lambda",
                          creation_date = "2026-01-01", compression = 4,
                          time_units = "years", var_comment = NULL) {
  if (is.null(values)) values <- seq(0.5, by = 0.25, length.out = 8)
  values[na_index] <- NA
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  lon <- ncdf4::ncdim_def("lon", "degrees_east", c(0.25, 0.75))
  lat <- ncdf4::ncdim_def("lat", "degrees_north", c(0.25, 0.75))
  time <- ncdf4::ncdim_def("time", time_units, c(2000, 2001))
  var <- ncdf4::ncvar_def("fertl_mai", "kg ha-1", list(lon, lat, time), missval = 1e20,
                          longname = "fertilizer", prec = "float", compression = compression)
  nc <- ncdf4::nc_create(path, var)
  on.exit(ncdf4::nc_close(nc))
  ncdf4::ncvar_put(nc, var, array(values, c(2, 2, 2)))
  if (!is.null(var_comment)) ncdf4::ncatt_put(nc, "fertl_mai", "comment", var_comment)
  ncdf4::ncatt_put(nc, 0, "scaling_method", scaling_method)
  ncdf4::ncatt_put(nc, 0, "creation_date", creation_date)
}

setup_dirs <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  list(ref = file.path(root, "ref"), new = file.path(root, "new"))
}

test_that("identical dirs report all OK", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"))
  write_tiny_nc(file.path(d$new, "a.nc"))
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(nrow(res), 1)
  expect_true(all(res$status == "OK"))
})

test_that("a single changed data value is DIFF", {
  d <- setup_dirs()
  base <- seq(0.5, by = 0.25, length.out = 8)
  changed <- base
  changed[5] <- changed[5] + 1e-3
  write_tiny_nc(file.path(d$ref, "a.nc"), base)
  write_tiny_nc(file.path(d$new, "a.nc"), changed)
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "DIFF")
  expect_match(res$detail, "data")
})

test_that("a moved NA is DIFF", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"), na_index = 1)
  write_tiny_nc(file.path(d$new, "a.nc"), na_index = 2)
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "DIFF")
})

test_that("creation_date differences are ignored", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"), creation_date = "2026-01-01")
  write_tiny_nc(file.path(d$new, "a.nc"), creation_date = "2026-12-31")
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "OK")
})

test_that("other global attribute differences are DIFF", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"), scaling_method = "lambda")
  write_tiny_nc(file.path(d$new, "a.nc"), scaling_method = "relative")
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "DIFF")
  expect_match(res$detail, "scaling_method")
})

test_that("different deflate level with same data is OK", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"), compression = 9)
  write_tiny_nc(file.path(d$new, "a.nc"), compression = 1)
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "OK")
})

test_that("missing and extra files are reported", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "only_ref.nc"))
  write_tiny_nc(file.path(d$new, "only_new.nc"))
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status[res$path == "only_ref.nc"], "MISSING")
  expect_equal(res$status[res$path == "only_new.nc"], "EXTRA")
})

test_that("dimension units differences are DIFF", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"), time_units = "years since 2014-1-1")
  write_tiny_nc(file.path(d$new, "a.nc"), time_units = "years since 2013-1-1")
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "DIFF")
  expect_match(res$detail, "dimension time units")
})

test_that("extra or changed variable attributes are DIFF", {
  d <- setup_dirs()
  write_tiny_nc(file.path(d$ref, "a.nc"))
  write_tiny_nc(file.path(d$new, "a.nc"), var_comment = "added")
  res <- compare_netcdf_dirs(d$ref, d$new)
  expect_equal(res$status, "DIFF")
  expect_match(res$detail, "attribute comment")
})
