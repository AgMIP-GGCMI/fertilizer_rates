# ============================================================================
# Shared Function Definitions for fertilizer_scaling.R
# ============================================================================
# Sourced by fertilizer_scaling.R. Keep this file function-definitions-only so
# it is safe to source from tests or other scripts without side effects.
# ============================================================================

source("fertilizer_scaling_plot_diagnostics_functions.R")

# ============================================================================
# FUNCTION: aggregate_to_halfdegree
# ============================================================================
# Aggregate spatial data from 5 arcmin to 0.5 degree resolution
#
# Args:
#   data_5min: Array of data at 5 arcmin resolution [4320 x 2160]
#   lon_5min: Longitude values for 5 arcmin grid
#   lat_5min: Latitude values for 5 arcmin grid
#
# Returns:
#   List with:
#     data: Aggregated data at 0.5 degree [720 x 360]
#     lon: Longitude values for 0.5 degree grid
#     lat: Latitude values for 0.5 degree grid
#
# Method:
#   Averages 6x6 blocks (36 cells) into single 0.5 degree cells
#   NA values are ignored in averaging (unless all NA)
# ============================================================================
aggregate_to_halfdegree <- function(data_5min, lon_5min, lat_5min) {
  # input: 4320 x 2160 (5 arcmin)
  # output: 720 x 360 (0.5 degree)
  # aggregation factor: 6 cells in each direction (6x6 = 36 cells per output cell)

  nlon_out <- 720
  nlat_out <- 360
  agg_factor <- 6

  # Derive output coordinates by averaging each 6-cell block of the input
  # coordinates rather than synthesizing from scratch, so we inherit
  # whatever convention the input file uses (Mueller 5-min files are
  # north->south).
  lon_halfdeg <- colMeans(matrix(lon_5min, nrow = agg_factor))
  lat_halfdeg <- colMeans(matrix(lat_5min, nrow = agg_factor))

  # create output array
  data_halfdeg <- array(NA, dim = c(nlon_out, nlat_out))

  # vectorized aggregation using array operations
  # process one output longitude at a time (still faster than nested loop)
  for (i in 1:nlon_out) {
    i_start <- (i - 1) * agg_factor + 1
    i_end <- i * agg_factor

    # extract longitude slice for all latitudes at once
    lon_slice <- data_5min[i_start:i_end, ]

    # vectorized aggregation over latitude
    for (j in 1:nlat_out) {
      j_start <- (j - 1) * agg_factor + 1
      j_end <- j * agg_factor

      # extract block and calculate mean
      block <- lon_slice[, j_start:j_end]
      data_halfdeg[i, j] <- mean(block, na.rm = TRUE)
      if (is.nan(data_halfdeg[i, j])) data_halfdeg[i, j] <- NA
    }
  }

  # Canonicalize to ascending lat with data aligned south->north along the
  # lat axis. This gives downstream code (write_netcdf_file, plot helpers,
  # fields::image.plot) an unambiguous contract regardless of which
  # convention the input file used. rev() only fixes the case where the
  # input is monotonically descending; a non-monotonic lat axis would
  # silently pass through, so verify strict ascending order after.
  if (any(diff(lat_halfdeg) < 0)) {
    lat_halfdeg <- rev(lat_halfdeg)
    data_halfdeg <- data_halfdeg[, ncol(data_halfdeg):1]
  }
  if (any(diff(lat_halfdeg) <= 0)) {
    stop("aggregate_to_halfdegree: lat_halfdeg is not strictly ascending ",
         "after canonicalization (input lat is non-monotonic).")
  }
  # lon_halfdeg is taken directly from the input with no canonicalization,
  # so a non-monotonic input lon would silently propagate. Production
  # 5-min files are monotonic; this catches a corrupted or hand-built input.
  if (any(diff(lon_halfdeg) <= 0)) {
    stop("aggregate_to_halfdegree: lon_halfdeg is not strictly ascending ",
         "(input lon is non-monotonic).")
  }

  return(list(data = data_halfdeg, lon = lon_halfdeg, lat = lat_halfdeg))
}


# ============================================================================
# FUNCTION: prepare_scaling_inputs
# ============================================================================
# Common setup for scale_with_timeseries: validate base_year, extract the base
# year time slice, and compute the valid_base mask.
#
# Returns: list(base_idx, base_timeseries, valid_base).
# ============================================================================
prepare_scaling_inputs <- function(base_rate, timeseries, base_year,
                                   start_year, end_year,
                                   base_timeseries_override = NULL) {
  ntimes <- dim(timeseries)[3]
  base_idx <- base_year - start_year + 1
  if (!is.null(base_timeseries_override)) {
    base_timeseries <- base_timeseries_override
    if (all(is.na(base_idx)) || base_idx < 1 || base_idx > ntimes) {
      base_idx <- NA_integer_
    }
  } else {
    if (base_idx < 1 || base_idx > ntimes) {
      stop(paste("Base year", base_year, "is outside the time series range",
                 start_year, "-", end_year))
    }
    base_timeseries <- timeseries[, , base_idx]
  }
  valid_base <- is.finite(base_rate) & base_rate > 0
  list(
    base_idx        = base_idx,
    base_timeseries = base_timeseries,
    valid_base      = valid_base
  )
}

# ==========================================================================
# FUNCTION: read_timeseries_year_slice
# ==========================================================================
# Read a single [lon, lat] year slice from a time-series NetCDF without
# loading the full time axis into memory.
# ===========================================================================
read_timeseries_year_slice <- function(ts_file, var_name, year, file_start_year) {
  if (!file.exists(ts_file)) {
    stop(paste("Time series file does not exist:", ts_file))
  }

  nc <- nc_open(ts_file)
  on.exit(nc_close(nc), add = TRUE)

  if (!(var_name %in% names(nc$var))) {
    stop(paste("Variable", var_name, "not found in time series file"))
  }

  slice_idx <- year - file_start_year + 1
  if (slice_idx < 1 || slice_idx > nc$var[[var_name]]$varsize[3]) {
    stop(paste("Year", year, "is outside the time series range in", ts_file))
  }

  year_slice <- ncvar_get(nc, varid = var_name,
                          start = c(1, 1, slice_idx), count = c(-1, -1, 1))

  # Normalize to [lon, lat, time] so downstream indexing is shape-invariant
  # regardless of whether ncvar_get dropped the singleton time dimension.
  if (length(dim(year_slice)) == 2) {
    year_slice <- array(year_slice, dim = c(nrow(year_slice), ncol(year_slice), 1))
  }

  ts_lat <- ncvar_get(nc, varid = "lat")
  if (any(diff(ts_lat) < 0)) {
    year_slice <- year_slice[, dim(year_slice)[2]:1, , drop = FALSE]
  }

  missval <- ncatt_get(nc, varid = var_name, attname = "_FillValue")
  if (missval$hasatt) {
    year_slice[year_slice == missval$value] <- NA
  }
  year_slice[abs(year_slice) >= 1e+19] <- NA

  year_slice[, , 1, drop = FALSE][, , 1]
}

# ============================================================================
# FUNCTION: scale_relative_timestep
# ============================================================================
# Compute one [lon, lat] scaled slice using the relative-change method:
#   scaled = base_rate * (ts_t / base_timeseries)
# Cells where base_rate is invalid remain NA; cells where base_rate is valid
# but base_timeseries is invalid get base_rate (rel_change defaults to 1).
# ============================================================================
scale_relative_timestep <- function(base_rate, ts_t, base_timeseries, valid_base) {
  result <- array(NA_real_, dim = dim(base_rate))
  valid_ts_base <- valid_base & is.finite(base_timeseries) & base_timeseries > 0
  rel_change <- array(1, dim = dim(base_rate))
  rel_change[valid_ts_base] <- ts_t[valid_ts_base] / base_timeseries[valid_ts_base]
  result[valid_base] <- base_rate[valid_base] * rel_change[valid_base]
  result
}

