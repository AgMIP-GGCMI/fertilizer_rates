# ============================================================================
# Plot-diagnostics helpers extracted from plot_diagnostics()
# ============================================================================
# Sourced by fertilizer_scaling_functions.R. All functions assume that
# plot_diagnostics (in fertilizer_scaling_functions.R) has already opened
# the appropriate graphics device and set up par().
# ============================================================================

# ----------------------------------------------------------------------------
# build_sample_locations
# ----------------------------------------------------------------------------
# Returns the 10-row data frame of sample lat/lon/description values used
# for time-series plots and map overlays in plot_diagnostics.
# ----------------------------------------------------------------------------
build_sample_locations <- function() {
  data.frame(
    lat = c(8.0, 9.5, 26.0, -30.0, 40.0, 42.0, 30.0, 34.0, -15.0, -23.0),
    lon = c(-2.0, 37.0, 87.0, -60.0, -5.0, -93.5, 75.0, 114.0, -48.0, -47.0),
    description = c(
      "W Africa (Ghana)", "E Africa (Ethiopia)", "E India (Bihar)",
      "S Brazil (RS)", "N Spain", "US Iowa", "NW India (Punjab)",
      "N China (Henan)", "C Brazil (Mato Grosso)", "SE Brazil (SP)"
    ),
    stringsAsFactors = FALSE
  )
}

# ----------------------------------------------------------------------------
# add_sample_markers
# ----------------------------------------------------------------------------
# Overlays numbered circle markers at each sample location on the currently
# active map. Caller is responsible for calling this only when a map is
# currently plotted.
#
# Args:
#   lon, lat: Grid-cell coordinate vectors for the map being overlaid.
#   sample_locations: Data frame from build_sample_locations().
# ----------------------------------------------------------------------------
add_sample_markers <- function(lon, lat, sample_locations) {
  for (k in 1:nrow(sample_locations)) {
    target_lon <- sample_locations$lon[k]
    target_lat <- sample_locations$lat[k]

    i <- which.min(abs(lon - target_lon))
    j <- which.min(abs(lat - target_lat))
    marker_lon <- lon[i]
    marker_lat <- lat[j]

    points(marker_lon, marker_lat, pch = 21, col = "black", bg = NA,
           cex = 1.5, lwd = 0.8)
    text(marker_lon, marker_lat, k, cex = 0.5, col = "black", font = 2)
  }
}

# ----------------------------------------------------------------------------
# plot_map
# ----------------------------------------------------------------------------
# Renders a single 2D map with symmetric or sequential color scaling.
# Optionally overlays sample-location markers.
#
# Args:
#   lon, lat: Grid-cell coordinate vectors.
#   data: [nlon x nlat] matrix to plot.
#   title: Plot title.
#   diverging: If TRUE, use a zero-centered diverging palette.
#   add_markers: If TRUE, overlay sample-location markers (requires
#     sample_locations to be non-NULL).
#   sample_locations: Data frame from build_sample_locations(). Required
#     when add_markers = TRUE.
# ----------------------------------------------------------------------------
plot_map <- function(lon, lat, data, title, diverging = FALSE,
                     add_markers = TRUE, sample_locations = NULL) {
  data_plot <- data

  valid_data <- data_plot[is.finite(data_plot) & abs(data_plot) < 1e+10]
  if (length(valid_data) > 0) {
    zlim <- range(valid_data, na.rm = TRUE)
    if (diverging) {
      max_abs <- max(abs(zlim), na.rm = TRUE)
      zlim <- c(-max_abs, max_abs)
    }
  } else {
    zlim <- c(0, 1)
  }

  if (diverging) {
    col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0",
                                    "#f7f7f7",
                                    "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)
  } else {
    col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0", "#fefebe",
                                    "#fddbc7", "#ef8a62", "#b2182b"))(100)
  }

  image.plot(lon, lat, data_plot,
             main = title,
             xlab = "Longitude", ylab = "Latitude",
             col = col_ramp,
             zlim = zlim,
             ylim = c(-65, 90))

  if (add_markers) {
    add_sample_markers(lon, lat, sample_locations)
  }
}

