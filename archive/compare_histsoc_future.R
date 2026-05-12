# ============================================================================
# ARCHIVED — not sourced by any active script
# ============================================================================
# Vestigial cross-scenario script that duplicates much of
# compare_relative_lambda's logic with its own drifted copy. Preserved
# here for reference only.
# ============================================================================

# ============================================================================
# Cross-Scenario Comparison: histsoc (2014) vs Future (2015)
# ============================================================================
#
# Purpose:
#   Compare scaled fertilizer rates at the transition point between historical
#   and future scenarios. Visualizes differences in relative and lambda methods
#   across SSP/IAM/GCM combinations.
#
# Usage:
#   Rscript compare_histsoc_future.R <crop> <ssp> <iam> <gcm>
#   Example: Rscript compare_histsoc_future.R mai ssp585 image gfdl-esm4
#
# Output:
#   - Cross-scenario comparison PDF: output_base_path/cross_scenario/{crop}_{ssp}_{iam}_{gcm}_histsoc-2014_vs_future-2015.pdf
#   - Maps: spatial differences and masks
#   - Density plots: relative and lambda method comparisons
#
# ============================================================================

library(ncdf4)
library(fields)

# Input/output paths (must match fertilizer_scaling.R)
output_base_path <- "/p/projects/macmit/data/GGCMI/AgMIP.input/phase3/n-fertilizer/group_iii"

# Crop list
cropnames <- c("swh", "wwh", "mai", "ri1", "ri2", "soy", "mil", "sor", "pea", "sgb", "cas", "rap", "sun", "nut", "sgc")

# ============================================================================
# HELPER: Plot map with diverging palette and mask
# ============================================================================
plot_cross_scenario_map <- function(lon, lat, data_histsoc, data_future, title, 
                                     method = "absolute_diff", zlim = NULL) {
  # Flip latitude for display
  data_histsoc_plot <- data_histsoc[, c(length(lat):1)]
  data_future_plot <- data_future[, c(length(lat):1)]
  
  # Compute difference or ratio
  if (method == "absolute_diff") {
    diff_data <- data_future_plot - data_histsoc_plot
    col_label <- "2015 - 2014 (kg/ha)"
    col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0", "#f7f7f7", 
                                     "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))
  } else if (method == "relative_change") {
    # Avoid division by zero and ensure both arrays are finite
    valid <- is.finite(data_histsoc_plot) & is.finite(data_future_plot) & data_histsoc_plot > 0
    diff_data <- array(NA, dim = dim(data_histsoc_plot))
    diff_data[valid] <- (data_future_plot[valid] - data_histsoc_plot[valid]) / data_histsoc_plot[valid] * 100
    col_label <- "% Change (2015 - 2014) / 2014"
    col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0", "#f7f7f7",
                                     "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))
  } else {
    stop("Unknown method:", method)
  }
  
  # Set zlim if not provided
  valid_diff <- diff_data[is.finite(diff_data)]
  if (is.null(zlim)) {
    zlim <- quantile(valid_diff, c(0.02, 0.98), na.rm = TRUE)
  }
  
  # Plot
  image.plot(lon, lat, diff_data,
             main = title,
             xlab = "Longitude", ylab = "Latitude",
             col = col_ramp(200),
             zlim = zlim,
             ylim = c(-65, 90),
             legend.mar = 6, legend.cex = 0.85, legend.line = 2.5,
             axis.args = list(cex.axis = 0.8))
  
  # Add mask: where difference is negligible
  mask_small <- abs(diff_data) < quantile(abs(valid_diff), 0.1, na.rm = TRUE)
  mask_small[!is.finite(mask_small)] <- FALSE
  contour(lon, lat, mask_small, levels = 0.5, drawlabels = FALSE, add = TRUE,
          col = rgb(0.5, 0.5, 0.5, 0.3), lwd = 0.5)
}

