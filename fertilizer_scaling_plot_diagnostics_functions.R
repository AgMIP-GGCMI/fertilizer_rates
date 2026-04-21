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
  data_plot <- data[, c(length(lat):1)]

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
plot_base_year_scatter <- function(base_rate, scaled_data, base_idx, base_year, crop) {
  ntime <- dim(scaled_data)[3]
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
plot_relative_change_hist <- function(scaled_data, base_idx, base_year, end_year, crop) {
  ntime <- dim(scaled_data)[3]
  valid_rel_count <- 0
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
  invisible(valid_rel_count)
}
