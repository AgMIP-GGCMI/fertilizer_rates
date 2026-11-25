# PNG regression tests for plot_diagnostics. Each test renders a
# reference scenario through the harness and snapshots every produced
# PNG. testthat compares byte-for-byte against committed baselines and
# writes a .new.png next to any mismatch for review. The renders run with both
# scaling methods enabled (see render_scenario()).

# expect_snapshot_file() requires testthat edition 3. This project
# is not an R package, so there's no DESCRIPTION to set
# Config/testthat/edition; enable it per-file instead.
testthat::local_edition(3)

source(
  testthat::test_path("..", "..", "tools", "diagnostics_png_harness.R"),
  chdir = TRUE
)

# Use the "..", "testthat-slow" cancellation trick (same as the harness
# source above) so the path resolves to tests/testthat-slow/baselines under
# both testthat::test_dir (where test_path() defaults to tests/testthat-slow)
# and covr::file_coverage (where it defaults to tests/testthat).
baseline_dir <- testthat::test_path("..", "testthat-slow", "baselines")

render_scenario <- function(crop, scenario, iam = NULL, gcm = NULL) {
  tmp <- tempfile(paste0("diagnostics-", scenario, "-"))
  dir.create(tmp, recursive = TRUE)
  # Production runs the lambda method only; the test enables both so the
  # relative method and compare_relative_lambda() stay covered end to end.
  # Restored when render_scenario() returns.
  local_mocked_globals(scaling_methods = c("relative", "lambda"))
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

read_first_3_years <- function(path, var_name) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  list(
    data = ncdf4::ncvar_get(nc, var_name,
                            start = c(1, 1, 1), count = c(-1, -1, 3)),
    lon  = ncdf4::ncvar_get(nc, "lon"),
    lat  = ncdf4::ncvar_get(nc, "lat"),
    time = ncdf4::ncvar_get(nc, "time")[1:3]
  )
}

expect_ssp126_mai_baselines <- function(tmp) {
  for (method in c("relative", "lambda")) {
    produced_path <- file.path(
      tmp, "nc-outputs", "ssp126soc-adapt", method,
      sprintf("n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2100.nc", method)
    )
    baseline_path <- file.path(
      baseline_dir,
      sprintf("n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", method)
    )
    expect_true(file.exists(produced_path),
                label = sprintf("main() produced %s output", method))
    obs <- read_first_3_years(produced_path, "fertl_mai")
    exp <- read_first_3_years(baseline_path, "fertl_mai")
    expect_equal(obs$data, exp$data, tolerance = 0,
                 label = sprintf("first 3 years of %s data", method))
    expect_equal(obs$lon,  exp$lon,  tolerance = 0,
                 label = sprintf("%s lon coords", method))
    expect_equal(obs$lat,  exp$lat,  tolerance = 0,
                 label = sprintf("%s lat coords", method))
    expect_equal(obs$time, exp$time, tolerance = 0,
                 label = sprintf("%s time coords (first 3)", method))
  }
}

test_that("plot_diagnostics output is byte-identical for mai histsoc", {
  tmp <- render_scenario("mai", "histsoc")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
})

test_that("plot_diagnostics + NetCDF outputs match baselines for mai ssp126 image gfdl-esm4", {
  methods_before <- scaling_methods
  tmp <- render_scenario("mai", "ssp126", "image", "gfdl-esm4")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  expect_identical(scaling_methods, methods_before)
  snapshot_all_pngs(tmp)
  expect_ssp126_mai_baselines(tmp)
})