# ============================================================================
# FUNCTION: compute_lambda
# ============================================================================
# Compute the per-cell lambda exponent used by the lambda scaling method.
# lambda = sqrt(base_timeseries / base_rate) when base_timeseries < base_rate
# (at cells where both are valid and positive). Otherwise lambda = 1.
# ============================================================================
compute_lambda <- function(base_rate, base_timeseries, valid_base) {
  nlon <- dim(base_rate)[1]
  nlat <- dim(base_rate)[2]
  lambda <- array(1, dim = c(nlon, nlat))
  for (i in 1:nlon) {
    for (j in 1:nlat) {
      if (valid_base[i, j] && !is.na(base_timeseries[i, j]) && base_timeseries[i, j] > 0) {
        ts_base_val <- base_timeseries[i, j]
        spatial_val <- base_rate[i, j]
        if (ts_base_val < spatial_val) {
          lambda[i, j] <- sqrt(ts_base_val / spatial_val)
        } else {
          lambda[i, j] <- 1
        }
      }
    }
  }
  lambda
}

# ============================================================================
# FUNCTION: scale_lambda_timestep
# ============================================================================
# Compute one [lon, lat] scaled slice using the lambda scaling method.
#   scaled = base * [1 + (ts_t - ts_base) / base * (base / ts_base) ^ lambda]
# Clamped to >= 0. Invalid cells remain NA.
#
# On an internal error, this function re-throws a 'lambda_timestep_error'
# condition carrying i, j, nlon, nlat so the caller can enrich the
# diagnostic with time-step-level context (t, scaled_data dims).
# ============================================================================
scale_lambda_timestep <- function(base_rate, ts_t, base_timeseries,
                                  valid_base, lambda) {
  nlon <- dim(base_rate)[1]
  nlat <- dim(base_rate)[2]
  tryCatch({
    result <- array(NA_real_, dim = c(nlon, nlat))
    for (i in 1:nlon) {
      for (j in 1:nlat) {
        if (valid_base[i, j]) {
          if (base_rate[i, j] == 0) {
            # For true zero-base cells (not NA), carry the raw TS signal.
            result[i, j] <- ts_t[i, j]
          } else if (!is.na(base_timeseries[i, j]) && base_timeseries[i, j] > 0) {
            fert_diff <- ts_t[i, j] - base_timeseries[i, j]
            ratio_base <- base_rate[i, j] / base_timeseries[i, j]
            ratio_term <- ratio_base ^ lambda[i, j]
            result[i, j] <- base_rate[i, j] * (1 + (fert_diff / base_rate[i, j]) * ratio_term)
          }
          if (!is.na(result[i, j]) && result[i, j] < 0) {
            result[i, j] <- 0
          }
        }
      }
    }
    result
  }, error = function(e) {
    stop(structure(
      class = c("lambda_timestep_error", "error", "condition"),
      list(
        message  = e$message,
        call     = e$call,
        original = e,
        i        = i,
        j        = j,
        nlon     = nlon,
        nlat     = nlat
      )
    ))
  })
}

# ============================================================================
# FUNCTION: diagnose_extreme_values
# ============================================================================
# Print a warning and details for cells whose scaled value exceeds
# 1000 kg/ha. Never alters scaled_data. Returns invisibly.
# ============================================================================
diagnose_extreme_values <- function(scaled_data, base_rate, base_timeseries,
                                    timeseries, start_year) {
  max_val <- max(scaled_data, na.rm = TRUE)
  if (max_val > 1000) {
    print(paste("WARNING: Maximum scaled value is", round(max_val, 1), "kg/ha"))
    extreme_threshold <- 1000
    extreme_cells <- which(
      apply(scaled_data, c(1, 2), function(x) any(x > extreme_threshold, na.rm = TRUE)),
      arr.ind = TRUE
    )
    if (nrow(extreme_cells) > 0) {
      print(paste("Found", nrow(extreme_cells), "cells with values >",
                  extreme_threshold, "kg/ha"))
      n_report <- min(5, nrow(extreme_cells))
      for (i in 1:n_report) {
        idx_lon <- extreme_cells[i, 1]
        idx_lat <- extreme_cells[i, 2]
        ts_cell <- scaled_data[idx_lon, idx_lat, ]
        max_year_idx <- which.max(ts_cell)
        max_year <- start_year + max_year_idx - 1
        print(paste("\nCell", i, "at lon index", idx_lon, ", lat index", idx_lat))
        print(paste("  Base rate (year 2000 spatial):",
                    round(base_rate[idx_lon, idx_lat], 2), "kg/ha"))
        print(paste("  TS at base year (2000):",
                    round(base_timeseries[idx_lon, idx_lat], 2), "kg/ha"))
        print(paste("  TS at year", max_year, ":",
                    round(timeseries[idx_lon, idx_lat, max_year_idx], 2), "kg/ha"))
        print(paste("  Relative change:",
                    round(timeseries[idx_lon, idx_lat, max_year_idx] / base_timeseries[idx_lon, idx_lat], 2)))
        print(paste("  Scaled value at year", max_year, ":",
                    round(ts_cell[max_year_idx], 2), "kg/ha"))
        ratio_base_to_ts <- base_rate[idx_lon, idx_lat] / base_timeseries[idx_lon, idx_lat]
        if (abs(ratio_base_to_ts - 1) > 0.5) {
          print(paste("  MISMATCH: Spatial base / TS base ratio =",
                      round(ratio_base_to_ts, 2)))
        }
      }
    }
  }
  invisible(NULL)
}

# ============================================================================
# FUNCTION: scale_with_timeseries
# ============================================================================
# Scale fertilizer rates to a time series using the given method
#
# Args:
#   base_rate: Spatial pattern at 0.5 degree for base year [lon, lat]
#   timeseries: Temporal data from ISIMIP3b [lon, lat, time]
#   base_year: Reference year for scaling (default: 2000)
#   start_year: First year in time series
#   end_year: Last year in time series
#   method: Scaling method - "relative" (argument default) or "lambda"
#           (production; main() passes each entry of scaling_methods)
#
# Returns:
#   Scaled data [lon, lat, time]
#
# Method options:
#   "relative": scale each cell by timeseries[t] / timeseries[base_year]
#   "lambda": precipitation-style scaling with anomalies and lambda correction
# ============================================================================
scale_with_timeseries <- function(base_rate, timeseries, base_year = 2000,
                                   start_year, end_year, method = "relative",
                                   base_timeseries = NULL) {
  print(paste("Using scaling method:", method))
  lambda_max_rate <- 500
  delayed_anchor_threshold <- 1
  
  # get dimensions
  nlon <- dim(timeseries)[1]
  nlat <- dim(timeseries)[2]
  ntimes <- dim(timeseries)[3]

  # validate + precompute common pieces
  prep <- prepare_scaling_inputs(base_rate, timeseries, base_year,
                                 start_year, end_year,
                                 base_timeseries_override = base_timeseries)
  base_idx         <- prep$base_idx
  base_timeseries <- prep$base_timeseries
  valid_base      <- prep$valid_base

  # create output array [lon, lat, time]
  scaled_data <- array(NA, dim = c(nlon, nlat, ntimes))
  
  if (method == "relative") {
    # Relative method keeps the historical behavior: only base_rate > 0 cells
    # are considered valid for scaling.
    for (t in 1:ntimes) {
      scaled_data[, , t] <- scale_relative_timestep(
        base_rate, timeseries[, , t], base_timeseries, valid_base
      )
    }

  } else if (method == "lambda") {
    # Lambda method: treat base-rate zeros differently from NA. NA cells remain
    # invalid, while zero-base cells copy the raw TS trajectory.
    valid_base_lambda <- is.finite(base_rate) & base_rate >= 0

    # For positive-base cells where TS(base_year) is close to zero, use a
    # delayed anchor year y* (first t >= base year with TS(t) >= threshold)
    # and scale by TS(t)/TS(y*). This avoids undefined lambda behavior at
    # TS(base_year) ~= 0 while preserving the base-map amplitude at y*.
    delayed_anchor_cells <- is.finite(base_rate) & base_rate > 0 &
      is.finite(base_timeseries) & base_timeseries < delayed_anchor_threshold
    delayed_anchor_value <- array(NA_real_, dim = c(nlon, nlat))

    if (any(delayed_anchor_cells)) {
      # Always search the full available series for the first anchor year with
      # TS >= threshold. For future scenarios base_idx is already NA so this
      # makes no difference there; for histsoc it is essential because the
      # base year (2000) may itself be zero while earlier years are positive.
      for (i in 1:nlon) {
        for (j in 1:nlat) {
          if (delayed_anchor_cells[i, j]) {
            ts_cell <- timeseries[i, j, 1:ntimes]
            cand <- which(is.finite(ts_cell) & ts_cell >= delayed_anchor_threshold)
            if (length(cand) > 0) {
              delayed_anchor_value[i, j] <- ts_cell[cand[1]]
            }
          }
        }
      }
    }
    delayed_anchor_ready <- delayed_anchor_cells &
      is.finite(delayed_anchor_value) & delayed_anchor_value > 0
    delayed_anchor_unresolved <- delayed_anchor_cells & !delayed_anchor_ready

    # Lambda method: see compute_lambda and scale_lambda_timestep.
    lambda <- compute_lambda(base_rate, base_timeseries, valid_base_lambda)

    for (t in 1:ntimes) {
      tryCatch({
        scaled_data[, , t] <- scale_lambda_timestep(
          base_rate, timeseries[, , t], base_timeseries, valid_base_lambda, lambda
        )

        # Apply delayed-anchor fallback for TS(base_year) < threshold.
        if (any(delayed_anchor_ready)) {
          ts_t <- timeseries[, , t]
          fallback_cells <- delayed_anchor_ready & is.finite(ts_t)
          if (any(fallback_cells)) {
            slice <- scaled_data[, , t]
            slice[fallback_cells] <- base_rate[fallback_cells] *
              (ts_t[fallback_cells] / delayed_anchor_value[fallback_cells])
            slice[!is.na(slice) & slice < 0] <- 0
            scaled_data[, , t] <- slice
          }
        }

        # If no anchor year (TS>=threshold) exists for a delayed-anchor cell,
        # fall back to raw TS(t) so values do not remain NA indefinitely.
        if (any(delayed_anchor_unresolved)) {
          ts_t <- timeseries[, , t]
          unresolved_cells <- delayed_anchor_unresolved & is.finite(ts_t)
          if (any(unresolved_cells)) {
            slice <- scaled_data[, , t]
            slice[unresolved_cells] <- ts_t[unresolved_cells]
            slice[!is.na(slice) & slice < 0] <- 0
            scaled_data[, , t] <- slice
          }
        }
      }, lambda_timestep_error = function(e) {
        cat(sprintf("\nERROR in lambda loop at time step t=%d:\n", t))
        cat(sprintf("  Message: %s\n", e$message))
        cat(sprintf("  Last indices: i=%d (max=%d), j=%d (max=%d)\n",
                    e$i, e$nlon, e$j, e$nlat))
        cat(sprintf("  scaled_data dims: %d x %d x %d\n",
                    dim(scaled_data)[1], dim(scaled_data)[2], dim(scaled_data)[3]))
        stop(e$original)
      })
    }

    # Apply a hard cap for lambda outputs to avoid implausibly high rates.
    scaled_data[!is.na(scaled_data)] <- pmin(
      scaled_data[!is.na(scaled_data)],
      lambda_max_rate
    )
    
  } else {
    stop(paste("Unknown scaling method:", method))
  }
  
  diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                          timeseries, start_year)

  return(scaled_data)
}


