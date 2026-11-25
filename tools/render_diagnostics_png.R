#!/usr/bin/env Rscript
# ============================================================================
# render_diagnostics_png.R
# ============================================================================
# CLI wrapper around render_diagnostics_to_png(). See
# tools/diagnostics_png_harness.R for the shadowing logic.
# Renders with whatever `scaling_methods` the settings file sets (lambda only in
# production). With --both-methods it sets scaling_methods to c("relative", "lambda"),
# the regression test's configuration; without it, the output won't match the test's
# snapshots page for page.
#
# Usage:
#   Rscript tools/render_diagnostics_png.R [--both-methods] <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
both_methods <- "--both-methods" %in% args
args <- args[args != "--both-methods"]
if (length(args) < 3) {
  stop("Usage: Rscript tools/render_diagnostics_png.R [--both-methods] <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]")
}

source("fertilizer_scaling_settings.R")
if (both_methods) scaling_methods <- c("relative", "lambda")
source("fertilizer_scaling_functions.R")
source("tools/diagnostics_png_harness.R")

render_diagnostics_to_png(
  png_output_dir = args[1],
  crop = args[2],
  scenario = args[3],
  iam = if (length(args) >= 4) args[4] else NULL,
  gcm = if (length(args) >= 5) args[5] else NULL
)