# ----------------------------------------------------------------------------
# plot_aggregation_comparison
# ----------------------------------------------------------------------------
# Renders a 4-panel aggregation-comparison page: original 5-arcmin data,
# aggregated 0.5-degree data, and their respective distribution histograms.
# Sets par(mfrow = c(2, 2)) on entry and resets to par(mfrow = c(4, 3),
# mar = c(4, 4, 3, 6)) on exit — caller relies on this reset.
# ----------------------------------------------------------------------------
plot_aggregation_comparison <- function(base_rate, spatial_data_5min, lon, lat,
                                        lon_5min, lat_5min, crop) {
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 6))

  valid_5min <- spatial_data_5min[is.finite(spatial_data_5min) & abs(spatial_data_5min) < 1e+10]
  if (length(valid_5min) > 0) {
    zlim_5min <- quantile(valid_5min, c(0.02, 0.98), na.rm = TRUE)
  } else {
    zlim_5min <- c(0, 1)
  }

  col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0", "#fefebe",
                                  "#fddbc7", "#ef8a62", "#b2182b"))(100)

  lat_5min_plot <- rev(lat_5min)
  data_5min_plot <- spatial_data_5min[, ncol(spatial_data_5min):1]
  image.plot(lon_5min, lat_5min_plot, data_5min_plot,
             main = paste(crop, "- Original 5-arcmin Data (full resolution)"),
             xlab = "Longitude", ylab = "Latitude",
             col = col_ramp,
             zlim = zlim_5min,
             ylim = c(-65, 90))

  data_halfdeg_plot <- base_rate
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

  par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))
}

# ----------------------------------------------------------------------------
# plot_pattern_maps
# ----------------------------------------------------------------------------
# Renders the five map panels: original pattern (year 2000), scaled first /
# middle / last, and the last-first difference map (diverging palette).
# ----------------------------------------------------------------------------
plot_pattern_maps <- function(base_rate, scaled_data, lon, lat, sample_locations,
                              start_year, end_year, mid_idx, crop, method) {
  ntime <- dim(scaled_data)[3]
  mid_year <- start_year + mid_idx - 1

  plot_map(lon, lat, base_rate,
           paste(crop, "- Original Pattern (Year 2000) [Method:", method, "]"),
           sample_locations = sample_locations)

  plot_map(lon, lat, scaled_data[, , 1],
           paste(crop, "- Scaled Pattern (Year", start_year, ")"),
           sample_locations = sample_locations)

  plot_map(lon, lat, scaled_data[, , mid_idx],
           paste(crop, "- Scaled Pattern (Year", mid_year, ")"),
           sample_locations = sample_locations)

  plot_map(lon, lat, scaled_data[, , ntime],
           paste(crop, "- Scaled Pattern (Year", end_year, ")"),
           sample_locations = sample_locations)

  first_year_data <- scaled_data[, , 1]
  last_year_data <- scaled_data[, , ntime]
  diff_map <- last_year_data - first_year_data

  plot_map(lon, lat, diff_map,
           paste(crop, "- Change (", end_year, "-", start_year, ")"),
           diverging = TRUE, sample_locations = sample_locations)
}