# ============================================================================
# FUNCTION: check_base_year_match
# ============================================================================
# Compute the correlation between scaled_data's base-year slice and base_rate,
# across cells valid in both. Returns list(n_valid, correlation) where
# correlation is NA when n_valid == 0.
# ============================================================================
check_base_year_match <- function(scaled_data, base_rate, base_idx) {
  if (is.na(base_idx) || base_idx < 1 || base_idx > dim(scaled_data)[3]) {
    return(list(n_valid = 0, correlation = NA_real_))
  }
  scaled_base <- scaled_data[, , base_idx]
  valid_cells <- !is.na(base_rate) & !is.na(scaled_base)
  n_valid <- sum(valid_cells)
  correlation <- if (n_valid > 0) {
    cor(
      as.vector(base_rate[valid_cells]),
      as.vector(scaled_base[valid_cells]),
      use = "complete.obs"
    )
  } else {
    NA_real_
  }
  list(n_valid = n_valid, correlation = correlation)
}

# ============================================================================
# FUNCTION: check_no_negatives
# ============================================================================
# Returns TRUE iff every value in `scaled_data` is either NA or >= 0. Used
# by test_scaling to flag physically-impossible negative fertilizer rates.
#
# Unlike the other check_* helpers, this returns a bare logical rather than
# a list: callers need only the pass/fail bit. Upgrade to a named list if
# future diagnostics need more detail (e.g., count or locations of
# negatives).
# ============================================================================
check_no_negatives <- function(scaled_data) {
  all(scaled_data >= 0 | is.na(scaled_data))
}

# ============================================================================
# FUNCTION: check_trends_preserved
# ============================================================================
# Sample up to n_samples cells (attempting up to max_attempts times) and
# compute the correlation between the original and scaled time series at
# each sampled cell. Returns list(n_sampled, median_correlation) where
# median_correlation is NA when no valid samples were collected.
#
# Preserves the current non-deterministic sample() behavior.
# ============================================================================
check_trends_preserved <- function(scaled_data, timeseries,
                                   n_samples = 100, max_attempts = 1000) {
  nlon <- dim(scaled_data)[1]
  nlat <- dim(scaled_data)[2]

  sampled <- 0
  trend_cors <- numeric()

  for (attempt in 1:max_attempts) {
    i <- sample(1:nlon, 1)
    j <- sample(1:nlat, 1)

    ts_orig <- timeseries[i, j, ]
    ts_scaled <- scaled_data[i, j, ]

    if (sum(!is.na(ts_orig)) > 10 && sum(!is.na(ts_scaled)) > 10) {
      valid <- !is.na(ts_orig) & !is.na(ts_scaled)
      if (sum(valid) > 10 && sd(ts_orig[valid]) > 0 && sd(ts_scaled[valid]) > 0) {
        cor_val <- cor(ts_orig[valid], ts_scaled[valid])
        trend_cors <- c(trend_cors, cor_val)
        sampled <- sampled + 1
      }
    }

    if (sampled >= n_samples) break
  }

  median_correlation <- if (length(trend_cors) > 0) {
    median(trend_cors, na.rm = TRUE)
  } else {
    NA_real_
  }
  list(n_sampled = sampled, median_correlation = median_correlation)
}

# ============================================================================
# FUNCTION: check_relative_changes_applied
# ============================================================================
# Sample up to max_attempts cells searching for one with a full valid time
# series (sum(!is.na(ts_orig)) == ntime, non-NA positive base_rate, non-NA
# positive base-year ts value). On success, computes expected vs. actual
# scaled values at a fixed set of time steps — same indices as the original
# inline code: c(1, ntime %/% 2, ntime). Returns list(found, checks) where
# checks is a list of list(t, expected, actual). The caller applies the
# tolerance (1e-5) via expect_equal.
#
# Preserves the current non-deterministic sample() behavior.
# ============================================================================
check_relative_changes_applied <- function(scaled_data, timeseries, base_rate,
                                           base_idx, max_attempts = 1000) {
  nlon <- dim(scaled_data)[1]
  nlat <- dim(scaled_data)[2]
  ntime <- dim(scaled_data)[3]

  if (is.na(base_idx) || base_idx < 1 || base_idx > ntime) {
    return(list(found = FALSE, checks = list()))
  }

  checks <- list()
  found <- FALSE

  timestep_indices <- c(1, ntime %/% 2, ntime)

  for (attempt in 1:max_attempts) {
    i <- sample(1:nlon, 1)
    j <- sample(1:nlat, 1)

    ts_orig <- timeseries[i, j, ]
    ts_scaled <- scaled_data[i, j, ]

    if (!is.na(base_rate[i, j]) && base_rate[i, j] > 0 &&
        !is.na(ts_orig[base_idx]) && ts_orig[base_idx] > 0 &&
        sum(!is.na(ts_orig)) == ntime) {

      for (t in timestep_indices) {
        rel_change <- ts_orig[t] / ts_orig[base_idx]
        expected <- base_rate[i, j] * rel_change
        checks[[length(checks) + 1]] <- list(
          t = t, expected = expected, actual = ts_scaled[t]
        )
      }

      found <- TRUE
      break
    }
  }

  list(found = found, checks = checks)
}

