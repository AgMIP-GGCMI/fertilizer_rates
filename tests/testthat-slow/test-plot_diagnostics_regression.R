# PNG regression tests for plot_diagnostics. Each test renders a
# reference scenario through the harness and snapshots every produced
# PNG. testthat compares byte-for-byte against committed baselines and
# writes a .new.png next to any mismatch for review.

# expect_snapshot_file() requires testthat edition 3. This project
# is not an R package, so there's no DESCRIPTION to set
# Config/testthat/edition; enable it per-file instead.
testthat::local_edition(3)

source(
  testthat::test_path("..", "..", "tools", "diagnostics_png_harness.R"),
  chdir = TRUE
)

render_scenario <- function(crop, scenario, iam = NULL, gcm = NULL) {
  tmp <- tempfile(paste0("diagnostics-", scenario, "-"))
  dir.create(tmp, recursive = TRUE)
  withr::with_dir(
    testthat::test_path("..", ".."),
    render_diagnostics_to_png(tmp, crop, scenario, iam, gcm)
  )
  tmp
}

snapshot_all_pngs <- function(tmp_dir) {
  for (png in sort(list.files(tmp_dir, pattern = "\\.png$"))) {
    expect_snapshot_file(file.path(tmp_dir, png), name = png)
  }
}

test_that("plot_diagnostics output is byte-identical for mai histsoc", {
  tmp <- render_scenario("mai", "histsoc")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
})

test_that("plot_diagnostics output is byte-identical for mai ssp126 image gfdl-esm4", {
  tmp <- render_scenario("mai", "ssp126", "image", "gfdl-esm4")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
})