# ============================================================================
# HELPER: Density heatmap for 2D comparison
# ============================================================================
plot_comparison_density <- function(x, y, title, xlab = "2014 (histsoc)", ylab = "2015 (future)") {
  valid <- is.finite(x) & is.finite(y) & x > 0 & y > 0
  x <- x[valid]; y <- y[valid]
  
  if (length(x) < 10) {
    plot.new()
    text(0.5, 0.5, "Insufficient data for density plot")
    return(invisible(NULL))
  }
  
  # Trim 1% tails
  xq <- quantile(x, c(0.01, 0.99)); yq <- quantile(y, c(0.01, 0.99))
  xpad <- 0.02 * diff(xq); ypad <- 0.02 * diff(yq)
  xlim <- c(xq[1] - xpad, xq[2] + xpad)
  ylim <- c(yq[1] - ypad, yq[2] + ypad)
  
  # 2D histogram
  nbins <- 40
  xbreaks <- seq(xlim[1], xlim[2], length.out = nbins + 1)
  ybreaks <- seq(ylim[1], ylim[2], length.out = nbins + 1)
  xi <- findInterval(x, xbreaks, all.inside = TRUE)
  yi <- findInterval(y, ybreaks, all.inside = TRUE)
  z <- matrix(0, nrow = nbins, ncol = nbins)
  for (i in seq_along(x)) {
    z[xi[i], yi[i]] <- z[xi[i], yi[i]] + 1
  }
  z[z == 0] <- NA
  
  xc <- (xbreaks[-length(xbreaks)] + xbreaks[-1]) / 2
  yc <- (ybreaks[-length(ybreaks)] + ybreaks[-1]) / 2
  
  # Magma palette
  dens_palette <- colorRampPalette(c(
    "#fcfdbf", "#fef9c8", "#fcf0d0", "#fae4d6", "#f6d4db", "#eebcd7", "#e8a9ce",
    "#d991c5", "#c873b0", "#b35492", "#9d3072", "#7d1d4e", "#440154"
  ))
  
  zlim_range <- range(z, na.rm = TRUE)
  image.plot(xc, yc, z,
             main = title, xlab = xlab, ylab = ylab,
             col = dens_palette(200),
             zlim = zlim_range,
             legend.mar = 6, legend.line = 2.5, legend.cex = 0.85,
             axis.args = list(cex.axis = 0.8))
  
  # 1:1 reference line
  abline(0, 1, col = "red", lwd = 0.8, lty = 2)
}