# ============================================================================
# FUNCTION: test_scaling
# ============================================================================
# Test that scaling preserves trends and produces valid results
#
# Args:
#   scaled_data: Scaled fertilizer data [lon, lat, time]
#   timeseries: Original time series [time, lat, lon]
#   base_rate: Original spatial pattern [lon, lat]
#   start_year: First year in time series
#   base_year: Reference year for scaling
#   method: Scaling method ("relative" or "lambda")
#
# Tests:
#   1. Base year values match original pattern (relative method only)
#   2. No negative values introduced
#   3. Trends are preserved from the time series
#   4. Relative changes are correctly applied (relative method only)
# ============================================================================
test_scaling <- function(scaled_data, timeseries, base_rate, start_year, base_year, method = "relative") {

  base_idx <- base_year - start_year + 1

  # Test 1: Base year match - only applies to relative method
  bym <- check_base_year_match(scaled_data, base_rate, base_idx)
  if (method == "relative") {
    test_that("Scaled data at base year matches original pattern (relative method)", {
      if (bym$n_valid > 0) {
        expect_true(bym$correlation > 0.99)
      }
    })
  } else {
    # For lambda method, just report correlation (informational only)
    cat(sprintf("\n=== Lambda Method Validation ===\n"))
    if (bym$n_valid > 0) {
      cat(sprintf("Base year spatial correlation: %.4f\n", bym$correlation))
      cat(sprintf("Note: Lambda method doesn't preserve exact base year values\n"))
    }
  }

  test_that("No negative values introduced by scaling", {
    expect_true(check_no_negatives(scaled_data))
  })

  trends <- check_trends_preserved(scaled_data, timeseries)
  test_that("Trends are preserved from time series", {
    if (trends$n_sampled > 0) {
      if (method == "relative") {
        expect_true(trends$median_correlation > 0.95)
      } else {
        cat(sprintf("Median trend correlation (lambda method): %.4f\n",
                    trends$median_correlation))
      }
    }
  })

  # Test relative changes only for relative method
  if (method == "relative") {
    rel <- check_relative_changes_applied(scaled_data, timeseries, base_rate, base_idx)
    test_that("Relative changes are correctly applied", {
      if (rel$found) {
        for (check in rel$checks) {
          expect_equal(check$actual, check$expected, tolerance = 1e-5)
        }
      } else {
        warning("Could not find suitable cell for relative change test")
      }
    })
  }  # End of method == "relative" conditional
}


# ============================================================================
# FUNCTION: plot_diagnostics
# ============================================================================
# Create diagnostic plots comparing original and scaled patterns
#
# Args:
#   base_rate: Original spatial pattern [lon, lat]
#   scaled_data: Scaled data [lon, lat, time]
#   lon: Longitude values
#   lat: Latitude values
#   start_year: First year in time series
#   end_year: Last year in time series
#   crop: Crop name
#   scenario: Scenario name
#   output_dir: Directory to save plots
#
# Creates:
#   1. Original pattern (year 2000)
#   2. First year pattern
#   3. Middle year pattern
#   4. Last year pattern
#   5. Time series for selected cells
# ============================================================================
plot_diagnostics <- function(base_rate, scaled_data, timeseries, lon, lat,
                            start_year, end_year, crop, scenario, output_dir, method = "relative",
                            spatial_data_5min = NULL, lon_5min = NULL, lat_5min = NULL,
                            iam = NULL, gcm = NULL,
                            base_timeseries_override = NULL) {
  
  # Define output PDF file and open device
  # Construct explicit, scenario/method-specific filename aligned with NetCDF naming
  if (tolower(scenario) == "histsoc") {
    plot_file <- paste0(output_dir, "/n-fertilizer_", crop,
                        "_histsoc_", method, "_annual_1850_2014_diagnostics.pdf")
  } else {
    if (!is.null(iam) && !is.null(gcm)) {
      plot_file <- paste0(output_dir, "/n-fertilizer_", crop, "_", iam, "_", gcm, "_",
                          scenario, "_", method, "_annual_2015_2100_diagnostics.pdf")
    } else {
      # Fallback if IAM/GCM are not provided
      plot_file <- paste0(output_dir, "/n-fertilizer_", crop, "_", scenario, "_",
                          method, "_annual_1850_2100_diagnostics.pdf")
    }
  }
  pdf(plot_file, width = 16, height = 14)

  ntime <- dim(scaled_data)[3]
  mid_idx <- ntime %/% 2
  base_idx <- base_year - start_year + 1
  scaled_base_override <- if (!is.na(base_idx) && base_idx >= 1 && base_idx <= ntime) {
    NULL
  } else {
    base_rate
  }

  # Set up layout for multiple plots (4 rows x 3 columns)
  par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))
  
  # Define sample locations early for overlay on maps
  sample_locations <- build_sample_locations()
  
  # AGGREGATION COMPARISON: Show 5-minute vs 0.5-degree if data provided
  if (!is.null(spatial_data_5min) && !is.null(lon_5min) && !is.null(lat_5min)) {
    plot_aggregation_comparison(base_rate, spatial_data_5min, lon, lat,
                                lon_5min, lat_5min, crop)
  }
  
  plot_pattern_maps(base_rate, scaled_data, lon, lat, sample_locations,
                    start_year, end_year, mid_idx, crop, method)

  plot_base_year_scatter(base_rate, scaled_data, base_idx, base_year, crop,
                         scaled_base_override = scaled_base_override)

  valid_rel_count <- plot_relative_change_hist(scaled_data, base_idx, base_year, end_year, crop,
                                               scaled_base_override = scaled_base_override)

  plot_spatial_ts_ratio(base_rate, timeseries, base_idx, lon, lat, sample_locations, crop,
                        base_timeseries_override = base_timeseries_override)

  plot_sample_timeseries(base_rate, scaled_data, timeseries, lon, lat,
                         start_year, end_year, sample_locations, crop)

  plot_distribution_histograms(base_rate, scaled_data, timeseries, base_idx,
                               base_year, end_year, crop,
                               base_timeseries_override = base_timeseries_override)

  plot_outlier_scatter(base_rate, scaled_data, timeseries, base_idx, base_year, end_year,
                       base_timeseries_override = base_timeseries_override)

  # Add explicit NA-provenance masks to diagnose where output NAs come from.
  ts_base_for_diag <- NULL
  if (!is.null(base_timeseries_override)) {
    ts_base_for_diag <- base_timeseries_override
  } else if (!is.na(base_idx) && base_idx >= 1 && base_idx <= ntime) {
    ts_base_for_diag <- timeseries[, , base_idx]
  }

  if (!is.null(ts_base_for_diag)) {
    plot_na_provenance_masks(
      base_rate = base_rate,
      scaled_t = scaled_data[, , 1],
      ts_base = ts_base_for_diag,
      ts_t = timeseries[, , 1],
      lon = lon,
      lat = lat,
      crop = crop,
      year_label = start_year
    )
  }

  dev.off()
  

}


