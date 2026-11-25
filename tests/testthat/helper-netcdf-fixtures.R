# tests/testthat/helper-netcdf-fixtures.R
#
# Builders for tiny synthetic NetCDFs used by the coverage tests.
#
# The 5-min spatial NetCDFs and the time-series NetCDFs follow the
# variable/dim schema that fertilizer_scaling_functions.R reads in
# main(): 5-min files have a "<input_crop>Napprate" variable with
# "longitude"/"latitude" dims (and optionally a time dim), while TS
# files have a "<funcgroup>" variable (e.g. "fertl_c4ann") with
# "lon"/"lat"/"time" dims.

# Write one or more variables on a [lon, lat] grid, with an optional time
# dimension. vars: named list of arrays. Used for NPKGRIDS/CROPGRIDS-style
# files (2-D, "lon"/"lat") and, through make_5min_spatial_nc(), for the
# Mueller et al. 5-arcmin files ("longitude"/"latitude", optional time).
make_grids_nc <- function(path, lon, lat, vars, dim_names = c("lon", "lat"),
                          units = "-", missval = NULL, time = NULL) {
  dims <- list(ncdf4::ncdim_def(dim_names[1], "degrees_east", lon),
               ncdf4::ncdim_def(dim_names[2], "degrees_north", lat))
  if (!is.null(time)) dims[[3]] <- ncdf4::ncdim_def("time", "years", time)
  ncvs <- lapply(names(vars), function(nm)
    ncdf4::ncvar_def(nm, units, dims, missval = missval, prec = "float"))
  nc <- ncdf4::nc_create(path, ncvs)
  for (k in seq_along(ncvs)) ncdf4::ncvar_put(nc, ncvs[[k]], vars[[k]])
  ncdf4::nc_close(nc)
  invisible(path)
}

make_5min_spatial_nc <- function(path, input_crop, lon, lat,
                                 data = NULL, time = NULL) {
  if (is.null(data)) {
    data <- if (is.null(time)) {
      matrix(100, nrow = length(lon), ncol = length(lat))
    } else {
      array(100, dim = c(length(lon), length(lat), length(time)))
    }
  }
  make_grids_nc(path, lon, lat,
                setNames(list(data), paste0(input_crop, "Napprate")),
                dim_names = c("longitude", "latitude"),
                units = "kg ha-1 yr-1", missval = 1e20, time = time)
}

make_ts_nc <- function(path, var_name, lon, lat, nyears,
                       start_year, data = NULL, missval = 1e20) {
  nlon <- length(lon); nlat <- length(lat)
  dim_lon <- ncdf4::ncdim_def("lon", "degrees_east", lon)
  dim_lat <- ncdf4::ncdim_def("lat", "degrees_north", lat)
  dim_time <- ncdf4::ncdim_def(
    "time",
    paste("years since", start_year - 1, "-1-1 00:00:00"),
    seq_len(nyears)
  )
  if (is.null(data)) data <- array(50, dim = c(nlon, nlat, nyears))
  ncv <- ncdf4::ncvar_def(var_name, "kg ha-1 yr-1",
                          dim = list(dim_lon, dim_lat, dim_time),
                          missval = missval, prec = "float")
  nc <- ncdf4::nc_create(path, list(ncv))
  ncdf4::ncvar_put(nc, ncv, data)
  ncdf4::nc_close(nc)
  invisible(path)
}

# Build a per-test root layout for output_base_path / base_path_timeseries
# overrides. Returns a list of the paths so tests can address subdirs by name.
make_layout_dirs <- function(root) {
  dir.create(file.path(root, "histsoc", "relative"), recursive = TRUE,
             showWarnings = FALSE)
  dir.create(file.path(root, "histsoc", "lambda"), recursive = TRUE,
             showWarnings = FALSE)
  invisible(root)
}
