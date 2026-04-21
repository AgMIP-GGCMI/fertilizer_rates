# ============================================================================
# diagnostics_png_harness.R
# ============================================================================
# Pure function library for the PNG verification harness. Defines
# render_diagnostics_to_png() without side effects at source time, so it
# can be sourced from both the tools/render_diagnostics_png.R CLI wrapper
# and from the testthat regression test.
#
# The function shadows grDevices::pdf with a cairo-backed png() so each
# diagnostic "page" becomes a byte-comparable PNG. Cairo + renv-pinned R +
# pinned Debian cairo/png packages make output byte-identical inside the
# devcontainer.
# ============================================================================

.HARNESS_PNG_DPI <- 100

render_diagnostics_to_png <- function(png_output_dir, crop, scenario,
                                      iam = NULL, gcm = NULL) {
  dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

  scaling_args <- c(crop, scenario, iam, gcm)

  # The shadows must live in globalenv() because `source()` evaluates
  # fertilizer_scaling.R in globalenv, and plot_diagnostics's
  # unqualified `pdf(...)` call is looked up via its definition
  # environment (also globalenv). A `local({...})` wrapper is invisible
  # to both lookups. The shadows are closures over png_output_dir and
  # scaling_args; the assignment location does not affect scope
  # resolution.
  on.exit({
    if (exists("commandArgs", envir = globalenv(), inherits = FALSE)) {
      rm("commandArgs", envir = globalenv())
    }
    if (exists("pdf", envir = globalenv(), inherits = FALSE)) {
      rm("pdf", envir = globalenv())
    }
  }, add = TRUE)

  assign("commandArgs",
    function(trailingOnly = FALSE) {
      if (trailingOnly) scaling_args else c("Rscript", "fertilizer_scaling.R", scaling_args)
    },
    envir = globalenv())

  assign("pdf",
    function(file, width = 7, height = 7, ...) {
      base <- sub("\\.pdf$", "", basename(file))
      pattern <- file.path(png_output_dir, paste0(base, "-%03d.png"))
      grDevices::png(filename = pattern,
                     width = round(width * .HARNESS_PNG_DPI),
                     height = round(height * .HARNESS_PNG_DPI),
                     type = "cairo",
                     res = .HARNESS_PNG_DPI)
    },
    envir = globalenv())

  source("fertilizer_scaling.R")
}