# ============================================================================
# FUNCTION: main
# ============================================================================
# Main processing workflow: load spatial patterns, load timeseries, scale,
# write outputs, and generate diagnostics.
#
# Args:
#   crop: Crop name (e.g., "mai" for maize)
#   scenario: "histsoc" (historical) or SSP scenario (e.g., "ssp585")
#   iam: IAM model name for future scenarios (e.g., "IMAGE")
#   gcm: GCM name for future scenarios (e.g., "HadGEM2-ES")
#
# Details:
#   - For histsoc: processes 1850–2014
#   - For future: combines historical (1850–2014) with future (2015–2100)
#   - Applies each method in scaling_methods (production: lambda only)
#   - Outputs NetCDF and diagnostic plots
# ============================================================================
main <- function(crop, scenario, iam = NULL, gcm = NULL) {
  
  print(paste("Processing crop:", crop, "scenario:", scenario))
  if (!is.null(iam)) print(paste("IAM:", iam, "GCM:", gcm))
  
  # get input file name
  input_crop <- crop_to_inputfile[[crop]]
  input_file <- paste0(base_path_5min, "/", input_crop, "Napprate_gadm_subnational.nc")
  
  # check if file exists
  if (!file.exists(input_file)) {
    print(paste("Input file does not exist:", input_file))
    return()
  }
  
  # load spatial pattern
  print(paste("Loading spatial pattern from", input_file))
  nc_spatial <- nc_open(input_file)
  
  # get spatial data
  spatial_data <- ncvar_get(nc_spatial, varid = paste0(input_crop, "Napprate"))
  lon_5min <- ncvar_get(nc_spatial, varid = "longitude")
  lat_5min <- ncvar_get(nc_spatial, varid = "latitude")
  
  # get fill value from NetCDF metadata
  missval_spatial <- ncatt_get(nc_spatial, varid = paste0(input_crop, "Napprate"), attname = "_FillValue")
  if (missval_spatial$hasatt) {
    spatial_data[spatial_data == missval_spatial$value] <- NA
  }
  # also catch any extreme values that might be fill values
  spatial_data[abs(spatial_data) >= 1e+19] <- NA
  
  # handle 2D or 3D data (if only 1 time step, drop the time dimension)
  if (length(dim(spatial_data)) == 3) {
    spatial_data_2d <- spatial_data[, , 1]
  } else {
    spatial_data_2d <- spatial_data
  }
  
  # get attributes for output
  var_atts <- ncatt_get(nc_spatial, varid = paste0(input_crop, "Napprate"))
  
  nc_close(nc_spatial)
  
  # aggregate to 0.5 degree
  print("Aggregating to 0.5 degree resolution")
  agg_result <- aggregate_to_halfdegree(spatial_data_2d, lon_5min, lat_5min)
  base_rate <- agg_result$data
  lon_halfdeg <- agg_result$lon
  lat_halfdeg <- agg_result$lat
  
  # load time series - for future scenarios, combine with historical data
  base_timeseries <- NULL
  if (scenario == "histsoc") {
    ts_file <- paste0(base_path_timeseries, "/histsoc/n-fertilizer-5crops_histsoc_annual_1850_2014.nc")
    start_year_ts <- 1850
    end_year_ts <- 2014
    ts_data_list <- list()
  } else {
    # For future scenarios, we only need the historical base-year slice for
    # scaling, plus the future time series for the years we actually compute.
    ts_file_hist <- paste0(base_path_timeseries, "/histsoc/n-fertilizer-5crops_histsoc_annual_1850_2014.nc")
    ts_file_future <- paste0(base_path_timeseries, "/", scenario, "soc-adapt/n-fertilizer-5crops_",
                           iam, "_", gcm, "_", scenario, "_annual_2015_2100.nc")

    # Load the historical base-year slice only (year 2000), not the full
    # 1850-2014 series. This avoids computing/scaling historical years in
    # future scenario tasks.
    funcgroup <- crop_to_funcgroup[[crop]]
    print(paste("Loading historical base-year slice from", ts_file_hist))
    base_timeseries <- read_timeseries_year_slice(ts_file_hist, funcgroup, base_year, 1850)
  }
  
  # Load future or histsoc data
  if (scenario == "histsoc") {
    ts_file <- ts_file
  } else {
    ts_file <- ts_file_future
  }
  
  if (!file.exists(ts_file)) {
    print(paste("Time series file does not exist:", ts_file))
    return()
  }
  
  print(paste("Loading time series from", ts_file))
  nc_ts <- nc_open(ts_file)
  
  # List available variables for debugging
  var_names <- names(nc_ts$var)
  print(paste("Available variables in time series file:", paste(var_names, collapse = ", ")))
  
  # Check coordinate dimensions
  ts_lon <- NULL
  ts_lat <- NULL
  if ("lon" %in% names(nc_ts$dim)) {
    ts_lon <- ncvar_get(nc_ts, varid = "lon")
  }
  if ("lat" %in% names(nc_ts$dim)) {
    ts_lat <- ncvar_get(nc_ts, varid = "lat")
  }
  
  # get functional group for this crop
  funcgroup <- crop_to_funcgroup[[crop]]
  print(paste("Looking for variable:", funcgroup))
  
  # Check if variable exists, if not try alternative names
  # ISIMIP3b files use different naming: histsoc = fertl_<type>, future = <type>_fertl
  if (!(funcgroup %in% var_names)) {
    # Try swapping prefix/suffix format
    if (startsWith(funcgroup, "fertl_")) {
      # Try <type>_fertl format
      alt_name <- paste0(gsub("fertl_", "", funcgroup), "_fertl")
    } else {
      # Try fertl_<type> format
      alt_name <- paste0("fertl_", gsub("_fertl", "", funcgroup))
    }
    
    if (alt_name %in% var_names) {
      print(paste("Variable", funcgroup, "not found, using", alt_name, "instead"))
      funcgroup <- alt_name
    } else {
      print(paste("ERROR: Neither", funcgroup, "nor", alt_name, "found in file"))
      print(paste("Please check the file structure. Available variables are:", paste(var_names, collapse = ", ")))
      nc_close(nc_ts)
      return()
    }
  }
  
  # load time series data [lon, lat, time]
  ts_data <- ncvar_get(nc_ts, varid = funcgroup)
  print(paste("Future TS dims:", paste(dim(ts_data), collapse = "x")))
  # Canonicalize lat axis to ascending to match aggregate_to_halfdegree's
  # output convention. ISIMIP3b TS files store lat north->south.
  if (!is.null(ts_lat) && any(diff(ts_lat) < 0)) {
    ts_data <- ts_data[, dim(ts_data)[2]:1, ]
  }
  time_vals <- ncvar_get(nc_ts, varid = "time")
  
  # get fill value from NetCDF metadata
  missval_ts <- ncatt_get(nc_ts, varid = funcgroup, attname = "_FillValue")
  if (missval_ts$hasatt) {
    ts_data[ts_data == missval_ts$value] <- NA
  }
  # also catch any extreme values that might be fill values
  ts_data[abs(ts_data) >= 1e+19] <- NA
  
  nc_close(nc_ts)
  
  # Combine historical and future data if needed
  if (scenario != "histsoc") {
    print("Using future time series only for scaling; historical base-year slice was loaded separately")
    end_year_ts <- 2100
    start_year_ts <- 2015
  } else {
    start_year_ts <- 1850
    end_year_ts <- 2014
  }
  
  # Loop over configured scaling methods from settings.
  for (method in scaling_methods) {
    print(paste("\n=================================================="))
    print(paste("Processing with method:", method))
    print(paste("==================================================\n"))
    
    # scale the data
    print(paste("Scaling with time series using method:", method))
    scaled_data <- scale_with_timeseries(base_rate, ts_data, base_year, start_year_ts, end_year_ts,
                       method = method, base_timeseries = base_timeseries)
    
    # create output directory for diagnostics
    if (scenario == "histsoc") {
      output_dir <- paste0(output_base_path, "/", scenario, "/", method)
    } else {
      output_dir <- paste0(output_base_path, "/", scenario, "soc-adapt/", method)
    }
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

    # Run tests
    print("Running validation tests...")
    test_scaling(scaled_data, ts_data, base_rate, start_year_ts, base_year, method = method)
    
    # Create diagnostic plots BEFORE writing NetCDF (ncvar_put modifies the array in place!)
    print("Creating diagnostic plots...")
    plot_diagnostics(base_rate, scaled_data, ts_data, lon_halfdeg, lat_halfdeg,
            start_year_ts, end_year_ts, crop, scenario, output_dir, method = method,
            spatial_data_5min = spatial_data_2d, lon_5min = lon_5min, lat_5min = lat_5min,
          iam = iam, gcm = gcm,
          base_timeseries_override = base_timeseries)
    
    # Write output file(s)
    write_netcdf_file <- function(data_slice, yr_start, yr_end, out_file) {
      print(paste("Writing output to", out_file))
      
      # create output directory
      out_dir <- dirname(out_file)
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      
      # define dimensions
      dim_lon <- ncdim_def("lon", "degrees_east", lon_halfdeg)
      dim_lat <- ncdim_def("lat", "degrees_north", lat_halfdeg)
      dim_time <- ncdim_def("time", paste("years since", yr_start - 1, "-1-1 00:00:00"),
                           (yr_start:yr_end) - (yr_start - 1))

      # Chunk one full spatial field per timestep. With var dims ordered as
      # [lon, lat, time], this appears as [1, 360, 720] in ncdump output.
      chunk_sizes <- c(length(lon_halfdeg), length(lat_halfdeg), 1)
      
      # define variable
      ncv <- ncvar_def(name = paste0("fertl_", crop),
                      dim = list(dim_lon, dim_lat, dim_time),
                      missval = 1.e+20,
                      prec = "float",
                      units = "kg ha-1 yr-1",
                      longname = paste("N fertilizer application rate for", crop),
                      compression = 9,
                      chunksizes = chunk_sizes,
                      verbose = FALSE)
      
      # create file
      nc_out <- nc_create(out_file, list(ncv), verbose = FALSE)
      
      # write data
      ncvar_put(nc_out, varid = ncv, data_slice, start = c(1, 1, 1), count = c(-1, -1, -1))
      
      # add global attributes
      ncatt_put(nc_out, 0, "source", "Scaled from Mueller et al. fertilizer data and ISIMIP3b time series")
      ncatt_put(nc_out, 0, "contact", "info@pik-potsdam.de")
      ncatt_put(nc_out, 0, "institution", "Potsdam Institute for Climate Impact Research")
      ncatt_put(nc_out, 0, "base_year", base_year)
      ncatt_put(nc_out, 0, "scaling_method", method)
      ncatt_put(nc_out, 0, "creation_date", as.character(Sys.Date()))
      
      nc_close(nc_out)
    }
    
    # Write file(s) depending on scenario
    if (scenario == "histsoc") {
      # Just write histsoc file
      output_file <- paste0(output_base_path, "/", scenario, "/", method, "/n-fertilizer_", crop,
               "_", scenario, "_", method, "_annual_1850_2014.nc")
      write_netcdf_file(scaled_data, 1850, 2014, output_file)
    } else {
      # Write future file only. The dedicated histsoc task is the only place
      # that computes and writes the historical output.
      future_idx_start <- (2015 - start_year_ts) + 1
      future_idx_end <- dim(scaled_data)[3]
      scaled_future <- scaled_data[, , future_idx_start:future_idx_end]

      output_file_future <- paste0(output_base_path, "/", scenario, "soc-adapt/", method, 
                  "/n-fertilizer_", crop, "_", iam, "_", gcm, "_", scenario, 
                  "_", method, "_annual_2015_2100.nc")
      write_netcdf_file(scaled_future, 2015, 2100, output_file_future)
    }
    
  }  # End of method loop

  # Compare relative vs lambda outputs only when both methods were produced.
  if (all(c("relative", "lambda") %in% scaling_methods)) {
    comparison_dir <- if (scenario == "histsoc") {
      paste0(output_base_path, "/", scenario)
    } else {
      paste0(output_base_path, "/", scenario, "soc-adapt")
    }
    compare_relative_lambda(crop, scenario, iam, gcm, output_dir = comparison_dir)
  } else {
    print("Skipping compare_relative_lambda because both 'relative' and 'lambda' are not enabled")
  }

  print(paste("Completed processing for", crop, scenario))
}