# ============================================================================
# MAIN: Compare histsoc 2014 vs future 2015
# ============================================================================
compare_histsoc_future <- function(crop, ssp, iam, gcm) {
  
  print(paste(rep("=", 80), collapse = ""))
  print(paste("Cross-scenario comparison:", crop, "histsoc 2014 vs", ssp, iam, gcm, "2015"))
  print(paste(rep("=", 80), collapse = ""))
  
  # Build file paths matching the actual output structure
  file_histsoc_rel <- paste0(output_base_path, "/histsoc/relative/n-fertilizer_", crop,
                              "_histsoc_relative_annual_1850_2014.nc")
  file_histsoc_lambda <- paste0(output_base_path, "/histsoc/lambda/n-fertilizer_", crop,
                                 "_histsoc_lambda_annual_1850_2014.nc")
  file_future_rel <- paste0(output_base_path, "/", ssp, "soc-adapt/relative/n-fertilizer_", crop,
                             "_", iam, "_", gcm, "_", ssp, "_relative_annual_2015_2100.nc")
  file_future_lambda <- paste0(output_base_path, "/", ssp, "soc-adapt/lambda/n-fertilizer_", crop,
                                "_", iam, "_", gcm, "_", ssp, "_lambda_annual_2015_2100.nc")
  
  # Check files exist
  required_files <- c(file_histsoc_rel, file_histsoc_lambda, file_future_rel, file_future_lambda)
  missing <- required_files[!file.exists(required_files)]
  if (length(missing) > 0) {
    print(paste("ERROR: Missing files:"))
    print(paste("  ", missing, collapse = "\n  "))
    return(invisible(NULL))
  }
  
  # Load spatial coordinates from histsoc
  nc_histsoc <- nc_open(file_histsoc_rel)
  lon <- ncvar_get(nc_histsoc, "lon")
  lat <- ncvar_get(nc_histsoc, "lat")
  nc_close(nc_histsoc)
  
  # Build variable name from crop (fertl_<crop>)
  varname <- paste0("fertl_", crop)
  
  # Load histsoc data (last year = 2014, which is index 165 in 1850-2014)
  nc_histsoc_rel <- nc_open(file_histsoc_rel)
  histsoc_rel_2014 <- ncvar_get(nc_histsoc_rel, varname)[, , 165]  # 1850 + 164 = 2014
  nc_close(nc_histsoc_rel)
  
  nc_histsoc_lambda <- nc_open(file_histsoc_lambda)
  histsoc_lambda_2014 <- ncvar_get(nc_histsoc_lambda, varname)[, , 165]
  nc_close(nc_histsoc_lambda)
  
  # Load future data (first year = 2015, which is index 1 in 2015-2100)
  nc_future_rel <- nc_open(file_future_rel)
  future_rel_2015 <- ncvar_get(nc_future_rel, varname)[, , 1]
  nc_close(nc_future_rel)
  
  nc_future_lambda <- nc_open(file_future_lambda)
  future_lambda_2015 <- ncvar_get(nc_future_lambda, varname)[, , 1]
  nc_close(nc_future_lambda)
  
  # Create output directory
  output_dir <- paste0(output_base_path, "/cross_scenario")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create comparison PDF
  plot_file <- paste0(output_dir, "/", crop, "_", ssp, "_", iam, "_", gcm, 
                      "_histsoc-2014_vs_future-2015.pdf")
  
  tryCatch({
    pdf(plot_file, width = 16, height = 12)
    
    # Layout: 3 rows × 4 cols
    # Row 1: Relative method - maps and density
    # Row 2: Lambda method - maps and density
    # Row 3: Method comparison (rel vs lambda) for both years
    
    par(mfrow = c(3, 4), mar = c(3, 3, 2, 4), oma = c(0, 0, 2, 0))
    
    # Pre-compute unified zlim ranges for relative and lambda methods
    # This ensures visual comparability between methods
    
    # Absolute difference range (unified for relative and lambda)
    abs_diff_rel <- future_rel_2015 - histsoc_rel_2014
    abs_diff_lambda <- future_lambda_2015 - histsoc_lambda_2014
    abs_diff_combined <- c(abs_diff_rel[is.finite(abs_diff_rel)], 
                           abs_diff_lambda[is.finite(abs_diff_lambda)])
    zlim_abs <- quantile(abs_diff_combined, c(0.02, 0.98), na.rm = TRUE)
    
    # Percent change range (unified for relative and lambda)
    pct_change_rel <- (future_rel_2015 - histsoc_rel_2014) / histsoc_rel_2014 * 100
    pct_change_lambda <- (future_lambda_2015 - histsoc_lambda_2014) / histsoc_lambda_2014 * 100
    pct_change_combined <- c(pct_change_rel[is.finite(pct_change_rel)],
                             pct_change_lambda[is.finite(pct_change_lambda)])
    zlim_pct <- quantile(pct_change_combined, c(0.02, 0.98), na.rm = TRUE)
    
    # ===== ROW 1: RELATIVE METHOD =====
    # Map: absolute difference
    plot_cross_scenario_map(lon, lat, histsoc_rel_2014, future_rel_2015,
                            "Relative: 2015 - 2014 (absolute)",
                            method = "absolute_diff", zlim = zlim_abs)
    
    # Map: percent change
    plot_cross_scenario_map(lon, lat, histsoc_rel_2014, future_rel_2015,
                            "Relative: % Change",
                            method = "relative_change", zlim = zlim_pct)
    
    # Density: 2014 vs 2015
    rel_2014_flat <- as.vector(histsoc_rel_2014)
    rel_2015_flat <- as.vector(future_rel_2015)
    valid_rel <- is.finite(rel_2014_flat) & is.finite(rel_2015_flat) & 
                 rel_2014_flat > 0 & rel_2015_flat > 0
    plot_comparison_density(rel_2014_flat[valid_rel], rel_2015_flat[valid_rel],
                            "Relative: 2014 vs 2015 density",
                            xlab = "2014 (histsoc)", ylab = "2015 (future)")
    
    # Histogram: changes
    rel_change <- rel_2015_flat[valid_rel] - rel_2014_flat[valid_rel]
    hist(rel_change, breaks = 40, col = "steelblue", border = "steelblue",
         main = "Relative: Change distribution", xlab = "2015 - 2014 (kg/ha)")
    abline(v = 0, col = "red", lwd = 2, lty = 2)
    
    # ===== ROW 2: LAMBDA METHOD =====
    # Map: absolute difference
    plot_cross_scenario_map(lon, lat, histsoc_lambda_2014, future_lambda_2015,
                            "Lambda: 2015 - 2014 (absolute)",
                            method = "absolute_diff", zlim = zlim_abs)
    
    # Map: percent change
    plot_cross_scenario_map(lon, lat, histsoc_lambda_2014, future_lambda_2015,
                            "Lambda: % Change",
                            method = "relative_change", zlim = zlim_pct)
    
    # Density: 2014 vs 2015
    lambda_2014_flat <- as.vector(histsoc_lambda_2014)
    lambda_2015_flat <- as.vector(future_lambda_2015)
    valid_lambda <- is.finite(lambda_2014_flat) & is.finite(lambda_2015_flat) & 
                    lambda_2014_flat > 0 & lambda_2015_flat > 0
    plot_comparison_density(lambda_2014_flat[valid_lambda], lambda_2015_flat[valid_lambda],
                            "Lambda: 2014 vs 2015 density",
                            xlab = "2014 (histsoc)", ylab = "2015 (future)")
    
    # Histogram: changes
    lambda_change <- lambda_2015_flat[valid_lambda] - lambda_2014_flat[valid_lambda]
    hist(lambda_change, breaks = 40, col = "coral", border = "coral",
         main = "Lambda: Change distribution", xlab = "2015 - 2014 (kg/ha)")
    abline(v = 0, col = "red", lwd = 2, lty = 2)
    
    # ===== ROW 3: RELATIVE VS LAMBDA COMPARISON =====
    # 2014: Relative vs Lambda density
    plot_comparison_density(rel_2014_flat[valid_rel & valid_lambda], 
                            lambda_2014_flat[valid_lambda & valid_rel],
                            "2014 (histsoc): Relative vs Lambda",
                            xlab = "Relative", ylab = "Lambda")
    
    # 2015: Relative vs Lambda density
    plot_comparison_density(rel_2015_flat[valid_rel & valid_lambda],
                            lambda_2015_flat[valid_lambda & valid_rel],
                            "2015 (future): Relative vs Lambda",
                            xlab = "Relative", ylab = "Lambda")
    
    # Difference map: Lambda - Relative (2014)
    diff_methods_2014 <- histsoc_lambda_2014 - histsoc_rel_2014
    diff_methods_2014_plot <- diff_methods_2014[, c(length(lat):1)]
    valid_diff <- diff_methods_2014_plot[is.finite(diff_methods_2014_plot)]
    zlim_methods <- quantile(abs(valid_diff), 0.98, na.rm = TRUE) * c(-1, 1)
    
    col_ramp_methods <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0", "#f7f7f7",
                                            "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))
    image.plot(lon, lat, diff_methods_2014_plot,
               main = "2014: Lambda - Relative",
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp_methods(200),
               zlim = zlim_methods,
               ylim = c(-65, 90),
               legend.mar = 6, legend.cex = 0.85, legend.line = 2.5,
               axis.args = list(cex.axis = 0.8))
    
    # Difference map: Lambda - Relative (2015)
    diff_methods_2015 <- histsoc_lambda_2014 - histsoc_rel_2014  # Note: use 2014 for comparison
    diff_methods_2015_plot <- diff_methods_2015[, c(length(lat):1)]
    image.plot(lon, lat, diff_methods_2015_plot,
               main = "2014: Lambda - Relative (for ref)",
               xlab = "Longitude", ylab = "Latitude",
               col = col_ramp_methods(200),
               zlim = zlim_methods,
               ylim = c(-65, 90),
               legend.mar = 6, legend.cex = 0.85, legend.line = 2.5,
               axis.args = list(cex.axis = 0.8))
    
    # Summary statistics
    plot.new()
    
    stats_text <- sprintf(
      "Cross-Scenario Transition Statistics\n\n
       Crop: %s | SSP: %s | IAM: %s | GCM: %s\n\n
       RELATIVE METHOD:\n
       - 2014 mean: %.2f kg/ha\n
       - 2015 mean: %.2f kg/ha\n
       - Mean change: %.2f kg/ha\n
       - Percent change: %.1f%%\n\n
       LAMBDA METHOD:\n
       - 2014 mean: %.2f kg/ha\n
       - 2015 mean: %.2f kg/ha\n
       - Mean change: %.2f kg/ha\n
       - Percent change: %.1f%%\n\n
       METHOD DIFFERENCES (2014):\n
       - Lambda - Relative (mean): %.2f kg/ha\n
       - Relative higher: %.1f%% of cells\n",
      crop, ssp, iam, gcm,
      mean(rel_2014_flat[valid_rel], na.rm = TRUE),
      mean(rel_2015_flat[valid_rel], na.rm = TRUE),
      mean(rel_change, na.rm = TRUE),
      mean(rel_change / rel_2014_flat[valid_rel] * 100, na.rm = TRUE),
      mean(lambda_2014_flat[valid_lambda], na.rm = TRUE),
      mean(lambda_2015_flat[valid_lambda], na.rm = TRUE),
      mean(lambda_change, na.rm = TRUE),
      mean(lambda_change / lambda_2014_flat[valid_lambda] * 100, na.rm = TRUE),
      mean(diff_methods_2014_plot[is.finite(diff_methods_2014_plot)], na.rm = TRUE),
      sum(histsoc_rel_2014 > histsoc_lambda_2014, na.rm = TRUE) / 
        sum(!is.na(histsoc_rel_2014) & !is.na(histsoc_lambda_2014)) * 100
    )
    
    text(0.1, 0.5, stats_text, cex = 0.8, adj = c(0, 0.5))
    
    mtext(paste("histsoc 2014 vs", ssp, iam, gcm, "2015 -", crop), 
          side = 3, outer = TRUE, line = 0.5, cex = 1.2, font = 2)
    
    dev.off()
    print(paste("Comparison plot saved to", plot_file))
    
  }, error = function(e) {
    print(paste("ERROR in cross-scenario comparison:", e$message))
    if (dev.cur() > 1) dev.off()
  })
}

# ============================================================================
# EXECUTION
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop("Usage: Rscript compare_histsoc_future.R <crop> <ssp> <iam> <gcm>\n",
       "Example: Rscript compare_histsoc_future.R mai ssp585 image gfdl-esm4")
}

crop <- args[1]
ssp <- args[2]
iam <- args[3]
gcm <- args[4]

# Validate inputs
if (!(crop %in% cropnames)) {
  stop(paste("Invalid crop:", crop))
}

compare_histsoc_future(crop, ssp, iam, gcm)
