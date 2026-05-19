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
#
# The function also redirects output_base_path into <png_output_dir>/nc-outputs
# for the duration of the call, so all of main()'s filesystem outputs are
# contained inside png_output_dir.
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

  # Redirect NetCDF outputs into a `nc-outputs/` subdir of png_output_dir so
  # the harness's filesystem footprint is contained. Tests that need to
  # compare against baseline NetCDFs read from this location.
  #
  # The shadow target is environment(main), not globalenv(), because
  # fertilizer_scaling_settings.R defines output_base_path in the same env
  # main() was sourced into -- globalenv under testthat::test_dir, but
  # covr's private env under covr::file_coverage. Assigning to globalenv()
  # under covr would be hidden by the covr-env binding when main() looks
  # output_base_path up lexically, and main() would write to the original
  # FERT_OUTPUT_BASE_PATH instead of the test's tempdir.
  target_env <- environment(main)
  orig_output_base_path <- output_base_path
  nc_dir <- file.path(png_output_dir, "nc-outputs")
  dir.create(nc_dir, showWarnings = FALSE, recursive = TRUE)
  assign("output_base_path", nc_dir, envir = target_env)
  on.exit({
    assign("output_base_path", orig_output_base_path, envir = target_env)
  }, add = TRUE)

  main(crop, scenario, iam = iam, gcm = gcm)
}