# ============================================================================
# FUNCTION: compare_relative_lambda
# ============================================================================
# Create comparison plots between relative and lambda scaling methods
# Includes maps and scatter plots for multiple years
#
# Args:
#   crop: Crop name
#   scenario: Scenario name (histsoc or ssp)
#   iam: IAM model name (NULL for histsoc)
#   gcm: GCM name (NULL for histsoc)
#   output_dir: Directory to save comparison plots
# ============================================================================
compare_relative_lambda <- function(crop, scenario, iam = NULL, gcm = NULL, output_dir) {
  
  print(paste("====== DIAGNOSTIC: Starting compare_relative_lambda for", crop, scenario, "======"))
  
  # Determine output filenames
  if (scenario == "histsoc") {
    rel_file <- paste0(output_base_path, "/histsoc/relative/n-fertilizer_", crop,
               "_histsoc_relative_annual_1850_2014.nc")
    lambda_file <- paste0(output_base_path, "/histsoc/lambda/n-fertilizer_", crop,
                "_histsoc_lambda_annual_1850_2014.nc")
    start_year <- 1850
    end_year <- 2014
  } else {
    rel_file <- paste0(output_base_path, "/", scenario, "soc-adapt/relative/n-fertilizer_", crop,
               "_", iam, "_", gcm, "_", scenario, "_relative_annual_2015_2100.nc")
    lambda_file <- paste0(output_base_path, "/", scenario, "soc-adapt/lambda/n-fertilizer_", crop,
                "_", iam, "_", gcm, "_", scenario, "_lambda_annual_2015_2100.nc")
    start_year <- 2015
    end_year <- 2100
  }
  
  # Check files exist
  if (!file.exists(rel_file)) {
    print(paste("Relative file not found:", rel_file))
    return()
  }
  if (!file.exists(lambda_file)) {
    print(paste("Lambda file not found:", lambda_file))
    return()
  }
  
  # Load relative method data
  nc_rel <- nc_open(rel_file)
  rel_data <- ncvar_get(nc_rel, varid = paste0("fertl_", crop))
  lon <- ncvar_get(nc_rel, varid = "lon")
  lat <- ncvar_get(nc_rel, varid = "lat")
  nc_close(nc_rel)

  
  # Load lambda method data
  nc_lambda <- nc_open(lambda_file)
  lambda_data <- ncvar_get(nc_lambda, varid = paste0("fertl_", crop))
  nc_close(nc_lambda)

  
  # Ensure lon and lat are strictly increasing for image.plot
  # Handle any legacy files with different coordinate ordering
  if (any(diff(lon) <= 0)) {
    print("DIAGNOSTIC: lon coordinates not increasing, sorting...")
    lon_order <- order(lon)
    lon <- lon[lon_order]
    rel_data <- rel_data[lon_order, , ]
    lambda_data <- lambda_data[lon_order, , ]

  }
    
  # Create comparison PDF
  plot_file <- paste0(output_dir, "/comparison_relative_lambda_", crop, 
                      ifelse(scenario == "histsoc", "_histsoc.pdf",
                             paste0("_", scenario, "_", iam, "_", gcm, ".pdf")))
  
  tryCatch({
  pdf(plot_file, width = 16, height = 14)
  # Increase right margin to give legend labels more space
  par(mfrow = c(4, 3), mar = c(4, 4, 3, 8))
  
  # Helper function for mapping
  # Supports diverging color scales and symmetric log legend for differences
  plot_map_comp <- function(lon, lat, data, title, diverging = FALSE, log_scale = FALSE) {

    
    data_plot <- data

    
    valid_data <- data_plot[is.finite(data_plot) & abs(data_plot) < 1e+10]

    # Choose palette
    if (diverging) {
      col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0",
                                      "#f7f7f7",
                                      "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)
    } else {
      col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0",
                                      "#fefebe", "#fddbc7", "#ef8a62", "#b2182b"))(100)
    }
    # Legend axis args
    legend_axis_args <- list()
    # Data and zlim possibly transformed for log scale on diverging maps
    if (length(valid_data) > 0) {
      if (diverging) {
        max_abs_orig <- max(abs(valid_data), na.rm = TRUE)
        if (log_scale && max_abs_orig > 0) {
          symlog <- function(x) sign(x) * log10(1 + abs(x))
          data_col <- symlog(data_plot)
          zlim <- range(data_col[is.finite(data_col)], na.rm = TRUE)
          # Build symmetric tick labels in original units (increased n for more ticks)
          tick_orig <- pretty(c(-max_abs_orig, max_abs_orig), n = 10)
          # Ensure 0 present
          if (!any(abs(tick_orig) < .Machine$double.eps)) {
            tick_orig <- sort(unique(c(tick_orig, 0)))
          }
          tick_trans <- symlog(tick_orig)
          legend_axis_args <- list(at = tick_trans, labels = signif(tick_orig, 3))
          data_for_plot <- data_col
        } else {
          # Linear diverging scale centered at zero
          max_abs <- max(abs(valid_data), na.rm = TRUE)
          zlim <- c(-max_abs, max_abs)
          data_for_plot <- data_plot
        }
      } else {
        zlim <- range(valid_data, na.rm = TRUE)
        data_for_plot <- data_plot
      }
    } else {
      zlim <- c(0, 1)
      data_for_plot <- data_plot
    }

    
    # Handle edge case where zlim[1] == zlim[2] (no variation in data)
    # This can happen with difference maps when relative and lambda are identical
    if (zlim[1] == zlim[2]) {

      # Add a small epsilon to create valid zlim range
      zlim <- c(zlim[1] - 0.1, zlim[1] + 0.1)
    }
    

    
    # For legend customization with original (non-log) axis labels
    if (length(legend_axis_args) > 0) {
      # Create custom legend with axis function
      image.plot(lon, lat, data_for_plot, main = title, 
        xlab = "Longitude", ylab = "Latitude",
        col = col_ramp, zlim = zlim, ylim = c(-65, 90),
        legend.mar = 6, legend.cex = 0.9, legend.line = 1.5,
        axis.args = list(at = legend_axis_args$at, labels = legend_axis_args$labels))
    } else {
      image.plot(lon, lat, data_for_plot, main = title, 
        xlab = "Longitude", ylab = "Latitude",
        col = col_ramp, zlim = zlim, ylim = c(-65, 90),
        legend.mar = 6, legend.cex = 0.9, legend.line = 1.5)
    }

  }
  
  # Helper: 2D histogram heatmap using actual point counts
  plot_density_heatmap <- function(x, y, main_title, xlab = "Relative", ylab = "Lambda") {
    valid <- is.finite(x) & is.finite(y)
    x <- x[valid]; y <- y[valid]
    if (length(x) < 10) { plot.new(); text(0.5, 0.5, "Insufficient data for density plot"); return(invisible(NULL)) } # nocov
    xr <- range(x); yr <- range(y)
    if (diff(xr) == 0 || diff(yr) == 0) { plot.new(); text(0.5, 0.5, "No spread in data (single value)"); return(invisible(NULL)) }
    # Trim 1% tails for focused view
    xq <- quantile(x, c(0.01, 0.99), na.rm = TRUE); yq <- quantile(y, c(0.01, 0.99), na.rm = TRUE)
    xpad <- 0.02 * diff(xq); ypad <- 0.02 * diff(yq)
    xlim <- c(xq[1] - xpad, xq[2] + xpad)
    ylim <- c(yq[1] - ypad, yq[2] + ypad)
    # 2D histogram: bin data into 40x40 grid and count points per bin
    nbins <- 40
    xbreaks <- seq(xlim[1], xlim[2], length.out = nbins + 1)
    ybreaks <- seq(ylim[1], ylim[2], length.out = nbins + 1)
    # Map data to bin indices
    xi <- findInterval(x, xbreaks, all.inside = TRUE)
    yi <- findInterval(y, ybreaks, all.inside = TRUE)
    # Create count matrix
    z <- matrix(0, nrow = nbins, ncol = nbins)
    for (i in seq_along(x)) {
      z[xi[i], yi[i]] <- z[xi[i], yi[i]] + 1
    }
    z[z == 0] <- NA  # Mask empty bins to white
    # Bin centers for axes
    xc <- (xbreaks[-length(xbreaks)] + xbreaks[-1]) / 2
    yc <- (ybreaks[-length(ybreaks)] + ybreaks[-1]) / 2
    # Magma-like palette: light colors for low values, dark for high
    dens_palette <- colorRampPalette(c(
      "#fcfdbf", "#fef9c8", "#fcf0d0", "#fae4d6", "#f6d4db", "#eebcd7", "#e8a9ce",
      "#d991c5", "#c873b0", "#b35492", "#9d3072", "#7d1d4e", "#440154"
    ))
    if (all(is.na(z))) { plot.new(); text(0.5, 0.5, "No data in bins"); return(invisible(NULL)) } # nocov
    # Use zlim to set color range
    zlim_range <- range(z, na.rm = TRUE)
    image.plot(xc, yc, z,
               main = main_title, xlab = xlab, ylab = ylab,
               col = dens_palette(200),
               zlim = zlim_range,
               legend.mar = 6, legend.line = 2.5, legend.cex = 0.85,
               axis.args = list(cex.axis = 0.8))
    abline(0, 1, col = "red", lwd = 0.8, lty = 2)
  }

  
  # Helper function: binary mask panel (e.g., r<1)
  # r = ratio of value in year to reference year; r<1 indicates decrease
  plot_mask_panel <- function(lon, lat, mask_numeric, title) {
    # mask_numeric should be 0/1 with NA for invalid
    data_plot <- mask_numeric
    col_mask <- c("#eeeeee", "#b2182b")  # light grey for 0 (no decrease), red for 1 (decrease)
    # Ensure zlim spanning 0..1
    image.plot(lon, lat, data_plot,
               main = paste(title, "\n[r = year/reference; red = r<1]"),
               xlab = "Longitude", ylab = "Latitude",
               col = col_mask,
               zlim = c(0, 1),
               ylim = c(-65, 90),
               legend.mar = 4,
               axis.args = list(at = c(0, 1), labels = c("no", "yes")))
  }
  
  # Get base year index (2000 relative to start_year)
  base_idx <- base_year - start_year + 1
  first_idx <- 1
  last_idx <- dim(rel_data)[3]
  mid_idx <- last_idx %/% 2

  
  # ===== YEAR 2000 (if in range) =====
  if (base_idx >= 1 && base_idx <= last_idx) {
    print("DIAGNOSTIC: Plotting Year 2000 maps")
    plot_map_comp(lon, lat, rel_data[, , base_idx], 
            paste(crop, "- Year 2000 (Relative)"), diverging = FALSE)
    plot_map_comp(lon, lat, lambda_data[, , base_idx], 
            paste(crop, "- Year 2000 (Lambda)"), diverging = FALSE)
    diff_2000 <- lambda_data[, , base_idx] - rel_data[, , base_idx]
    plot_map_comp(lon, lat, diff_2000, 
            paste(crop, "- Year 2000 (Lambda - Relative)"), diverging = TRUE, log_scale = TRUE)

      # Ratio diagnostics (expect near equality in base year)
      rel_base <- rel_data[, , base_idx]
      lambda_base <- lambda_data[, , base_idx]
      valid_b <- is.finite(rel_base) & is.finite(lambda_base) & rel_base > 0
      n_equalish <- sum(abs(lambda_base[valid_b] - rel_base[valid_b]) < 1e-6)
      cat(sprintf("DIAGNOSTIC: Year 2000 equality count (|Δ|<1e-6): %d / %d\n", n_equalish, sum(valid_b)))
  }
  
  # ===== FIRST YEAR =====
  plot_map_comp(lon, lat, rel_data[, , first_idx], 
                paste(crop, "- Year", start_year, "(Relative)"), diverging = FALSE)
  plot_map_comp(lon, lat, lambda_data[, , first_idx], 
                paste(crop, "- Year", start_year, "(Lambda)"), diverging = FALSE)
  diff_first <- lambda_data[, , first_idx] - rel_data[, , first_idx]
  plot_map_comp(lon, lat, diff_first, 
                paste(crop, "- Year", start_year, "(Lambda - Relative)"), diverging = TRUE, log_scale = TRUE)

  # ===== DIAGNOSTICS: FIRST YEAR ratio vs inequality =====
  if (base_idx >= 1 && base_idx <= last_idx) {
    rel_base <- rel_data[, , base_idx]
    rel_y <- rel_data[, , first_idx]
    lambda_y <- lambda_data[, , first_idx]
    valid <- is.finite(rel_base) & is.finite(rel_y) & is.finite(lambda_y) & rel_base > 0
    r <- array(NA_real_, dim = dim(rel_base))
    r[valid] <- rel_y[valid] / rel_base[valid]
    mask_r_lt1 <- valid & r < 1
    mask_r_gt1 <- valid & r > 1
    mask_lambda_gt_rel <- valid & (lambda_y > rel_y)
    mask_lambda_lt_rel <- valid & (lambda_y < rel_y)
    n_valid <- sum(valid)
    cat(sprintf("DIAGNOSTIC: Year %d valid cells: %d\n", start_year, n_valid))
    cat(sprintf("  r<1: %d, r>1: %d\n", sum(mask_r_lt1), sum(mask_r_gt1)))
    cat(sprintf("  lambda>relative: %d, lambda<relative: %d\n", sum(mask_lambda_gt_rel), sum(mask_lambda_lt_rel)))
    overlap_gt <- sum(mask_r_lt1 & mask_lambda_gt_rel)
    overlap_lt <- sum(mask_r_gt1 & mask_lambda_lt_rel)
    cat(sprintf("  overlap (r<1 & lambda>rel): %d (%.1f%% of r<1)\n", overlap_gt,
                ifelse(sum(mask_r_lt1)>0, 100*overlap_gt/sum(mask_r_lt1), 0)))
    cat(sprintf("  overlap (r>1 & lambda<rel): %d (%.1f%% of r>1)\n", overlap_lt,
                ifelse(sum(mask_r_gt1)>0, 100*overlap_lt/sum(mask_r_gt1), 0)))
  }
  
  # ===== LAST YEAR =====
  plot_map_comp(lon, lat, rel_data[, , last_idx], 
                paste(crop, "- Year", end_year, "(Relative)"), diverging = FALSE)
  plot_map_comp(lon, lat, lambda_data[, , last_idx], 
                paste(crop, "- Year", end_year, "(Lambda)"), diverging = FALSE)
  diff_last <- lambda_data[, , last_idx] - rel_data[, , last_idx]
  plot_map_comp(lon, lat, diff_last, 
                paste(crop, "- Year", end_year, "(Lambda - Relative)"), diverging = TRUE, log_scale = TRUE)

  # ===== DIAGNOSTICS: LAST YEAR ratio vs inequality =====
  if (base_idx >= 1 && base_idx <= last_idx) {
    rel_base <- rel_data[, , base_idx]
    rel_y <- rel_data[, , last_idx]
    lambda_y <- lambda_data[, , last_idx]
    valid <- is.finite(rel_base) & is.finite(rel_y) & is.finite(lambda_y) & rel_base > 0
    r <- array(NA_real_, dim = dim(rel_base))
    r[valid] <- rel_y[valid] / rel_base[valid]
    mask_r_lt1 <- valid & r < 1
    mask_r_gt1 <- valid & r > 1
    mask_lambda_gt_rel <- valid & (lambda_y > rel_y)
    mask_lambda_lt_rel <- valid & (lambda_y < rel_y)
    n_valid <- sum(valid)
    cat(sprintf("DIAGNOSTIC: Year %d valid cells: %d\n", end_year, n_valid))
    cat(sprintf("  r<1: %d, r>1: %d\n", sum(mask_r_lt1), sum(mask_r_gt1)))
    cat(sprintf("  lambda>relative: %d, lambda<relative: %d\n", sum(mask_lambda_gt_rel), sum(mask_lambda_lt_rel)))
    overlap_gt <- sum(mask_r_lt1 & mask_lambda_gt_rel)
    overlap_lt <- sum(mask_r_gt1 & mask_lambda_lt_rel)
    cat(sprintf("  overlap (r<1 & lambda>rel): %d (%.1f%% of r<1)\n", overlap_gt,
                ifelse(sum(mask_r_lt1)>0, 100*overlap_gt/sum(mask_r_lt1), 0)))
    cat(sprintf("  overlap (r>1 & lambda<rel): %d (%.1f%% of r>1)\n", overlap_lt,
                ifelse(sum(mask_r_gt1)>0, 100*overlap_lt/sum(mask_r_gt1), 0)))
  }
  
  # ===== NEW PAGE: r<1 masks (decreases vs reference year) =====
  # Start a new page with 2x2 layout; show start and end year masks
  # For ssp data (base_year out of range), use first_year as reference
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 6))
  
  # Determine reference year: use base_year if in range, else first_year
  ref_idx <- if (base_idx >= 1 && base_idx <= last_idx) base_idx else first_idx
  ref_year <- if (base_idx >= 1 && base_idx <= last_idx) base_year else start_year
  
  rel_ref <- rel_data[, , ref_idx]
  
  # First year mask
  rel_first <- rel_data[, , first_idx]
  valid_first <- is.finite(rel_ref) & is.finite(rel_first) & rel_ref > 0
  r_first <- array(NA_real_, dim = dim(rel_ref))
  r_first[valid_first] <- rel_first[valid_first] / rel_ref[valid_first]
  mask_first <- array(NA_real_, dim = dim(rel_ref))
  mask_first[valid_first] <- 0
  mask_first[valid_first & r_first < 1] <- 1
  plot_mask_panel(lon, lat, mask_first, 
                  paste(crop, "- r<1 (Year", start_year, "vs", ref_year, ")"))

  # Last year mask
  rel_last <- rel_data[, , last_idx]
  valid_last <- is.finite(rel_ref) & is.finite(rel_last) & rel_ref > 0
  r_last <- array(NA_real_, dim = dim(rel_ref))
  r_last[valid_last] <- rel_last[valid_last] / rel_ref[valid_last]
  mask_last <- array(NA_real_, dim = dim(rel_ref))
  mask_last[valid_last] <- 0
  mask_last[valid_last & r_last < 1] <- 1
  plot_mask_panel(lon, lat, mask_last, 
                  paste(crop, "- r<1 (Year", end_year, "vs", ref_year, ")"))
  
  # ===== SCATTER/HEATMAP PLOTS =====
  # Reset layout to 4x3 for density plots
  par(mfrow = c(4, 3), mar = c(4, 4, 3, 8))
  
  # Calculate trends: (last - first) / nyears
  nyears <- end_year - start_year + 1
  trend_rel <- (rel_data[, , last_idx] - rel_data[, , first_idx]) / (nyears - 1)
  trend_lambda <- (lambda_data[, , last_idx] - lambda_data[, , first_idx]) / (nyears - 1)
  
  # Flatten for plots
  trend_rel_flat <- as.vector(trend_rel)
  trend_lambda_flat <- as.vector(trend_lambda)
  rel_first_flat <- as.vector(rel_data[, , first_idx])
  lambda_first_flat <- as.vector(lambda_data[, , first_idx])
  rel_last_flat <- as.vector(rel_data[, , last_idx])
  lambda_last_flat <- as.vector(lambda_data[, , last_idx])
  
  # Heatmap 1: Trends per pixel (2D density)
  valid_trend <- is.finite(trend_rel_flat) & is.finite(trend_lambda_flat) & 
                 !is.na(trend_rel_flat) & !is.na(trend_lambda_flat)
  if (sum(valid_trend) > 10) {
    x_trend <- trend_rel_flat[valid_trend]
    y_trend <- trend_lambda_flat[valid_trend]
    plot_density_heatmap(x_trend, y_trend,
                         main_title = paste("Density: Trend (", end_year, "-", start_year, ")/", nyears-1, "yr"))
  } else {
    plot.new(); text(0.5, 0.5, "Insufficient trend data")
  }
  
  # Heatmap 2: First year rates (2D density)
  valid_first <- is.finite(rel_first_flat) & is.finite(lambda_first_flat)
  if (sum(valid_first) > 10) {
    x_first <- rel_first_flat[valid_first]
    y_first <- lambda_first_flat[valid_first]
    plot_density_heatmap(x_first, y_first,
                         main_title = paste("Density: Rates Year", start_year))
  } else {
    plot.new(); text(0.5, 0.5, "Insufficient first year data")
  }
  
  # Heatmap 3: Last year rates (2D density)
  valid_last <- is.finite(rel_last_flat) & is.finite(lambda_last_flat)
  if (sum(valid_last) > 10) {
    x_last <- rel_last_flat[valid_last]
    y_last <- lambda_last_flat[valid_last]
    plot_density_heatmap(x_last, y_last,
                         main_title = paste("Density: Rates Year", end_year))
  } else {
    plot.new(); text(0.5, 0.5, "Insufficient last year data")
  }
  
  # Heatmap 4: Year 2000 or middle year (2D density)
  if (scenario == "histsoc") {
    if (base_idx >= 1 && base_idx <= last_idx) {
      rel_base_flat <- as.vector(rel_data[, , base_idx])
      lambda_base_flat <- as.vector(lambda_data[, , base_idx])
      valid_base <- is.finite(rel_base_flat) & is.finite(lambda_base_flat) & rel_base_flat > 0 & lambda_base_flat > 0
      if (sum(valid_base) > 10) {
        x_base <- rel_base_flat[valid_base]
        y_base <- lambda_base_flat[valid_base]
        plot_density_heatmap(x_base, y_base, main_title = "Density: Rates Year 2000")
      } else {
        plot.new(); text(0.5, 0.5, "Insufficient 2000 data")
      }
    }
  } else {
    # Middle year for future scenario
    if (mid_idx >= 1 && mid_idx <= last_idx) {
      mid_year <- start_year + mid_idx - 1
      rel_mid_flat <- as.vector(rel_data[, , mid_idx])
      lambda_mid_flat <- as.vector(lambda_data[, , mid_idx])
      valid_mid <- is.finite(rel_mid_flat) & is.finite(lambda_mid_flat) & rel_mid_flat > 0 & lambda_mid_flat > 0
      if (sum(valid_mid) > 10) {
        x_mid <- rel_mid_flat[valid_mid]
        y_mid <- lambda_mid_flat[valid_mid]
        plot_density_heatmap(x_mid, y_mid, main_title = paste("Density: Rates Year", mid_year))
      } else {
        plot.new(); text(0.5, 0.5, "Insufficient middle year data")
      }
    }
  }
  
  dev.off()
  print(paste("Comparison plot saved to", plot_file))
  }, error = function(e) {
    print("============ ERROR IN compare_relative_lambda ============")
    print(paste("Error message:", e$message))
    print("Stack trace:")
    print(traceback())
    print("============================================================")
    if (dev.cur() > 1) dev.off()  # Close PDF if open
  })
}
