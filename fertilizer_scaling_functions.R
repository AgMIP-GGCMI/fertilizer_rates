# ============================================================================
# Shared Function Definitions for fertilizer_scaling.R
# ============================================================================
# Sourced by fertilizer_scaling.R. Keep this file function-definitions-only so
# it is safe to source from tests or other scripts without side effects.
# ============================================================================

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
# TODO: lon_5min, lat_5min args are unused. Remove.
# TODO: Is this possibly the source of the upside-down maps?
aggregate_to_halfdegree <- function(data_5min, lon_5min, lat_5min) {
  # input: 4320 x 2160 (5 arcmin)
  # output: 720 x 360 (0.5 degree)
  # aggregation factor: 6 cells in each direction (6x6 = 36 cells per output cell)
  
  nlon_out <- 720
  nlat_out <- 360
  agg_factor <- 6
  
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
  
  # create output lon/lat
  lon_halfdeg <- seq(-179.75, 179.75, by = 0.5)
  lat_halfdeg <- seq(-89.75, 89.75, by = 0.5)
  
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
                                   start_year, end_year) {
  ntimes <- dim(timeseries)[3]
  base_idx <- base_year - start_year + 1
  if (base_idx < 1 || base_idx > ntimes) {
    stop(paste("Base year", base_year, "is outside the time series range",
               start_year, "-", end_year))
  }
  base_timeseries <- timeseries[, , base_idx]
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
  list(
    base_idx        = base_idx,
    base_timeseries = base_timeseries,
    valid_base      = valid_base
  )
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
  valid_ts_base <- valid_base & !is.na(base_timeseries) & is.finite(base_timeseries) & base_timeseries > 0
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
        if (valid_base[i, j] && !is.na(base_timeseries[i, j]) && base_timeseries[i, j] > 0) {
          fert_diff <- ts_t[i, j] - base_timeseries[i, j]
          ratio_base <- base_rate[i, j] / base_timeseries[i, j]
          ratio_term <- ratio_base ^ lambda[i, j]
          result[i, j] <- base_rate[i, j] * (1 + (fert_diff / base_rate[i, j]) * ratio_term)
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
# FUNCTION: scale_with_timeseries
# ============================================================================
# Scale fertilizer rates using relative change from time series
#
# Args:
#   base_rate: Spatial pattern at 0.5 degree for base year [lon, lat]
#   timeseries: Temporal data from ISIMIP3b [lon, lat, time]
#   base_year: Year to use as reference for relative scaling (default: 2000)
#   start_year: First year in time series
#   end_year: Last year in time series
#   method: Scaling method - "relative" (default) or "lambda"
#
# Returns:
#   Scaled data [lon, lat, time]
#
# Method options:
#   "relative": scaled[t] = base_rate * (timeseries[t] / timeseries[base_year])
#   "lambda": Precipitation-style scaling with anomalies and lambda correction
#              scaled[t] = base_rate * [1 + (TS_anom[t] / TS_mean) * (base_mean / TS_mean)^lambda]
#              where lambda = sqrt(TS_mean / base_mean) if TS_mean < base_mean, else 1
# ============================================================================
scale_with_timeseries <- function(base_rate, timeseries, base_year = 2000,
                                   start_year, end_year, method = "relative") {
  # base_rate: spatial pattern at 0.5 degree [lon, lat]
  # timeseries: temporal data [lon, lat, time]
  # returns: scaled data [lon, lat, time]
  
  print(paste("Using scaling method:", method))
  
  # get dimensions
  nlon <- dim(timeseries)[1]
  nlat <- dim(timeseries)[2]
  ntimes <- dim(timeseries)[3]

  # validate + precompute common pieces
  prep <- prepare_scaling_inputs(base_rate, timeseries, base_year,
                                 start_year, end_year)
  base_idx        <- prep$base_idx
  base_timeseries <- prep$base_timeseries
  valid_base      <- prep$valid_base

  # create output array [lon, lat, time]
  scaled_data <- array(NA, dim = c(nlon, nlat, ntimes))
  
  if (method == "relative") {
    for (t in 1:ntimes) {
      scaled_data[, , t] <- scale_relative_timestep(
        base_rate, timeseries[, , t], base_timeseries, valid_base
      )
    }

  } else if (method == "lambda") {
    # ===== LAMBDA METHOD (Precipitation-style) =====
    # Adapted for fertilizer: scaled[t] = F_ref * [1 + (fert_diff / F_ref_base) * (F_ref_base / F_ts_base)^lambda]
    # where:
    #   F_ref = base_rate (spatial baseline at year 2000)
    #   F_ref_base = base_rate (same, at base year 2000)
    #   F_ts_base = timeseries at base year 2000
    #   fert_diff = timeseries[t] - timeseries[base_year] (fertilizer difference relative to base year)
    #   lambda = sqrt(F_ts_base / F_ref_base) if F_ts_base < F_ref_base, else 1
    #   (lower lambda when TS is lower than spatial baseline to dampen amplification)
    
    lambda <- compute_lambda(base_rate, base_timeseries, valid_base)

    for (t in 1:ntimes) {
      tryCatch({
        scaled_data[, , t] <- scale_lambda_timestep(
          base_rate, timeseries[, , t], base_timeseries, valid_base, lambda
        )
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
    
  } else {
    stop(paste("Unknown scaling method:", method))
  }
  
  # Check for extreme values and diagnose issues
  max_val <- max(scaled_data, na.rm = TRUE)
  if (max_val > 1000) {
    print(paste("WARNING: Maximum scaled value is", round(max_val, 1), "kg/ha"))
    
    # Find cells with extreme values
    extreme_threshold <- 1000
    extreme_cells <- which(apply(scaled_data, c(1, 2), function(x) any(x > extreme_threshold, na.rm = TRUE)), arr.ind = TRUE)
    
    if (nrow(extreme_cells) > 0) {
      print(paste("Found", nrow(extreme_cells), "cells with values >", extreme_threshold, "kg/ha"))
      
      # Report details for first few extreme cases
      n_report <- min(5, nrow(extreme_cells))
      for (i in 1:n_report) {
        idx_lon <- extreme_cells[i, 1]
        idx_lat <- extreme_cells[i, 2]
        
        ts_cell <- scaled_data[idx_lon, idx_lat, ]
        max_year_idx <- which.max(ts_cell)
        max_year <- start_year + max_year_idx - 1
        
        print(paste("\nCell", i, "at lon index", idx_lon, ", lat index", idx_lat))
        print(paste("  Base rate (year 2000 spatial):", round(base_rate[idx_lon, idx_lat], 2), "kg/ha"))
        print(paste("  TS at base year (2000):", round(base_timeseries[idx_lon, idx_lat], 2), "kg/ha"))
        print(paste("  TS at year", max_year, ":", round(timeseries[idx_lon, idx_lat, max_year_idx], 2), "kg/ha"))
        print(paste("  Relative change:", round(timeseries[idx_lon, idx_lat, max_year_idx] / base_timeseries[idx_lon, idx_lat], 2)))
        print(paste("  Scaled value at year", max_year, ":", round(ts_cell[max_year_idx], 2), "kg/ha"))
        
        # Check for mismatches
        ratio_base_to_ts <- base_rate[idx_lon, idx_lat] / base_timeseries[idx_lon, idx_lat]
        if (abs(ratio_base_to_ts - 1) > 0.5) {
          print(paste("  MISMATCH: Spatial base / TS base ratio =", round(ratio_base_to_ts, 2)))
        }
      }
    }
  }
  
  return(scaled_data)
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
#   1. Trends are preserved (correlation between scaled and original trends)
#   2. Base year values match original pattern (only for "relative" method)
#   3. No negative values introduced
#   4. Relative changes are correctly applied
# ============================================================================
test_scaling <- function(scaled_data, timeseries, base_rate, start_year, base_year, method = "relative") {
  
  base_idx <- base_year - start_year + 1
  
  # Test 1: Base year match - only applies to relative method
  if (method == "relative") {
    test_that("Scaled data at base year matches original pattern (relative method)", {
      # Extract base year from scaled data [lon, lat]
      scaled_base <- scaled_data[, , base_idx]
      
      # Compare (accounting for NA positions)
      valid_cells <- !is.na(base_rate) & !is.na(scaled_base)
      if (sum(valid_cells) > 0) {
        # Should be very close (allowing for numerical precision)
        expect_true(cor(as.vector(base_rate[valid_cells]), 
                       as.vector(scaled_base[valid_cells]), 
                       use = "complete.obs") > 0.99)
      }
    })
  } else {
    # For lambda method, just report correlation (informational only)
    cat(sprintf("\n=== Lambda Method Validation ===\n"))
    scaled_base <- scaled_data[, , base_idx]
    valid_cells <- !is.na(base_rate) & !is.na(scaled_base)
    if (sum(valid_cells) > 0) {
      # Pattern should still be correlated, just not identical
      cor_val <- cor(as.vector(base_rate[valid_cells]), 
                    as.vector(scaled_base[valid_cells]), 
                    use = "complete.obs")
      cat(sprintf("Base year spatial correlation: %.4f\n", cor_val))
      cat(sprintf("Note: Lambda method doesn't preserve exact base year values\n"))
    }
  }
  
  test_that("No negative values introduced by scaling", {
    # Negative fertilizer rates are physically impossible
    expect_true(all(scaled_data >= 0 | is.na(scaled_data)))
  })
  
  test_that("Trends are preserved from time series", {
    # Sample some grid cells and check if trends match
    nlon <- dim(scaled_data)[1]
    nlat <- dim(scaled_data)[2]
    ntime <- dim(scaled_data)[3]
    
    # Sample 100 random cells with data
    sampled <- 0
    trend_cors <- numeric()
    
    for (attempt in 1:1000) {
      i <- sample(1:nlon, 1)
      j <- sample(1:nlat, 1)
      
      # Check if both have valid time series
      # timeseries is [lon, lat, time]
      ts_orig <- timeseries[i, j, ]
      ts_scaled <- scaled_data[i, j, ]
      
      if (sum(!is.na(ts_orig)) > 10 && sum(!is.na(ts_scaled)) > 10) {
        # Calculate correlation of trends
        valid <- !is.na(ts_orig) & !is.na(ts_scaled)
        if (sum(valid) > 10 && sd(ts_orig[valid]) > 0 && sd(ts_scaled[valid]) > 0) {
          cor_val <- cor(ts_orig[valid], ts_scaled[valid])
          trend_cors <- c(trend_cors, cor_val)
          sampled <- sampled + 1
        }
      }
      
      if (sampled >= 100) break
    }
    
    if (length(trend_cors) > 0) {
      # Trends should be highly correlated (relative scaling preserves shape)
      median_cor <- median(trend_cors, na.rm = TRUE)
      if (method == "relative") {
        expect_true(median_cor > 0.95)
      } else {
        # For lambda method, just report (trends may differ)
        cat(sprintf("Median trend correlation (lambda method): %.4f\n", median_cor))
      }
    }
  })
  
  # Test relative changes only for relative method
  if (method == "relative") {
    test_that("Relative changes are correctly applied", {
    # Pick a cell with valid data throughout
    nlon <- dim(scaled_data)[1]
    nlat <- dim(scaled_data)[2]
    ntime <- dim(scaled_data)[3]
    
    found <- FALSE
    for (attempt in 1:1000) {
      i <- sample(1:nlon, 1)
      j <- sample(1:nlat, 1)
      
      # timeseries is [lon, lat, time]
      ts_orig <- timeseries[i, j, ]
      ts_scaled <- scaled_data[i, j, ]
      
      if (!is.na(base_rate[i, j]) && base_rate[i, j] > 0 &&
          !is.na(ts_orig[base_idx]) && ts_orig[base_idx] > 0 &&
          sum(!is.na(ts_orig)) == ntime) {
        
        # Calculate expected scaling for a few time steps
        for (t in c(1, ntime %/% 2, ntime)) {
          rel_change <- ts_orig[t] / ts_orig[base_idx]
          expected <- base_rate[i, j] * rel_change
          
          # Should match within numerical precision
          expect_equal(ts_scaled[t], expected, tolerance = 1e-5)
        }
        
        found <- TRUE
        break
      }
    }
    
    # Report if we couldn't find suitable test cell
    if (!found) {
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
                            iam = NULL, gcm = NULL) {
  
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
  valid_rel_count <- 0
  

  # Set up layout for multiple plots (4 rows x 3 columns)
  par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))
  
  # Define sample locations early for overlay on maps
  sample_locations <- data.frame(
    lat = c(8.0, 9.5, 26.0, -30.0, 40.0, 42.0, 30.0, 34.0, -15.0, -23.0),
    lon = c(-2.0, 37.0, 87.0, -60.0, -5.0, -93.5, 75.0, 114.0, -48.0, -47.0),
    description = c(
      "W Africa (Ghana)", "E Africa (Ethiopia)", "E India (Bihar)", 
      "S Brazil (RS)", "N Spain", "US Iowa", "NW India (Punjab)", 
      "N China (Henan)", "C Brazil (Mato Grosso)", "SE Brazil (SP)"
    ),
    stringsAsFactors = FALSE
  )
  
  # Find nearest valid cells for markers (will be used in time series plot)
  sample_cells_for_ts <- list()
  
  # Helper function to add sample location markers to maps
  add_sample_markers <- function() {
    for (k in 1:nrow(sample_locations)) {
      target_lon <- sample_locations$lon[k]
      target_lat <- sample_locations$lat[k]
      
      # Find nearest grid cell
      i <- which.min(abs(lon - target_lon))
      j <- which.min(abs(lat - target_lat))
      marker_lon <- lon[i]
      marker_lat <- lat[j]
      
      # Add circle marker
      points(marker_lon, marker_lat, pch = 21, col = "black", bg = NA, 
             cex = 1.5, lwd = 0.8)
      # Add number label
      text(marker_lon, marker_lat, k, cex = 0.5, col = "black", font = 2)
    }
  }
  
  # Helper function for plotting maps
  plot_map <- function(lon, lat, data, title, diverging = FALSE, add_markers = TRUE) {
    # Flip lat for plotting (north up)
    data_plot <- data[, c(length(lat):1)]
    
    # Calculate data range excluding NA and extreme values
    valid_data <- data_plot[is.finite(data_plot) & abs(data_plot) < 1e+10]
    if (length(valid_data) > 0) {
      zlim <- range(valid_data, na.rm = TRUE)
      
      # For diverging maps (e.g., difference maps), center at zero
      if (diverging) {
        max_abs <- max(abs(zlim), na.rm = TRUE)
        zlim <- c(-max_abs, max_abs)
      }
    } else {
      zlim <- c(0, 1)
    }
    
    # Choose color scheme
    if (diverging) {
      # Diverging: blue (negative) -> white (zero) -> red (positive)
      col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0", 
                                      "#f7f7f7", 
                                      "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)
    } else {
      # Sequential: blue (low) -> cyan -> yellow -> red (high)
      col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0", "#fefebe", 
                                      "#fddbc7", "#ef8a62", "#b2182b"))(100)
    }
    
    image.plot(lon, lat, data_plot,
               main = title,
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp,
               zlim = zlim,
               ylim = c(-65, 90))
    
    # Add sample location markers if requested
    if (add_markers) {
      add_sample_markers()
    }
  }
  
  # AGGREGATION COMPARISON: Show 5-minute vs 0.5-degree if data provided
  if (!is.null(spatial_data_5min) && !is.null(lon_5min) && !is.null(lat_5min)) {
    # Create a separate page for aggregation comparison
    par(mfrow = c(2, 2), mar = c(4, 4, 3, 6))
    
    # Plot 1: Original 5-arcmin data (full resolution)
    valid_5min <- spatial_data_5min[is.finite(spatial_data_5min) & abs(spatial_data_5min) < 1e+10]
    if (length(valid_5min) > 0) {
      zlim_5min <- quantile(valid_5min, c(0.02, 0.98), na.rm = TRUE)
    } else {
      zlim_5min <- c(0, 1)
    }
    
    col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0", "#fefebe",
                                    "#fddbc7", "#ef8a62", "#b2182b"))(100)
    
    # With lat_5min sorted increasing, no flip is needed
    # Flip latitude for plotting without reordering coordinates
    lat_5min_plot <- rev(lat_5min)
    data_5min_plot <- spatial_data_5min[, ncol(spatial_data_5min):1]
    image.plot(lon_5min, lat_5min_plot, data_5min_plot,
               main = paste(crop, "- Original 5-arcmin Data (full resolution)"),
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp,
               zlim = zlim_5min,
               ylim = c(-65, 90))
    
    # Plot 2: Aggregated 0.5-degree data (base_rate)
    data_halfdeg_plot <- base_rate[, c(length(lat):1)]
    valid_halfdeg <- data_halfdeg_plot[is.finite(data_halfdeg_plot) & abs(data_halfdeg_plot) < 1e+10]
    if (length(valid_halfdeg) > 0) {
      zlim_halfdeg <- quantile(valid_halfdeg, c(0.02, 0.98), na.rm = TRUE)
    } else {
      zlim_halfdeg <- c(0, 1)
    }
    
    image.plot(lon, lat, data_halfdeg_plot,
               main = paste(crop, "- Aggregated 0.5-degree Data"),
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp,
               zlim = zlim_halfdeg,
               ylim = c(-65, 90))
    
    # Plot 3: Spatial statistics - 5-minute data
    if (length(valid_5min) > 0) {
      hist(valid_5min, breaks = 50, main = "5-arcmin Data Distribution",
           xlab = "N Rate (kg/ha)", col = "steelblue", border = "steelblue")
      legend("topright",
             legend = c(paste("N =", format(length(valid_5min), big.mark = ",")),
                        paste("mean =", sprintf("%.2f", mean(valid_5min, na.rm = TRUE))),
                        paste("median =", sprintf("%.2f", median(valid_5min, na.rm = TRUE))),
                        paste("max =", sprintf("%.2f", max(valid_5min, na.rm = TRUE)))),
             bty = "n", cex = 0.85)
    } else {
      plot.new(); text(0.5, 0.5, "No valid 5-arcmin data")
    }
    
    # Plot 4: Spatial statistics - 0.5-degree data
    if (length(valid_halfdeg) > 0) {
      hist(valid_halfdeg, breaks = 50, main = "0.5-degree Aggregated Data Distribution",
           xlab = "N Rate (kg/ha)", col = "coral", border = "coral")
      legend("topright",
             legend = c(paste("N =", format(length(valid_halfdeg), big.mark = ",")),
                        paste("mean =", sprintf("%.2f", mean(valid_halfdeg, na.rm = TRUE))),
                        paste("median =", sprintf("%.2f", median(valid_halfdeg, na.rm = TRUE))),
                        paste("max =", sprintf("%.2f", max(valid_halfdeg, na.rm = TRUE)))),
             bty = "n", cex = 0.85)
    } else {
      plot.new(); text(0.5, 0.5, "No valid 0.5-degree data")
    }
    
    # Reset layout for remaining diagnostic plots
    par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))
  }
  
  plot_map(lon, lat, base_rate,
          paste(crop, "- Original Pattern (Year 2000) [Method:", method, "]"))
  
  # Plot 2: First year
  plot_map(lon, lat, scaled_data[, , 1],
          paste(crop, "- Scaled Pattern (Year", start_year, ")"))
  
  # Plot 3: Middle year
  mid_year <- start_year + mid_idx - 1
  plot_map(lon, lat, scaled_data[, , mid_idx],
          paste(crop, "- Scaled Pattern (Year", mid_year, ")"))
  
  # Plot 4: Last year
  plot_map(lon, lat, scaled_data[, , ntime],
          paste(crop, "- Scaled Pattern (Year", end_year, ")"))
  
  # Plot 5: Difference (last - first year)
  first_year_data <- scaled_data[, , 1]
  last_year_data <- scaled_data[, , ntime]
  diff_map <- last_year_data - first_year_data
  
  plot_map(lon, lat, diff_map,
           paste(crop, "- Change (", end_year, "-", start_year, ")"),
           diverging = TRUE)

  # Plot 6: Base year scatter (scaled vs original)
  if (base_idx >= 1 && base_idx <= ntime) {
    scaled_base <- scaled_data[, , base_idx]
    valid <- is.finite(base_rate) & is.finite(scaled_base)
    if (any(valid)) {
      x <- base_rate[valid]
      y <- scaled_base[valid]
      plot(x, y, pch = 16, cex = 0.4,
           xlab = "Original (Year 2000)", ylab = "Scaled (Year 2000)",
           main = paste(crop, "- Scatter Year", base_year))
      abline(0, 1, col = "red", lwd = 2)
      # summary stats
      if (length(x) > 1 && sd(x) > 0 && sd(y) > 0) {
        cor_val <- cor(x, y)
      } else {
        cor_val <- NA_real_
      }
      rmse <- sqrt(mean((y - x)^2))
      bias <- mean(y - x)
      legend("topleft",
             legend = c(paste("N =", length(x)),
                        sprintf("cor = %.3f", cor_val),
                        sprintf("RMSE = %.2f", rmse),
                        sprintf("Bias = %.2f", bias)),
             bty = "n")
    } else {
      plot.new(); text(0.5, 0.5, "No valid data for base-year scatter")
    }
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }

  # Plot 7: Relative change distribution (last / base year)
  if (base_idx >= 1 && base_idx <= ntime) {
    scaled_base <- scaled_data[, , base_idx]
    scaled_last <- scaled_data[, , ntime]
    valid_rel <- is.finite(scaled_base) & is.finite(scaled_last) & scaled_base > 0
    if (any(valid_rel)) {
      rel_change <- scaled_last[valid_rel] / scaled_base[valid_rel]
      valid_rel_count <- length(rel_change)
      hist(rel_change, breaks = 40, main = paste(crop, "- Rel. Change", end_year, "vs", base_year),
           xlab = "Relative change (last/base)", col = "grey")
      stats <- quantile(rel_change, probs = c(0.05, 0.5, 0.95))
      abline(v = 1, col = "red", lwd = 2, lty = 2)
      legend("topright",
             legend = c(sprintf("N = %d", length(rel_change)),
                        sprintf("mean = %.2f", mean(rel_change)),
                        sprintf("p05/50/95 = %.2f / %.2f / %.2f", stats[1], stats[2], stats[3])),
             bty = "n")
    } else {
      plot.new(); text(0.5, 0.5, "No valid relative changes")
    }
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }

  # Plot 8: Extreme values diagnostic - Ratio of spatial base to TS base
  if (base_idx >= 1 && base_idx <= ntime) {
    ts_base <- timeseries[, , base_idx]
    
    # Calculate ratio where both are positive
    valid_ratio <- is.finite(base_rate) & is.finite(ts_base) & base_rate > 0.1 & ts_base > 0.1
    
    if (any(valid_ratio)) {
      ratio_map <- array(NA, dim = dim(base_rate))
      ratio_map[valid_ratio] <- base_rate[valid_ratio] / ts_base[valid_ratio]
      
      # Cap extreme ratios for visualization
      ratio_capped <- ratio_map
      ratio_capped[ratio_capped > 5] <- 5
      ratio_capped[ratio_capped < 0.2] <- 0.2
      
      # Plot map with diverging colors centered at 1
      data_plot <- ratio_capped[, c(length(lat):1)]
      valid_data <- data_plot[is.finite(data_plot)]
      
      if (length(valid_data) > 0) {
        # Center around 1, symmetric limits
        zlim <- c(0.2, 5)
        
        # Diverging color scheme for ratios
        col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0", 
                                        "#f7f7f7", 
                                        "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)
        
        image.plot(lon, lat, data_plot,
                   main = paste(crop, "- Spatial/TS Ratio (Year 2000)"),
                   xlab = "Longitude", ylab = "Latitude",
                   col = col_ramp,
                   zlim = zlim,
                   ylim = c(-65, 90))
        
        # Report statistics
        n_mismatch <- sum(abs(ratio_map - 1) > 0.5, na.rm = TRUE)
        n_total <- sum(valid_ratio)
        pct_mismatch <- 100 * n_mismatch / n_total
        print(paste("Base/TS mismatch: ", n_mismatch, " cells (", 
                    round(pct_mismatch, 1), "%) differ by >50%", sep = ""))
      } else {
        plot.new(); text(0.5, 0.5, "No valid ratio data")
      }
    } else {
      plot.new(); text(0.5, 0.5, "No valid ratio data")
    }
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }

  # Plot 9: Time series for predefined sample locations
  # Use 10 globally distributed pixels representing different fertilizer trends
  # (sample_locations already defined at top of function)
  
  
  # ===== SAMPLE LOCATION TIME SERIES EXTRACTION =====
  # 
  # IMPORTANT: Coordinate System Mismatch Between Datasets
  # 
  # This script works with two different coordinate systems:
  # 
  # 1. Aggregated data (base_rate, scaled_data):
  #    - Created by aggregating from 5 arcmin to 0.5 degree resolution
  #    - Latitude ordering: South -> North (-89.75 to 89.75)
  #    - Index j increases as latitude increases
  #
  # 2. Time series data (timeseries array):
  #    - From ISIMIP3b original files
  #    - Latitude ordering: North -> South (89.75 to -89.75) 
  #    - Index j decreases as latitude increases
  #
  # VISUAL MAPPING:
  #    plot_map() function displays data with: data[, length(lat):1]
  #    This flips the lat dimension for display, so map position j_display = length(lat) - j_original
  #    The add_sample_markers() function correctly uses geographic coordinates (lon, lat)
  #    which display at the correct position on the map.
  #
  # TIME SERIES EXTRACTION:
  #    To extract time series data at a location that shows correctly on the map:
  #    j_ts = length(lat) - j + 1
  #    Then access: timeseries[i, j_ts, t] to get correct data
  #    Similarly: scaled_data[i, j_ts, t] (also uses timeseries indexing internally)
  #
  # EXAMPLE:
  #    If a location matches to j=199 in the South->North (aggregated) system,
  #    and length(lat)=360:
  #      j_ts = 360 - 199 + 1 = 162
  #      This correctly maps to the same geographic location in the North->South (ISIMIP) system
  #
  # Find nearest grid cells to these locations
  # Since all pixels have valid data, use simple nearest-neighbor matching
  sample_cells <- list()
  nlon <- length(lon)
  nlat <- length(lat)
  
  for (k in 1:nrow(sample_locations)) {
    target_lat <- sample_locations$lat[k]
    target_lon <- sample_locations$lon[k]
    
    # Find nearest grid indices
    i <- which.min(abs(lon - target_lon))
    j <- which.min(abs(lat - target_lat))
    
    # Get actual matched coordinates
    actual_lon <- lon[i]
    actual_lat <- lat[j]
    
    # CRITICAL COORDINATE SYSTEM HANDLING:
    # - base_rate and scaled_data use lat from aggregation (South->North: -89.75 to 89.75)
    # - timeseries uses original ISIMIP lat ordering (North->South: 89.75 to -89.75)
    # - plot_map() flips lat for display: data[, length(lat):1]
    # - To extract time series at correct map location, flip j index: j_ts = length(lat) - j + 1
    j_ts <- length(lat) - j + 1
    
    # Store all data - use j_ts (flipped) for timeseries AND scaled_data extraction
    sample_cells[[k]] <- list(
      i = i, j = j,
      j_ts = j_ts,
      actual_lon = actual_lon,
      actual_lat = actual_lat,
      description = sample_locations$description[k],
      base_rate_val = base_rate[i, j],
      ts_scaled = scaled_data[i, j_ts, ],  # Use flipped j (computed with timeseries indexing)
      ts_original = timeseries[i, j_ts, ]  # Use flipped j
    )
  }
  
  # Plot time series
  years <- start_year:end_year
  
  if (length(sample_cells) > 0) {
    # Build combined y-range including original ts
    all_values <- c()
    for (x in sample_cells) {
      ts_scaled <- x$ts_scaled[is.finite(x$ts_scaled)]
      ts_orig <- x$ts_original[is.finite(x$ts_original)]
      all_values <- c(all_values, ts_scaled, ts_orig)
    }
    
    if (length(all_values) > 0) {
      y_range <- range(all_values, na.rm = TRUE)
    } else {
      y_range <- c(0, 1)
    }
    
    # Check if y_range is valid (finite values)
    if (all(is.finite(y_range))) {
      plot(years, scaled_data[1, 1, ], type = "n",
           ylim = y_range,
           main = paste(crop, "- Time Series at Sample Locations"),
           xlab = "Year", ylab = "N Fertilizer Rate (kg/ha)")
      
      colors <- rainbow(length(sample_cells))
      for (k in seq_along(sample_cells)) {
        cell <- sample_cells[[k]]
        # scaled (solid line)
        lines(years, cell$ts_scaled, col = colors[k], lwd = 1)
        # original (dashed line)
        lines(years, cell$ts_original, col = colors[k], lwd = 0.8, lty = 2)
      }
      # Create legend labels with description and actual coordinates
      legend_labels <- sapply(seq_along(sample_cells), function(k) {
        cell <- sample_cells[[k]]
        sprintf("%s (%.1f°, %.1f°)", cell$description, cell$actual_lat, cell$actual_lon)
      })
      legend("topleft", legend = legend_labels,
             col = colors, lwd = 2, lty = 1, cex = 0.65, bg = "white")
    } else {
      # No valid data for time series plot
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "No valid time series data available", axes = FALSE)
      text(1, 1, "No cells with sufficient data found", cex = 1.2)
    }
  } else {
    # No cells found
    plot(1, 1, type = "n", xlab = "", ylab = "", main = "No sample locations found", axes = FALSE)
    text(1, 1, "No cells with fertilizer application > 0.1 kg/ha", cex = 1.2)
  }
  
  # Plot 10: Histogram - Spatial base vs Scaled last
  base_vals <- base_rate[is.finite(base_rate) & base_rate > 0]
  scaled_last_vals <- scaled_data[, , ntime][is.finite(scaled_data[, , ntime]) & scaled_data[, , ntime] > 0]
  
  if (length(base_vals) > 0 && length(scaled_last_vals) > 0) {
    x_range <- range(c(base_vals, scaled_last_vals), na.rm = TRUE)
    breaks_seq <- seq(x_range[1], x_range[2], length.out = 30)
    
    hist(base_vals, breaks = breaks_seq, col = rgb(0, 0, 1, 0.5), 
         main = paste("Spatial Base vs Scaled"),
         xlab = "N Rate (kg/ha)", ylab = "Frequency",
         xlim = x_range)
    hist(scaled_last_vals, breaks = breaks_seq, col = rgb(1, 0, 0, 0.5), add = TRUE)
    
    legend("topright", 
           legend = c(paste("Base", base_year), paste("Scaled", end_year)),
           fill = c(rgb(0, 0, 1, 0.5), rgb(1, 0, 0, 0.5)),
           cex = 0.8, bty = "n")
  } else {
    plot.new(); text(0.5, 0.5, "No data")
  }
  
  # Plot 11: Histogram - Original time series base vs last
  ts_base_vals <- timeseries[, , base_idx][is.finite(timeseries[, , base_idx]) & timeseries[, , base_idx] > 0]
  ts_last_vals <- timeseries[, , ntime][is.finite(timeseries[, , ntime]) & timeseries[, , ntime] > 0]
  
  if (length(ts_base_vals) > 0 && length(ts_last_vals) > 0) {
    x_range <- range(c(ts_base_vals, ts_last_vals), na.rm = TRUE)
    breaks_seq <- seq(x_range[1], x_range[2], length.out = 30)
    
    hist(ts_base_vals, breaks = breaks_seq, col = rgb(0, 0.6, 0, 0.5), 
         main = paste("Original TS"),
         xlab = "N Rate (kg/ha)", ylab = "Frequency",
         xlim = x_range)
    hist(ts_last_vals, breaks = breaks_seq, col = rgb(1, 0.5, 0, 0.5), add = TRUE)
    
    legend("topright", 
           legend = c(paste("TS", base_year), paste("TS", end_year)),
           fill = c(rgb(0, 0.6, 0, 0.5), rgb(1, 0.5, 0, 0.5)),
           cex = 0.8, bty = "n")
  } else {
    plot.new(); text(0.5, 0.5, "No data")
  }
  
  # Plot 12: Histogram - Changes (deltas)
  change_scaled <- (scaled_data[, , ntime] - base_rate)[is.finite(scaled_data[, , ntime] - base_rate)]
  change_ts <- (timeseries[, , ntime] - timeseries[, , base_idx])[is.finite(timeseries[, , ntime] - timeseries[, , base_idx])]
  
  if (length(change_scaled) > 0 && length(change_ts) > 0) {
    x_range <- range(c(change_scaled, change_ts), na.rm = TRUE)
    breaks_seq <- seq(x_range[1], x_range[2], length.out = 30)
    
    hist(change_scaled, breaks = breaks_seq, col = rgb(0.5, 0, 0.5, 0.5), 
         main = paste("Changes:", end_year, "-", base_year),
         xlab = "Change in N Rate (kg/ha)", ylab = "Frequency",
         xlim = x_range)
    hist(change_ts, breaks = breaks_seq, col = rgb(0.7, 0.7, 0, 0.5), add = TRUE)
    abline(v = 0, col = "black", lwd = 2, lty = 2)
    
    legend("topright", 
           legend = c("Scaled change", "TS change"),
           fill = c(rgb(0.5, 0, 0.5, 0.5), rgb(0.7, 0.7, 0, 0.5)),
           cex = 0.8, bty = "n")
  } else {
    plot.new(); text(0.5, 0.5, "No data")
  }
  
  # ---- Page 2 for additional diagnostics ----
  
  # Plot 13: Scatter - Scaling factor vs Final value with log scale (ALL data)
  # Extract scaling factors and final values
  scaling_factors <- (timeseries[, , ntime] / timeseries[, , base_idx])
  final_values <- scaled_data[, , ntime]
  
  # Flatten and create valid mask
  sf_flat <- as.vector(scaling_factors)
  fv_flat <- as.vector(final_values)
  valid_mask <- is.finite(sf_flat) & is.finite(fv_flat) & 
                sf_flat > 0 & sf_flat < Inf & fv_flat > 0  # Need >0 for log scale
  
  sf_valid <- sf_flat[valid_mask]
  fv_valid <- fv_flat[valid_mask]
  
  if (length(sf_valid) > 100) {
    # Define outlier threshold
    outlier_threshold <- 1000  # kg/ha
    is_outlier <- fv_valid > outlier_threshold
    
    # Set up colors (blue for normal, red for outliers)
    point_colors <- ifelse(is_outlier, rgb(1, 0, 0, 0.7), rgb(0, 0, 1, 0.2))
    
    # Plot with log scale on y-axis to show full range
    plot(sf_valid, fv_valid, 
         pch = 16, cex = 0.4, col = point_colors,
         log = "y",
         main = paste("Scaling Factor vs Final Value - Log Scale (", end_year, ")", sep = ""),
         xlab = paste("Scaling Factor (", end_year, "/", base_year, ")", sep = ""),
         ylab = paste("Final Scaled Value (kg/ha, ", end_year, ") [LOG SCALE]", sep = ""))
    
    # Add reference lines
    abline(v = 1, col = "gray50", lwd = 2, lty = 2)  # No change line
    abline(h = outlier_threshold, col = "red", lwd = 2, lty = 2)  # Outlier threshold
    
    # Calculate statistics
    n_outliers <- sum(is_outlier)
    pct_outliers <- 100 * n_outliers / length(fv_valid)
    median_sf_normal <- median(sf_valid[!is_outlier], na.rm = TRUE)
    median_sf_outlier <- if(n_outliers > 0) median(sf_valid[is_outlier], na.rm = TRUE) else NA
    
    # Add legend with statistics
    legend("bottomright", 
           legend = c(
             paste("Normal (n=", format(sum(!is_outlier), big.mark = ","), ")", sep = ""),
             paste("Outliers >", outlier_threshold, " (n=", format(n_outliers, big.mark = ","), ")", sep = ""),
             paste("Med SF normal:", sprintf("%.2f", median_sf_normal)),
             if(!is.na(median_sf_outlier)) paste("Med SF outliers:", sprintf("%.2f", median_sf_outlier)) else NULL
           ),
           col = c(rgb(0, 0, 1, 0.6), rgb(1, 0, 0, 0.7), NA, NA),
           pch = c(16, 16, NA, NA),
           cex = 0.7, bty = "n")
    
    # Print summary to console
    cat("\n=== Scaling Factor vs Outlier Analysis ===\n")
    cat(sprintf("Total cells: %s\n", format(length(fv_valid), big.mark = ",")))
    cat(sprintf("Outliers (>%d kg/ha): %s (%.1f%%)\n", 
                outlier_threshold, format(n_outliers, big.mark = ","), pct_outliers))
    cat(sprintf("Median scaling factor (normal): %.2f\n", median_sf_normal))
    if (n_outliers > 0) {
      cat(sprintf("Median scaling factor (outliers): %.2f\n", median_sf_outlier))
      cat(sprintf("Range of outlier values: %.0f - %.0f kg/ha\n",
                  min(fv_valid[is_outlier], na.rm = TRUE),
                  max(fv_valid[is_outlier], na.rm = TRUE)))
      cat(sprintf("Range of outlier scaling factors: %.2f - %.2f\n",
                  min(sf_valid[is_outlier], na.rm = TRUE),
                  max(sf_valid[is_outlier], na.rm = TRUE)))
    }
    
  } else {
    plot.new()
    text(0.5, 0.5, "Insufficient data for scatter plot")
  }
  
  # Plot 14: Scatter - OUTLIERS ONLY (detailed view)
  if (length(sf_valid) > 100 && sum(is_outlier) > 0) {
    sf_outliers <- sf_valid[is_outlier]
    fv_outliers <- fv_valid[is_outlier]
    
    # Also get base rates for outlier cells
    base_flat <- as.vector(base_rate)
    base_valid <- base_flat[valid_mask]
    base_outliers <- base_valid[is_outlier]
    
    # Color by base rate intensity (helps identify if high base rates contribute)
    base_quartiles <- quantile(base_outliers, probs = c(0.25, 0.5, 0.75), na.rm = TRUE)
    outlier_colors <- ifelse(base_outliers < base_quartiles[1], rgb(1, 0.8, 0, 0.6),  # Low base - orange
                       ifelse(base_outliers < base_quartiles[2], rgb(1, 0.5, 0, 0.6),  # Med-low - red-orange
                       ifelse(base_outliers < base_quartiles[3], rgb(1, 0.2, 0, 0.6),  # Med-high - red
                              rgb(0.8, 0, 0, 0.6))))  # High base - dark red
    
    plot(sf_outliers, fv_outliers, 
         pch = 16, cex = 0.8, col = outlier_colors,
         main = paste("OUTLIERS ONLY: Scaling Factor vs Final Value (", end_year, ")", sep = ""),
         xlab = paste("Scaling Factor (", end_year, "/", base_year, ")", sep = ""),
         ylab = paste("Final Scaled Value (kg/ha, ", end_year, ")", sep = ""))
    
    abline(v = 1, col = "gray50", lwd = 2, lty = 2)
    
    # Statistics
    cor_outliers <- cor(sf_outliers, fv_outliers, use = "complete.obs")
    
    legend("topright", 
           legend = c(
             paste("n =", format(length(sf_outliers), big.mark = ",")),
             paste("Correlation:", sprintf("%.3f", cor_outliers)),
             "",
             "Base rate (2000) quartiles:",
             paste("Q1:", sprintf("%.0f", base_quartiles[1])),
             paste("Q2:", sprintf("%.0f", base_quartiles[2])),
             paste("Q3:", sprintf("%.0f", base_quartiles[3]))
           ),
           col = c(NA, NA, NA, NA, 
                   rgb(1, 0.8, 0, 0.6), rgb(1, 0.5, 0, 0.6), 
                   rgb(1, 0.2, 0, 0.6)),
           pch = c(NA, NA, NA, NA, 16, 16, 16),
           cex = 0.7, bty = "n")
    
    cat(sprintf("\n=== Outlier Detail Analysis ===\n"))
    cat(sprintf("Correlation (SF vs final value) for outliers: %.3f\n", cor_outliers))
    cat(sprintf("Base rate range for outliers: %.0f - %.0f kg/ha\n",
                min(base_outliers, na.rm = TRUE),
                max(base_outliers, na.rm = TRUE)))
    
  } else if (length(sf_valid) > 100) {
    plot.new()
    text(0.5, 0.5, "No outliers to display")
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
#   - Applies both relative and lambda scaling methods
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
  # convert very small values (likely numerical artifacts in ocean) to NA
  spatial_data[abs(spatial_data) < 1e-6 & !is.na(spatial_data)] <- NA
  
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
  if (scenario == "histsoc") {
    ts_file <- paste0(base_path_timeseries, "/histsoc/n-fertilizer-5crops_histsoc_annual_1850_2014.nc")
    start_year_ts <- 1850
    end_year_ts <- 2014
    ts_data_list <- list()
  } else {
    # For future scenarios, load both historical and future data
    ts_file_hist <- paste0(base_path_timeseries, "/histsoc/n-fertilizer-5crops_histsoc_annual_1850_2014.nc")
    ts_file_future <- paste0(base_path_timeseries, "/", scenario, "soc-adapt/n-fertilizer-5crops_",
                           iam, "_", gcm, "_", scenario, "_annual_2015_2100.nc")
    ts_data_list <- list()
    
    # Load historical
    if (!file.exists(ts_file_hist)) {
      print(paste("Historical time series file not found:", ts_file_hist))
      return()
    }
    
    print(paste("Loading historical time series from", ts_file_hist))
    nc_hist <- nc_open(ts_file_hist)
    funcgroup <- crop_to_funcgroup[[crop]]
    
    if (!(funcgroup %in% names(nc_hist$var))) {
      print(paste("Variable", funcgroup, "not found in historical file"))
      nc_close(nc_hist)
      return()
    }
    
    ts_hist <- ncvar_get(nc_hist, varid = funcgroup)
    print(paste("Historical TS dims:", paste(dim(ts_hist), collapse = "x")))
    missval_hist <- ncatt_get(nc_hist, varid = funcgroup, attname = "_FillValue")
    if (missval_hist$hasatt) {
      ts_hist[ts_hist == missval_hist$value] <- NA
    }
    ts_hist[abs(ts_hist) >= 1e+19] <- NA
    
    nc_close(nc_hist)
    
    ts_data_list$hist <- list(data = ts_hist, start = 1850, end = 2014)
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
    print("Combining historical and future time series")
    ts_hist_data <- ts_hist  # Data is [lon, lat, time]
    # Both are [lon, lat, time], bind along time dimension (dimension 3)
    print(paste("Historical dims:", paste(dim(ts_hist_data), collapse = "x")))
    print(paste("Future dims:", paste(dim(ts_data), collapse = "x")))
    ts_data_combined <- abind::abind(ts_hist_data, ts_data, along = 3)
    print(paste("Combined dims:", paste(dim(ts_data_combined), collapse = "x")))
    start_year_ts <- 1850
    end_year_ts <- 2100
    ts_data <- ts_data_combined
  } else {
    start_year_ts <- 1850
    end_year_ts <- 2014
  }
  
  # Loop over both scaling methods for comparison
  scaling_methods <- c("relative", "lambda")
  
  for (method in scaling_methods) {
    print(paste("\n=================================================="))
    print(paste("Processing with method:", method))
    print(paste("==================================================\n"))
    
    # scale the data
    print(paste("Scaling with time series using method:", method))
    scaled_data <- scale_with_timeseries(base_rate, ts_data, base_year, start_year_ts, end_year_ts, method = method)
    
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
            iam = iam, gcm = gcm)
    
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
      
      # define variable
      ncv <- ncvar_def(name = paste0("fertl_", crop),
                      dim = list(dim_lon, dim_lat, dim_time),
                      missval = 1.e+20,
                      prec = "float",
                      units = "kg ha-1 yr-1",
                      longname = paste("N fertilizer application rate for", crop),
                      compression = 9,
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
      # Write both histsoc (1850-2014) and future (2015-2100) files
      # Extract time slices
      hist_idx_start <- 1
      hist_idx_end <- 2014 - 1850 + 1  # 165 years (1850-2014)
      future_idx_start <- hist_idx_end + 1
      future_idx_end <- 165 + 86  # 2100 - 2015 + 1 = 86 years
      
      scaled_hist <- scaled_data[, , hist_idx_start:hist_idx_end]
      scaled_future <- scaled_data[, , future_idx_start:future_idx_end]
      
      # Write histsoc file
      output_file_hist <- paste0(output_base_path, "/histsoc/", method, "/n-fertilizer_", crop,
                "_histsoc_", method, "_annual_1850_2014.nc")
      write_netcdf_file(scaled_hist, 1850, 2014, output_file_hist)
      
      # Write future file
      output_file_future <- paste0(output_base_path, "/", scenario, "soc-adapt/", method, 
                  "/n-fertilizer_", crop, "_", iam, "_", gcm, "_", scenario, 
                  "_", method, "_annual_2015_2100.nc")
      write_netcdf_file(scaled_future, 2015, 2100, output_file_future)
    }
    
  }  # End of method loop
  
  print(paste("Completed processing for", crop, scenario))
}


# ============================================================================
# FUNCTION: compare_2014_2015
# ============================================================================
# Create scatter plot comparing 2014 (end of histsoc) vs 2015 (start of future)
#
# Args:
#   crop: Crop name
#   iam: IAM model name
#   gcm: GCM name
#   ssp: SSP scenario
#   output_dir: Directory to save plot
# ============================================================================
compare_2014_2015 <- function(crop, iam, gcm, ssp, output_dir) {
  
  print(paste("Creating 2014/2015 comparison for", crop, iam, gcm, ssp))
  
  # Load 2014 data (last year of histsoc)
  histsoc_file <- paste0(output_base_path, "/histsoc/n-fertilizer_", crop,
                         "_histsoc_annual_1850_2014.nc")
  
  # Load 2015 data (first year of future scenario)
  future_file <- paste0(output_base_path, "/", ssp, "soc-adapt/n-fertilizer_", crop,
                       "_", iam, "_", gcm, "_", ssp, "_annual_2015_2100.nc")
  
  if (!file.exists(histsoc_file)) {
    print(paste("Histsoc file not found:", histsoc_file))
    return()
  }
  
  if (!file.exists(future_file)) {
    print(paste("Future file not found:", future_file))
    return()
  }
  
  # Load 2014 data (last time slice)
  nc_hist <- nc_open(histsoc_file)
  var_name <- paste0("fertl_", crop)
  data_hist <- ncvar_get(nc_hist, varid = var_name)
  ntime_hist <- dim(data_hist)[3]
  data_2014 <- data_hist[, , ntime_hist]  # last year = 2014
  nc_close(nc_hist)
  
  # Load 2015 data (first time slice)
  nc_fut <- nc_open(future_file)
  data_fut <- ncvar_get(nc_fut, varid = var_name)
  data_2015 <- data_fut[, , 1]  # first year = 2015
  nc_close(nc_fut)
  
  # Create comparison plot
  plot_file <- paste0(output_dir, "/comparison_2014_2015_", crop, "_", 
                     iam, "_", gcm, "_", ssp, ".pdf")
  pdf(plot_file, width = 8, height = 8)
  
  # Extract valid data
  valid <- is.finite(data_2014) & is.finite(data_2015) & data_2014 > 0 & data_2015 > 0
  
  if (sum(valid) > 0) {
    x <- data_2014[valid]
    y <- data_2015[valid]
    
    plot(x, y, pch = 16, cex = 0.4, col = rgb(0, 0, 0, 0.3),
         xlab = "2014 (histsoc)", ylab = "2015 (future)",
         main = paste(crop, "-", iam, gcm, ssp, "\n2014 vs 2015"),
         asp = 1)
    abline(0, 1, col = "red", lwd = 2)
    
    # Calculate statistics
    if (length(x) > 1 && sd(x) > 0 && sd(y) > 0) {
      cor_val <- cor(x, y)
    } else {
      cor_val <- NA_real_
    }
    rmse <- sqrt(mean((y - x)^2))
    bias <- mean(y - x)
    rel_bias <- bias / mean(x) * 100
    
    legend("topleft",
           legend = c(paste("N =", length(x)),
                      sprintf("cor = %.3f", cor_val),
                      sprintf("RMSE = %.2f kg/ha", rmse),
                      sprintf("Bias = %.2f kg/ha", bias),
                      sprintf("Rel. Bias = %.1f%%", rel_bias)),
           bty = "n")
  } else {
    plot.new()
    text(0.5, 0.5, "No valid data for comparison")
  }
  
  dev.off()
  print(paste("Comparison plot saved to", plot_file))
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

    
    # Flip data along lat dimension for north-up display
    data_plot <- data[, c(length(lat):1)]

    
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
    if (length(x) < 10) { plot.new(); text(0.5, 0.5, "Insufficient data for density plot"); return(invisible(NULL)) }
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
    if (all(is.na(z))) { plot.new(); text(0.5, 0.5, "No data in bins"); return(invisible(NULL)) }
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
    data_plot <- mask_numeric[, c(length(lat):1)]
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
