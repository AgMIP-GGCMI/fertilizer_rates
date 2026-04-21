#!/usr/bin/env Rscript
# ============================================================================
# render_diagnostics_png.R
# ============================================================================
# CLI wrapper around render_diagnostics_to_png(). See
# tools/diagnostics_png_harness.R for the shadowing logic.
#
# Usage:
#   Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]")
}

source("tools/diagnostics_png_harness.R")
render_diagnostics_to_png(
  png_output_dir = args[1],
  crop = args[2],
  scenario = args[3],
  iam = if (length(args) >= 4) args[4] else NULL,
  gcm = if (length(args) >= 5) args[5] else NULL
)
