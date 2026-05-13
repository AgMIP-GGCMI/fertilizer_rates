# tests/testthat/test-compare_relative_lambda_all_na.R
#
# Feeds all-NA rel + lambda NetCDFs to compare_relative_lambda() to
# exercise:
#   - lines 1048-1049 (plot_map_comp empty-valid-data fallback)
#   - lines 1294, 1305, 1316, 1330 (histsoc "insufficient ... data")
#   - line 1345 (future "insufficient middle year data")

make_pair_all_na <- function(root, crop, scenario,
                             iam = NULL, gcm = NULL) {
  if (scenario == "histsoc") {
    rel_subdir <- file.path(root, "histsoc", "relative")
    lambda_subdir <- file.path(root, "histsoc", "lambda")
    nyears <- 165
    start_year <- 1850
    rel_name <- paste0("n-fertilizer_", crop, "_histsoc_relative_annual_1850_2014.nc")
    lambda_name <- paste0("n-fertilizer_", crop, "_histsoc_lambda_annual_1850_2014.nc")
  } else {
    rel_subdir <- file.path(root, paste0(scenario, "soc-adapt"), "relative")
    lambda_subdir <- file.path(root, paste0(scenario, "soc-adapt"), "lambda")
    nyears <- 86
    start_year <- 2015
    rel_name <- paste0("n-fertilizer_", crop, "_", iam, "_", gcm, "_", scenario,
                       "_relative_annual_2015_2100.nc")
    lambda_name <- paste0("n-fertilizer_", crop, "_", iam, "_", gcm, "_", scenario,
                          "_lambda_annual_2015_2100.nc")
  }
  dir.create(rel_subdir, recursive = TRUE, showWarnings = FALSE)
  dir.create(lambda_subdir, recursive = TRUE, showWarnings = FALSE)

  lon <- seq(-179.75, by = 0.5, length.out = 4)
  lat <- seq(-89.75, by = 0.5, length.out = 3)
  na_arr <- array(NA_real_, dim = c(length(lon), length(lat), nyears))

  make_ts_nc(file.path(rel_subdir, rel_name),
             var_name = paste0("fertl_", crop),
             lon = lon, lat = lat, nyears = nyears,
             start_year = start_year, data = na_arr)
  make_ts_nc(file.path(lambda_subdir, lambda_name),
             var_name = paste0("fertl_", crop),
             lon = lon, lat = lat, nyears = nyears,
             start_year = start_year, data = na_arr)
  invisible(NULL)
}

test_that("compare_relative_lambda handles all-NA histsoc input", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)
  make_pair_all_na(tmp, "mai", "histsoc")
  out <- capture.output(
    compare_relative_lambda("mai", "histsoc", output_dir = tmp)
  )
  pdf_path <- file.path(tmp, "comparison_relative_lambda_mai_histsoc.pdf")
  expect_true(file.exists(pdf_path))
  # No "ERROR IN compare_relative_lambda" — the tryCatch handler must
  # not have fired (that branch is intentionally not exercised here).
  expect_false(any(grepl("ERROR IN compare_relative_lambda", out)))
})

test_that("compare_relative_lambda handles all-NA future-scenario input", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)
  make_pair_all_na(tmp, "mai", "ssp126", iam = "image", gcm = "gfdl-esm4")
  out <- capture.output(
    compare_relative_lambda("mai", "ssp126", iam = "image", gcm = "gfdl-esm4",
                            output_dir = tmp)
  )
  pdf_path <- file.path(tmp,
    "comparison_relative_lambda_mai_ssp126_image_gfdl-esm4.pdf")
  expect_true(file.exists(pdf_path))
  expect_false(any(grepl("ERROR IN compare_relative_lambda", out)))
})