# ----------------------------------------------------------------------------
# plot_base_year_scatter
# ----------------------------------------------------------------------------
# Renders a scatter plot of scaled vs original values at the base year,
# with 1:1 reference line and correlation / RMSE / bias legend.
# ----------------------------------------------------------------------------
plot_base_year_scatter <- function(base_rate, scaled_data, base_idx, base_year, crop,
                                   scaled_base_override = NULL) {
  ntime <- dim(scaled_data)[3]
  if (!is.null(scaled_base_override)) {
    scaled_base <- scaled_base_override
    valid <- is.finite(base_rate) & is.finite(scaled_base)
    if (any(valid)) {
      x <- base_rate[valid]
      y <- scaled_base[valid]
      plot(x, y, pch = 16, cex = 0.4,
           xlab = "Original (Year 2000)", ylab = "Scaled (Year 2000)",
           main = paste(crop, "- Scatter Year", base_year))
      abline(0, 1, col = "red", lwd = 2)
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
  } else if (base_idx >= 1 && base_idx <= ntime) {
    scaled_base <- scaled_data[, , base_idx]
    valid <- is.finite(base_rate) & is.finite(scaled_base)
    if (any(valid)) {
      x <- base_rate[valid]
      y <- scaled_base[valid]
      plot(x, y, pch = 16, cex = 0.4,
           xlab = "Original (Year 2000)", ylab = "Scaled (Year 2000)",
           main = paste(crop, "- Scatter Year", base_year))
      abline(0, 1, col = "red", lwd = 2)
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
}

# ----------------------------------------------------------------------------
# plot_relative_change_hist
# ----------------------------------------------------------------------------
# Renders a histogram of per-cell relative change (last year / base year),
# with quantile legend. Returns the count of valid relative-change cells
# (preserved from the original code where it was assigned but unused).
# ----------------------------------------------------------------------------
plot_relative_change_hist <- function(scaled_data, base_idx, base_year, end_year, crop,
                                      scaled_base_override = NULL) {
  ntime <- dim(scaled_data)[3]
  valid_rel_count <- 0
  if (!is.null(scaled_base_override)) {
    scaled_base <- scaled_base_override
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
  } else if (base_idx >= 1 && base_idx <= ntime) {
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
  invisible(valid_rel_count)
}

# ----------------------------------------------------------------------------
# plot_spatial_ts_ratio
# ----------------------------------------------------------------------------
# Renders a ratio map of spatial-base vs timeseries-base at the base year,
# with ratios capped to [0.2, 5] for visualization. Prints a console
# diagnostic line reporting cells that differ by more than 50%.
#
# The sample_locations arg matches the signature convention used by other
# map-producing section functions (parity with plot_pattern_maps, etc.).
# It is accepted but not overlaid on this particular map — the current
# code does not draw markers on the ratio map, and preserving output
# byte-for-byte means not adding any.
# ----------------------------------------------------------------------------
plot_spatial_ts_ratio <- function(base_rate, timeseries, base_idx, lon, lat,
                                  sample_locations, crop,
                                  base_timeseries_override = NULL) {
  ntime <- dim(timeseries)[3]
  if (!is.null(base_timeseries_override)) {
    ts_base <- base_timeseries_override
    valid_ratio <- is.finite(base_rate) & is.finite(ts_base) & base_rate > 0.1 & ts_base > 0.1

    if (any(valid_ratio)) {
      ratio_map <- array(NA, dim = dim(base_rate))
      ratio_map[valid_ratio] <- base_rate[valid_ratio] / ts_base[valid_ratio]

      ratio_capped <- ratio_map
      ratio_capped[ratio_capped > 5] <- 5
      ratio_capped[ratio_capped < 0.2] <- 0.2

      data_plot <- ratio_capped
      valid_data <- data_plot[is.finite(data_plot)]

      if (length(valid_data) > 0) {
        zlim <- c(0.2, 5)

        col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0",
                                        "#f7f7f7",
                                        "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)

        image.plot(lon, lat, data_plot,
                   main = paste(crop, "- Spatial/TS Ratio (Year 2000)"),
                   xlab = "Longitude", ylab = "Latitude",
                   col = col_ramp,
                   zlim = zlim,
                   ylim = c(-65, 90))

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
  } else if (base_idx >= 1 && base_idx <= ntime) {
    ts_base <- timeseries[, , base_idx]

    valid_ratio <- is.finite(base_rate) & is.finite(ts_base) & base_rate > 0.1 & ts_base > 0.1

    if (any(valid_ratio)) {
      ratio_map <- array(NA, dim = dim(base_rate))
      ratio_map[valid_ratio] <- base_rate[valid_ratio] / ts_base[valid_ratio]

      ratio_capped <- ratio_map
      ratio_capped[ratio_capped > 5] <- 5
      ratio_capped[ratio_capped < 0.2] <- 0.2

      data_plot <- ratio_capped
      valid_data <- data_plot[is.finite(data_plot)]

      if (length(valid_data) > 0) {
        zlim <- c(0.2, 5)

        col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0",
                                        "#f7f7f7",
                                        "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)

        image.plot(lon, lat, data_plot,
                   main = paste(crop, "- Spatial/TS Ratio (Year 2000)"),
                   xlab = "Longitude", ylab = "Latitude",
                   col = col_ramp,
                   zlim = zlim,
                   ylim = c(-65, 90))

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
}

# ----------------------------------------------------------------------------
# plot_sample_timeseries
# ----------------------------------------------------------------------------
# Renders one line plot showing original vs scaled time series at each
# sample location.
# ----------------------------------------------------------------------------
plot_sample_timeseries <- function(base_rate, scaled_data, timeseries, lon, lat,
                                   start_year, end_year, sample_locations, crop) {
  # ===== SAMPLE LOCATION TIME SERIES EXTRACTION =====
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

    sample_cells[[k]] <- list(
      i = i, j = j,
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
}

# ----------------------------------------------------------------------------
# plot_distribution_histograms
# ----------------------------------------------------------------------------
# Renders three overlay histograms: spatial-base vs scaled-last,
# timeseries-base vs timeseries-last, and per-cell change deltas.
# ----------------------------------------------------------------------------
plot_distribution_histograms <- function(base_rate, scaled_data, timeseries,
                                         base_idx, base_year, end_year, crop,
                                         base_timeseries_override = NULL) {
  ntime <- dim(scaled_data)[3]

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

  ts_base_for_diag <- NULL
  if (!is.null(base_timeseries_override)) {
    ts_base_for_diag <- base_timeseries_override
  } else if (!is.na(base_idx) && base_idx >= 1 && base_idx <= ntime) {
    ts_base_for_diag <- timeseries[, , base_idx]
  }

  if (!is.null(ts_base_for_diag)) {
    ts_base_vals <- ts_base_for_diag[is.finite(ts_base_for_diag) & ts_base_for_diag > 0]
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
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }

  if (!is.null(ts_base_for_diag)) {
    change_scaled <- (scaled_data[, , ntime] - base_rate)[is.finite(scaled_data[, , ntime] - base_rate)]
    change_ts <- (timeseries[, , ntime] - ts_base_for_diag)[is.finite(timeseries[, , ntime] - ts_base_for_diag)]

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
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }
}

# ----------------------------------------------------------------------------
# plot_outlier_scatter
# ----------------------------------------------------------------------------
# Renders two scatter plots on a new PDF page: scaling factor vs final
# value with log-scale y-axis, and an outliers-only detail scatter with
# coloring by base-rate quartile. Prints analysis stats to the console.
# ----------------------------------------------------------------------------
plot_outlier_scatter <- function(base_rate, scaled_data, timeseries,
                                 base_idx, base_year, end_year,
                                 base_timeseries_override = NULL) {
  ntime <- dim(scaled_data)[3]

  if (!is.null(base_timeseries_override)) {
    scaling_factors <- (timeseries[, , ntime] / base_timeseries_override)
  } else if (!is.na(base_idx) && base_idx >= 1 && base_idx <= ntime) {
    scaling_factors <- (timeseries[, , ntime] / timeseries[, , base_idx])
  } else {
    plot.new()
    text(0.5, 0.5, "Base year outside range")
    plot.new()
    text(0.5, 0.5, "Base year outside range")
    return(invisible(NULL))
  }

  final_values <- scaled_data[, , ntime]

  sf_flat <- as.vector(scaling_factors)
  fv_flat <- as.vector(final_values)
  valid_mask <- is.finite(sf_flat) & is.finite(fv_flat) &
                sf_flat > 0 & sf_flat < Inf & fv_flat > 0

  sf_valid <- sf_flat[valid_mask]
  fv_valid <- fv_flat[valid_mask]

  if (length(sf_valid) > 100) {
    outlier_threshold <- 1000
    is_outlier <- fv_valid > outlier_threshold

    point_colors <- ifelse(is_outlier, rgb(1, 0, 0, 0.7), rgb(0, 0, 1, 0.2))

    plot(sf_valid, fv_valid,
         pch = 16, cex = 0.4, col = point_colors,
         log = "y",
         main = paste("Scaling Factor vs Final Value - Log Scale (", end_year, ")", sep = ""),
         xlab = paste("Scaling Factor (", end_year, "/", base_year, ")", sep = ""),
         ylab = paste("Final Scaled Value (kg/ha, ", end_year, ") [LOG SCALE]", sep = ""))

    abline(v = 1, col = "gray50", lwd = 2, lty = 2)
    abline(h = outlier_threshold, col = "red", lwd = 2, lty = 2)

    n_outliers <- sum(is_outlier)
    pct_outliers <- 100 * n_outliers / length(fv_valid)
    median_sf_normal <- median(sf_valid[!is_outlier], na.rm = TRUE)
    median_sf_outlier <- if(n_outliers > 0) median(sf_valid[is_outlier], na.rm = TRUE) else NA

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

  if (length(sf_valid) > 100 && sum(is_outlier) > 0) {
    sf_outliers <- sf_valid[is_outlier]
    fv_outliers <- fv_valid[is_outlier]

    base_flat <- as.vector(base_rate)
    base_valid <- base_flat[valid_mask]
    base_outliers <- base_valid[is_outlier]

    base_quartiles <- quantile(base_outliers, probs = c(0.25, 0.5, 0.75), na.rm = TRUE)
    outlier_colors <- ifelse(base_outliers < base_quartiles[1], rgb(1, 0.8, 0, 0.6),
                       ifelse(base_outliers < base_quartiles[2], rgb(1, 0.5, 0, 0.6),
                       ifelse(base_outliers < base_quartiles[3], rgb(1, 0.2, 0, 0.6),
                              rgb(0.8, 0, 0, 0.6))))

    plot(sf_outliers, fv_outliers,
         pch = 16, cex = 0.8, col = outlier_colors,
         main = paste("OUTLIERS ONLY: Scaling Factor vs Final Value (", end_year, ")", sep = ""),
         xlab = paste("Scaling Factor (", end_year, "/", base_year, ")", sep = ""),
         ylab = paste("Final Scaled Value (kg/ha, ", end_year, ")", sep = ""))

    abline(v = 1, col = "gray50", lwd = 2, lty = 2)

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
}

# ----------------------------------------------------------------------------
# plot_na_provenance_masks
# ----------------------------------------------------------------------------
# Renders a 2x2 diagnostics page with binary masks to explain why cells are NA
# in the final scaled output for a selected year.
# ----------------------------------------------------------------------------
plot_na_provenance_masks <- function(base_rate, scaled_t, ts_base, ts_t,
                                     lon, lat, crop, year_label) {
  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  par(mfrow = c(2, 3), mar = c(4, 4, 3, 6))

  plot_binary_mask <- function(mask, title, detail) {
    mask_num <- array(NA_real_, dim = dim(base_rate))
    mask_num[] <- 0
    mask_num[mask] <- 1
    image.plot(lon, lat, mask_num,
               main = paste0(title, "\n", detail),
               xlab = "Longitude", ylab = "Latitude",
               col = c("#eeeeee", "#b2182b"),
               zlim = c(0, 1),
               ylim = c(-65, 90),
               legend.mar = 4,
               axis.args = list(at = c(0, 1), labels = c("no", "yes")))
  }

  base_na <- !is.finite(base_rate)
  base_pos <- is.finite(base_rate) & base_rate > 0
  ts_base_na <- base_pos & !is.finite(ts_base)
  ts_base_nonpos <- base_pos & is.finite(ts_base) & ts_base <= 0
  ts_t_na_given_valid_base <- base_pos & is.finite(ts_base) & ts_base > 0 & !is.finite(ts_t)
  out_na_basepos <- base_pos & !is.finite(scaled_t)
  proc_introduced_na <- base_pos & !is.finite(scaled_t) &
    is.finite(ts_base) & ts_base > 0 & is.finite(ts_t)

  n_total <- length(base_rate)
  n_base_pos <- sum(base_pos, na.rm = TRUE)
  pct_total <- function(mask) sprintf("n=%d (%.1f%% of all cells)",
                                      sum(mask, na.rm = TRUE),
                                      100 * sum(mask, na.rm = TRUE) / n_total)
  pct_basepos <- function(mask) {
    if (n_base_pos == 0) return("n=0 (NA% of base>0)")
    sprintf("n=%d (%.1f%% of base>0)", sum(mask, na.rm = TRUE),
            100 * sum(mask, na.rm = TRUE) / n_base_pos)
  }

  plot_binary_mask(base_na,
                   paste(crop, "- Input mask: base map NA"),
                   pct_total(base_na))

  plot_binary_mask(ts_base_na,
                   paste(crop, "- Input mask: base>0 and TS(base) is NA"),
                   pct_basepos(ts_base_na))

  plot_binary_mask(ts_base_nonpos,
                   paste(crop, "- Input mask: base>0 and TS(base)<=0"),
                   pct_basepos(ts_base_nonpos))

  plot_binary_mask(ts_t_na_given_valid_base,
                   paste(crop, "- Input mask: base>0, TS(base)>0, TS(year) NA"),
                   pct_basepos(ts_t_na_given_valid_base))

  plot_binary_mask(out_na_basepos,
                   paste(crop, "- Output mask: final NA on base>0"),
                   paste("Year", year_label, "-", pct_basepos(out_na_basepos)))

  plot_binary_mask(proc_introduced_na,
                   paste(crop, "- Sanity: processing-introduced NA"),
                   pct_basepos(proc_introduced_na))
}
