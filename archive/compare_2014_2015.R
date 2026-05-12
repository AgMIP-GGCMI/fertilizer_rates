# ============================================================================
# Archived: compare_2014_2015
# ============================================================================
# Previously lived in fertilizer_scaling_functions.R. Defined but never
# called from anywhere in the codebase. Preserved here for reference only;
# not sourced by any active script.
# ============================================================================

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
