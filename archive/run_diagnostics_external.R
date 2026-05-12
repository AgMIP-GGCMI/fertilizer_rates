# ============================================================================
# Run Diagnostics on ISIMIP Data
# ============================================================================
# 
# Purpose:
#   Run the plot_diagnostics function from fertilizer_scaling.R on ISIMIP
#   data files to compare results with the scaling performed in the main script.
#
# This script loads:
#   - ssp585 data: n-fertilizer-15crops_image_gfdl-esm4_ssp585_annual_2015_2100_gridcell_fixed_prevalidation.nc
#   - histsoc data: n-fertilizer-15crops_histsoc_annual_1850_2014_gridcell_fixed_prevalidation.nc
#
# Crops analyzed: mai (maize), wwh (winter wheat)
#
# Author: Generated for comparison analysis
# Date: 2026-01-20
# ============================================================================

# Load libraries
library(ncdf4)
library(fields)

# Paths and crop mapping for 5-arcmin spatial data (year 2000 baseline)
base_path_5min <- "/p/projects/ikiimp/5min_input/toolbox_paper_application/fertilizer_paper/tmp/work_5min"
crop_to_inputfile <- list(
  swh = "wheat",
  wwh = "wheat",
  mai = "maize"
)

# ============================================================================
# FUNCTION: plot_diagnostics (extracted from fertilizer_scaling.R)
# ============================================================================
plot_diagnostics <- function(base_rate, scaled_data, timeseries, lon, lat,
                            start_year, end_year, crop, scenario, output_dir, method = "relative",
                            spatial_data_5min = NULL, lon_5min = NULL, lat_5min = NULL,
                            iam = NULL, gcm = NULL, base_rate_5min_agg = NULL) {
  
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
  base_year <- 2000
  base_idx <- base_year - start_year + 1
  if (base_idx < 1 || base_idx > ntime) {
    cat(sprintf("[diag] base_idx out of range (start_year=%d, base_year=%d, ntime=%d); using base_idx=1 (year %d)\n",
                start_year, base_year, ntime, start_year))
    base_idx <- 1
    base_year <- start_year
  }
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
  add_sample_markers <- function(lat_plot) {
    for (k in 1:nrow(sample_locations)) {
      target_lon <- sample_locations$lon[k]
      target_lat <- sample_locations$lat[k]
      
      # Find nearest grid cell
      i <- which.min(abs(lon - target_lon))
      j <- which.min(abs(lat - target_lat))
      j_ts <- length(lat) - j + 1
      marker_lon <- lon[i]
      marker_lat <- lat_plot[j_ts]
      
      # Add circle marker
      points(marker_lon, marker_lat, pch = 21, col = "black", bg = NA, 
             cex = 1.5, lwd = 0.8)
      # Add number label
      text(marker_lon, marker_lat, k, cex = 0.5, col = "black", font = 2)
    }
  }
  
  # Helper function for plotting maps
  plot_map <- function(lon, lat, data, title, diverging = FALSE, add_markers = TRUE) {
    # Diagnostics for grid monotonicity (image() requires increasing coords)
    if (is.unsorted(lon)) {
      cat("[diag] lon is not strictly increasing for", title, "\n")
    }
    if (is.unsorted(lat)) {
      cat("[diag] lat is not strictly increasing for", title, "\n")
    }
    cat("[diag] lon range:", range(lon), "lat range:", range(lat), "\n")
    # Extra diagnostics: show head/tail and diff signs
    cat("[diag] lon head/tail:", paste(head(lon, 3), collapse=","), ";",
      paste(tail(lon, 3), collapse=","), "\n")
    cat("[diag] lat head/tail:", paste(head(lat, 3), collapse=","), ";",
      paste(tail(lat, 3), collapse=","), "\n")
    cat("[diag] lat diff >0 count:", sum(diff(lat) > 0),
      "lat diff <0 count:", sum(diff(lat) < 0),
      "lat diff ==0 count:", sum(diff(lat) == 0), "\n")
    
    # Ensure increasing latitude for image.plot: flip data and provide flipped lat vector
    lat_plot <- rev(lat)
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
    
    image.plot(lon, lat_plot, data_plot,
               main = title,
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp,
               zlim = zlim,
               ylim = c(-65, 90))
    
    # Add sample location markers if requested
    if (add_markers) {
      add_sample_markers(lat_plot)
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
    
    # Plot 2: Aggregated 0.5-degree data (base_rate) - compute zlim first
    data_halfdeg_plot <- base_rate[, c(length(lat):1)]
    lat_halfdeg_plot <- rev(lat)
    valid_halfdeg <- data_halfdeg_plot[is.finite(data_halfdeg_plot) & abs(data_halfdeg_plot) < 1e+10]
    if (length(valid_halfdeg) > 0) {
      zlim_halfdeg <- quantile(valid_halfdeg, c(0.02, 0.98), na.rm = TRUE)
    } else {
      zlim_halfdeg <- c(0, 1)
    }
    
    # Use 5-arcmin zlim for both maps for consistency with fertilizer_scaling.R
    # ISIMIP values >zlim_5min[2] will be clipped/saturated for direct visual comparison
    zlim_common <- zlim_5min
    
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
               zlim = zlim_common,
               ylim = c(-65, 90))
    
    # Now plot 0.5-degree aggregated using same zlim
    image.plot(lon, lat_halfdeg_plot, data_halfdeg_plot,
               main = paste(crop, "- Aggregated 0.5-degree Data"),
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp,
               zlim = zlim_common,
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
    
    # Plot 4: Spatial statistics - 0.5-degree data (capped at 350 for comparability)
    if (length(valid_halfdeg) > 0) {
      # Cap values at 350 to match 5-arcmin scale; count values >350
      valid_halfdeg_capped <- pmin(valid_halfdeg, 350)
      n_over_350 <- sum(valid_halfdeg > 350)
      
      hist(valid_halfdeg_capped, breaks = 50, main = "0.5-degree Aggregated Data Distribution",
           xlab = "N Rate (kg/ha, capped at 350)", col = "coral", border = "coral",
           xlim = c(0, 350))
      legend("topright",
             legend = c(paste("N =", format(length(valid_halfdeg), big.mark = ",")),
                        paste("mean (uncapped) =", sprintf("%.2f", mean(valid_halfdeg, na.rm = TRUE))),
                        paste("median (uncapped) =", sprintf("%.2f", median(valid_halfdeg, na.rm = TRUE))),
                        paste("values >350: ", format(n_over_350, big.mark = ","))),
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
  # For histsoc with 5-min aggregated data available, compare against that; otherwise use base_rate
  if (base_idx >= 1 && base_idx <= ntime) {
    scaled_base <- scaled_data[, , base_idx]
    
    # Choose reference data: 5-min aggregated if available (for histsoc comparison), else base_rate
    ref_data <- if (!is.null(base_rate_5min_agg)) base_rate_5min_agg else base_rate
    xlabel_text <- if (!is.null(base_rate_5min_agg)) "5-min Aggregated (Year 2000)" else "Original (Year 2000)"
    
    valid <- is.finite(ref_data) & is.finite(scaled_base)
    if (any(valid)) {
      x <- ref_data[valid]
      y <- scaled_base[valid]
      plot(x, y, pch = 16, cex = 0.4,
           xlab = xlabel_text, ylab = "ISIMIP (Year 2000)",
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
        
        lat_ratio_plot <- rev(lat)
        image.plot(lon, lat_ratio_plot, data_plot,
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
    
    # Keep original coordinate handling: flip j for timeseries/plotting alignment
    j_ts <- length(lat) - j + 1
    
    # Store all data: use j for extraction (ISIMIP data in North->South order)
    # j_ts is only needed for marker placement in flipped display
    sample_cells[[k]] <- list(
      i = i, j = j,
      j_ts = j_ts,
      actual_lon = actual_lon,
      actual_lat = actual_lat,
      description = sample_locations$description[k],
      base_rate_val = base_rate[i, j],
      ts_scaled = scaled_data[i, j, ],
      ts_original = timeseries[i, j, ]
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
  
  dev.off()
  cat(paste("\nDiagnostic plots saved to:", plot_file, "\n"))
}

# ============================================================================
# MAIN: Process external data files
# ============================================================================

# Helper: aggregate 5-arcmin data to 0.5-degree
aggregate_to_halfdegree <- function(data_5min, lon_5min, lat_5min) {
  # input: 4320 x 2160 (5 arcmin)
  # output: 720 x 360 (0.5 degree)
  # aggregation factor: 6 cells in each direction (6x6 = 36 cells per output cell)
  nlon_out <- 720
  nlat_out <- 360
  agg_factor <- 6
  data_halfdeg <- array(NA, dim = c(nlon_out, nlat_out))
  for (i in 1:nlon_out) {
    i_start <- (i - 1) * agg_factor + 1
    i_end <- i * agg_factor
    lon_slice <- data_5min[i_start:i_end, ]
    for (j in 1:nlat_out) {
      j_start <- (j - 1) * agg_factor + 1
      j_end <- j * agg_factor
      block <- lon_slice[, j_start:j_end]
      data_halfdeg[i, j] <- mean(block, na.rm = TRUE)
      if (is.nan(data_halfdeg[i, j])) data_halfdeg[i, j] <- NA
    }
  }
  data_halfdeg
}

# Helper: load raw 5-arcmin spatial pattern (year 2000)
load_spatial_5min <- function(crop) {
  if (!(crop %in% names(crop_to_inputfile))) {
    warning(paste("No 5min mapping for crop", crop))
    return(NULL)
  }
  input_crop <- crop_to_inputfile[[crop]]
  input_file <- paste0(base_path_5min, "/", input_crop, "Napprate_gadm_subnational.nc")
  if (!file.exists(input_file)) {
    warning(paste("5min file not found:", input_file))
    return(NULL)
  }
  nc_spatial <- nc_open(input_file)
  spatial_data <- ncvar_get(nc_spatial, varid = paste0(input_crop, "Napprate"))
  lon_5min <- ncvar_get(nc_spatial, varid = "longitude")
  lat_5min <- ncvar_get(nc_spatial, varid = "latitude")
  missval_spatial <- ncatt_get(nc_spatial, varid = paste0(input_crop, "Napprate"), attname = "_FillValue")
  if (missval_spatial$hasatt) {
    spatial_data[spatial_data == missval_spatial$value] <- NA
  }
  spatial_data[abs(spatial_data) >= 1e+19] <- NA
  spatial_data[abs(spatial_data) < 1e-6 & !is.na(spatial_data)] <- NA
  if (length(dim(spatial_data)) == 3) {
    spatial_data_2d <- spatial_data[, , 1]
  } else {
    spatial_data_2d <- spatial_data
  }
  nc_close(nc_spatial)
  list(data = spatial_data_2d, lon = lon_5min, lat = lat_5min)
}

# Settings
crops_to_process <- c("mai", "wwh")  # maize and winter wheat
output_dir <- "/p/projects/macmit/data/GGCMI/AgMIP.input/phase3/n-fertilizer/group_iii"

# File paths
ssp585_file <- "/p/tmp/lisano/fertilizer_Katja/outcome_files/late_gapfilling/dez2025/normal_version/no_bf/3_input_fixed/ssp585soc-adapt/n-fertilizer-15crops_image_gfdl-esm4_ssp585_annual_2015_2100_gridcell_fixed_prevalidation.nc"
histsoc_file <- "/p/projects/isimip/isimip/lisano/fertilizer/normal_version/3_input_fixed/histsoc/n-fertilizer-15crops_histsoc_annual_1850_2014_gridcell_fixed_prevalidation.nc"

# Verify files exist
if (!file.exists(ssp585_file)) {
  stop(paste("SSP585 file not found:", ssp585_file))
}
if (!file.exists(histsoc_file)) {
  stop(paste("Histsoc file not found:", histsoc_file))
}

cat("Processing external data files for diagnostic plots...\n\n")

# ============================================================================
# Process SSP585 scenario
# ============================================================================
cat("=== Processing SSP585 scenario ===\n")
nc_ssp585 <- nc_open(ssp585_file)

# Get coordinates
lon <- ncvar_get(nc_ssp585, "lon")
lat <- ncvar_get(nc_ssp585, "lat")

for (crop in crops_to_process) {
  cat(paste("\nProcessing crop:", crop, "\n"))
  
  # Read the variable for this crop
  # Map crop codes to variable names in the NetCDF files
  if (crop == "mai") {
    varname <- "maize_fertl"
  } else if (crop == "wwh") {
    varname <- "wheat_fertl"
  } else {
    cat(paste("Unknown crop code:", crop, ". Skipping.\n"))
    next
  }
  
  # Check if variable exists in file
  if (!(varname %in% names(nc_ssp585$var))) {
    cat(paste("Variable", varname, "not found in SSP585 file. Skipping.\n"))
    next
  }
  
  # Get data [lon, lat, time]
  data_ssp585 <- ncvar_get(nc_ssp585, varname)
  
  # Handle missing values
  missval <- ncatt_get(nc_ssp585, varname, "_FillValue")
  if (missval$hasatt) {
    data_ssp585[data_ssp585 == missval$value] <- NA
  }
  data_ssp585[abs(data_ssp585) >= 1e+19] <- NA
  data_ssp585[abs(data_ssp585) < 1e-6 & !is.na(data_ssp585)] <- NA
  
  # For this ISIMIP data, use year 2015 as base_rate (first year of future data)
  # In the original script, year 2000 was used, but this data starts at 2015
  base_rate <- data_ssp585[, , 1]  # First year (2015)
  
  # For timeseries, use the same data (it's already the "scaled" result)
  # Since we're comparing the final output, timeseries = scaled_data
  scaled_data <- data_ssp585
  timeseries <- data_ssp585
  
  # Run diagnostics
  plot_diagnostics(
    base_rate = base_rate,
    scaled_data = scaled_data,
    timeseries = timeseries,
    lon = lon,
    lat = lat,
    start_year = 2015,
    end_year = 2100,
    crop = crop,
    scenario = "ssp585",
    output_dir = output_dir,
    method = "ISIMIP",
    iam = "image",
    gcm = "gfdl-esm4"
  )
}

nc_close(nc_ssp585)

# ============================================================================
# Process HISTSOC scenario
# ============================================================================
cat("\n=== Processing HISTSOC scenario ===\n")
nc_histsoc <- nc_open(histsoc_file)

# Get coordinates (should be same as ssp585, but read again to be safe)
lon <- ncvar_get(nc_histsoc, "lon")
lat <- ncvar_get(nc_histsoc, "lat")

for (crop in crops_to_process) {
  cat(paste("\nProcessing crop:", crop, "\n"))
  
  # Read the variable for this crop
  # Map crop codes to variable names in the NetCDF files
  if (crop == "mai") {
    varname <- "maize_fertl"
  } else if (crop == "wwh") {
    varname <- "wheat_fertl"
  } else {
    cat(paste("Unknown crop code:", crop, ". Skipping.\n"))
    next
  }
  
  # Check if variable exists in file
  if (!(varname %in% names(nc_histsoc$var))) {
    cat(paste("Variable", varname, "not found in HISTSOC file. Skipping.\n"))
    next
  }
  
  # Get data [lon, lat, time]
  data_histsoc <- ncvar_get(nc_histsoc, varname)
  
  # Handle missing values
  missval <- ncatt_get(nc_histsoc, varname, "_FillValue")
  if (missval$hasatt) {
    data_histsoc[data_histsoc == missval$value] <- NA
  }
  data_histsoc[abs(data_histsoc) >= 1e+19] <- NA
  data_histsoc[abs(data_histsoc) < 1e-6 & !is.na(data_histsoc)] <- NA
  
  # Find year 2000 index (histsoc is 1850-2014, so year 2000 is index 151)
  base_idx <- 2000 - 1850 + 1

  if (base_idx > 0 && base_idx <= dim(data_histsoc)[3]) {
    base_rate <- data_histsoc[, , base_idx]  # Year 2000
  } else {
    cat("Year 2000 not in range, using first year\n")
    base_rate <- data_histsoc[, , 1]
    base_idx <- 1
  }
  
  # Load raw 5-arcmin spatial data for comparison
  spatial_5min <- load_spatial_5min(crop)
  if (is.null(spatial_5min)) {
    cat("Warning: 5min spatial data unavailable; skipping 5min comparison page\n")
  }
  
  # Aggregate 5-arcmin data to 0.5-degree for scatter plot comparison
  base_rate_5min_agg <- NULL
  if (!is.null(spatial_5min)) {
    base_rate_5min_agg <- aggregate_to_halfdegree(
      spatial_5min$data,
      spatial_5min$lon,
      spatial_5min$lat
    )
  }
  
  # For timeseries, use the same data
  scaled_data <- data_histsoc
  timeseries <- data_histsoc
  
  # Run diagnostics
  plot_diagnostics(
    base_rate = base_rate,
    scaled_data = scaled_data,
    timeseries = timeseries,
    lon = lon,
    lat = lat,
    start_year = 1850,
    end_year = 2014,
    crop = crop,
    scenario = "histsoc",
    output_dir = output_dir,
    method = "ISIMIP",
    spatial_data_5min = if (!is.null(spatial_5min)) spatial_5min$data else NULL,
    lon_5min = if (!is.null(spatial_5min)) spatial_5min$lon else NULL,
    lat_5min = if (!is.null(spatial_5min)) spatial_5min$lat else NULL,
    base_rate_5min_agg = base_rate_5min_agg
  )
}

nc_close(nc_histsoc)

cat("\n=== All processing complete ===\n")
cat(paste("Diagnostic PDFs saved to:", output_dir, "\n"))
