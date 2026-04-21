#!/usr/bin/env Rscript
# ============================================================================
# render_diagnostics_png.R
# ============================================================================
# Verification harness for the plot_diagnostics refactor.
#
# Shadows grDevices::pdf with a png() wrapper so that each diagnostic
# "page" becomes a byte-comparable PNG file. Used to confirm that
# refactoring plot_diagnostics does not change the rendered output.
#
# Usage:
#   Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]
#
# Examples:
#   Rscript tools/render_diagnostics_png.R data/plot-refactor-baseline/histsoc mai histsoc
#   Rscript tools/render_diagnostics_png.R data/plot-refactor-baseline/ssp126  mai ssp126 image gfdl-esm4
# ============================================================================

harness_args <- commandArgs(trailingOnly = TRUE)
if (length(harness_args) < 3) {
  stop("Usage: Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]")
}

png_output_dir <- harness_args[1]
scaling_args <- harness_args[-1]
dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

# Make fertilizer_scaling.R see the CLI args it expects (crop, scenario, ...)
commandArgs <- function(trailingOnly = FALSE) {
  if (trailingOnly) scaling_args else c("Rscript", "fertilizer_scaling.R", scaling_args)
}

# Shadow grDevices::pdf. plot_diagnostics calls `pdf(plot_file, width = 16, height = 14)`.
# Our shadow ignores `file`'s directory and writes cairo PNGs into png_output_dir
# using an %03d multi-page filename pattern, with inches converted to pixels at
# a fixed DPI so width/height are preserved.
.harness_png_dpi <- 100
pdf <- function(file, width = 7, height = 7, ...) {
  base <- sub("\\.pdf$", "", basename(file))
  pattern <- file.path(png_output_dir, paste0(base, "-%03d.png"))
  grDevices::png(
    filename = pattern,
    width = round(width * .harness_png_dpi),
    height = round(height * .harness_png_dpi),
    type = "cairo",
    res = .harness_png_dpi
  )
}

# Run the full pipeline. fertilizer_scaling.R sources
# fertilizer_scaling_functions.R, parses commandArgs(), and calls main(...).
source("fertilizer_scaling.R")
