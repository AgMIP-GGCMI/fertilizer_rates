# ============================================================================
# diagnostics_png_harness.R
# ============================================================================
# Pure function library for the PNG verification harness. Defines
# render_diagnostics_to_png() without side effects at source time, so it
# can be sourced from both the tools/render_diagnostics_png.R CLI wrapper
# and from the testthat regression test.
#
# The function shadows grDevices::pdf with a cairo-backed png() so each
# diagnostic "page" becomes a byte-comparable PNG, then invokes main()
# directly. Callers must have already sourced fertilizer_scaling_settings.R
# and fertilizer_scaling_functions.R into globalenv() (testthat setup.R and
# render_diagnostics_png.R both do this).
#
# Cairo + renv-pinned R + pinned Debian cairo/png packages make output
# byte-identical inside the devcontainer.
# ============================================================================

.HARNESS_PNG_DPI <- 100

render_diagnostics_to_png <- function(png_output_dir, crop, scenario,
                                      iam = NULL, gcm = NULL) {
  dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

  # The pdf shadow must live in globalenv() because plot_diagnostics's
  # unqualified `pdf(...)` call is looked up via its definition environment
  # (globalenv, since fertilizer_scaling_functions.R is sourced there). A
  # `local({...})` wrapper would be invisible to the lookup. The shadow is
  # a closure over png_output_dir; the assignment into globalenv is
  # load-bearing, but the closure itself captures from this function's frame.
  #
  # This function is NOT reentrant. Do not call it recursively or from
  # parallel tests in the same R session — the on.exit cleanup rm()s the
  # globalenv shadow, which would remove an outer call's shadow partway
  # through its main() invocation.
  on.exit({
    if (exists("pdf", envir = globalenv(), inherits = FALSE)) {
      rm("pdf", envir = globalenv())
    }
  }, add = TRUE)

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

  main(crop, scenario, iam = iam, gcm = gcm)
}
