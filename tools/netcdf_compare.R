# ============================================================================
# netcdf_compare.R
# ============================================================================
# Bit-for-bit comparison of the NetCDF files in two output directories.
# Function library only; sourcing it has no side effects. See
# tools/compare_netcdf_outputs.R for the CLI.
#
# Two files are equal when they have the same dimension names, lengths, units
# and values, the same variable names, the same missval and prec per variable,
# identical variable data (including the NA pattern), identical variable
# attributes (all of them), and the same global attributes except
# `creation_date`. Storage settings (compression level, file size) are not
# compared.
# ============================================================================

# Returns a character vector of mismatch reasons (empty when the files match).
compare_netcdf_files <- function(ref_path, new_path) {
  ref <- ncdf4::nc_open(ref_path)
  on.exit(ncdf4::nc_close(ref), add = TRUE)
  new <- ncdf4::nc_open(new_path)
  on.exit(ncdf4::nc_close(new), add = TRUE)

  reasons <- character(0)

  ref_dims <- names(ref$dim)
  new_dims <- names(new$dim)
  if (!identical(ref_dims, new_dims)) {
    reasons <- c(reasons, sprintf("dimension names differ (%s vs %s)",
                                  paste(ref_dims, collapse = ","), paste(new_dims, collapse = ",")))
  }
  for (d in intersect(ref_dims, new_dims)) {
    if (ref$dim[[d]]$len != new$dim[[d]]$len) {
      reasons <- c(reasons, sprintf("dimension %s length differs (%d vs %d)", d, ref$dim[[d]]$len, new$dim[[d]]$len))
    } else if (!identical(ref$dim[[d]]$vals, new$dim[[d]]$vals)) {
      reasons <- c(reasons, sprintf("dimension %s values differ", d))
    }
    if (!identical(ref$dim[[d]]$units, new$dim[[d]]$units)) {
      reasons <- c(reasons, sprintf("dimension %s units differ (%s vs %s)", d,
                                    ref$dim[[d]]$units, new$dim[[d]]$units))
    }
  }

  ref_vars <- names(ref$var)
  new_vars <- names(new$var)
  if (!identical(ref_vars, new_vars)) {
    reasons <- c(reasons, sprintf("variable names differ (%s vs %s)",
                                  paste(ref_vars, collapse = ","), paste(new_vars, collapse = ",")))
  }
  for (v in intersect(ref_vars, new_vars)) {
    for (field in c("missval", "prec")) {
      if (!identical(ref$var[[v]][[field]], new$var[[v]][[field]])) {
        reasons <- c(reasons, sprintf("variable %s %s differs", v, field))
      }
    }
    ref_var_atts <- ncdf4::ncatt_get(ref, v)
    new_var_atts <- ncdf4::ncatt_get(new, v)
    for (a in union(names(ref_var_atts), names(new_var_atts))) {
      if (!identical(ref_var_atts[[a]], new_var_atts[[a]])) {
        reasons <- c(reasons, sprintf("variable %s attribute %s differs", v, a))
      }
    }
    if (!identical(ncdf4::ncvar_get(ref, v), ncdf4::ncvar_get(new, v))) {
      reasons <- c(reasons, sprintf("variable %s data differs", v))
    }
  }

  ref_atts <- ncdf4::ncatt_get(ref, 0)
  new_atts <- ncdf4::ncatt_get(new, 0)
  ref_atts$creation_date <- NULL
  new_atts$creation_date <- NULL
  for (a in union(names(ref_atts), names(new_atts))) {
    if (!identical(ref_atts[[a]], new_atts[[a]])) {
      reasons <- c(reasons, sprintf("global attribute %s differs", a))
    }
  }

  reasons
}

# Compares every .nc file under ref_dir and new_dir (matched by relative path).
# Returns a data frame with columns path, status (OK, DIFF, MISSING = only in
# ref_dir, EXTRA = only in new_dir), detail, ref_bytes, new_bytes.
compare_netcdf_dirs <- function(ref_dir, new_dir) {
  ref_files <- list.files(ref_dir, pattern = "\\.nc$", recursive = TRUE)
  new_files <- list.files(new_dir, pattern = "\\.nc$", recursive = TRUE)
  paths <- sort(union(ref_files, new_files))

  size_of <- function(dir, path, present) {
    if (present) file.size(file.path(dir, path)) else NA_real_
  }

  rows <- lapply(paths, function(p) {
    in_ref <- p %in% ref_files
    in_new <- p %in% new_files
    status <- "OK"
    detail <- character(0)
    if (!in_new) {
      status <- "MISSING"
    } else if (!in_ref) {
      status <- "EXTRA"
    } else {
      detail <- compare_netcdf_files(file.path(ref_dir, p), file.path(new_dir, p))
      if (length(detail) > 0) status <- "DIFF"
    }
    data.frame(
      path = p,
      status = status,
      detail = paste(detail, collapse = "; "),
      ref_bytes = size_of(ref_dir, p, in_ref),
      new_bytes = size_of(new_dir, p, in_new),
      stringsAsFactors = FALSE
    )
  })

  if (length(rows) == 0) {
    return(data.frame(path = character(0), status = character(0), detail = character(0),
                      ref_bytes = numeric(0), new_bytes = numeric(0), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}
