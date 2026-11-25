# tests/testthat/test-compare_relative_lambda_tick_orig_zero.R
#
# Covers the "ensure 0 in tick_orig" injection (the `Ensure 0 present` block, inside
# plot_map_comp) by installing a pretty() shadow into
# compare_relative_lambda's enclosing env. The shadow returns ticks
# that omit 0, forcing the !any(abs(tick_orig) < eps) guard to fire.

with_pretty_shadow <- function(shadow, expr, envir = parent.frame()) {
  target_env <- environment(compare_relative_lambda)
  had <- exists("pretty", envir = target_env, inherits = FALSE)
  old <- if (had) get("pretty", envir = target_env, inherits = FALSE) else NULL
  assign("pretty", shadow, envir = target_env)
  withr::defer({
    if (had) {
      assign("pretty", old, envir = target_env)
    } else {
      rm("pretty", envir = target_env)
    }
  }, envir = envir)
  force(expr)
}

test_that("plot_map_comp injects 0 into tick_orig when pretty() omits it", {
  tmp <- withr::local_tempdir()
  local_mocked_globals(output_base_path = tmp)

  # Minimal valid rel + lambda histsoc files so compare_relative_lambda
  # gets past file-existence and lon-sort checks and reaches the
  # diverging+log_scale plot_map_comp call (the `log_scale && max_abs_orig > 0` branch).
  lon <- seq(-179.75, by = 0.5, length.out = 4)
  lat <- seq(-89.75, by = 0.5, length.out = 3)
  rel_dir <- file.path(tmp, "histsoc", "relative")
  lambda_dir <- file.path(tmp, "histsoc", "lambda")
  dir.create(rel_dir, recursive = TRUE)
  dir.create(lambda_dir, recursive = TRUE)
  make_ts_nc(
    file.path(rel_dir, "n-fertilizer_mai_histsoc_relative_annual_1850_2014.nc"),
    var_name = "fertl_mai", lon = lon, lat = lat,
    nyears = 165, start_year = 1850
  )
  # Make lambda differ from rel slightly so diff_2000 has nonzero,
  # finite values and plot_map_comp enters the diverging+log_scale
  # path (the `log_scale && max_abs_orig > 0` branch) rather than the empty-valid-data fallback.
  lambda_data <- array(75, dim = c(length(lon), length(lat), 165))
  make_ts_nc(
    file.path(lambda_dir, "n-fertilizer_mai_histsoc_lambda_annual_1850_2014.nc"),
    var_name = "fertl_mai", lon = lon, lat = lat,
    nyears = 165, start_year = 1850, data = lambda_data
  )

  # Shadow pretty() to return ticks that omit 0. The shadow is only
  # installed for the duration of this test_that block.
  shadow_called <- FALSE
  with_pretty_shadow(
    shadow = function(x, n = 5, ...) {
      shadow_called <<- TRUE
      c(-1, -0.5, 0.5, 1)
    },
    expr = {
      out <- capture.output(
        compare_relative_lambda("mai", "histsoc", output_dir = tmp)
      )
    }
  )

  expect_true(shadow_called)
  expect_true(file.exists(file.path(tmp, "comparison_relative_lambda_mai_histsoc.pdf")))
})
