# Tests for scale_lambda_timestep() in fertilizer_scaling_functions.R.

make_lambda_fixture <- function() {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  list(base_rate = base_rate, base_timeseries = base_timeseries,
       valid_base = valid_base, lambda = lambda)
}

test_that("scaled slice has same shape as base_rate", {
  fx <- make_lambda_fixture()
  ts_t <- fx$base_timeseries
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_equal(dim(out), dim(fx$base_rate))
})

test_that("at the base time step (fert_diff = 0), output equals base_rate", {
  fx <- make_lambda_fixture()
  ts_t <- fx$base_timeseries
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_equal(out, fx$base_rate)
})

test_that("when ts_base == base_rate (lambda = 1), output equals ts_t", {
  # lambda = 1 and base/ts_base = 1 → scaled = ts_t.
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- base_rate
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  lambda <- matrix(1, nrow = 2, ncol = 2)
  ts_t <- matrix(c(12, 25, 35, 45), nrow = 2)
  out <- scale_lambda_timestep(base_rate, ts_t, base_timeseries,
                               valid_base, lambda)
  expect_equal(out, ts_t)
})

test_that("output is clamped to non-negative", {
  base_rate <- matrix(10, nrow = 1, ncol = 1)
  base_timeseries <- matrix(2, nrow = 1, ncol = 1)
  valid_base <- matrix(TRUE, nrow = 1, ncol = 1)
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  ts_t <- matrix(-50, nrow = 1, ncol = 1)
  out <- scale_lambda_timestep(base_rate, ts_t, base_timeseries,
                               valid_base, lambda)
  expect_equal(out[1, 1], 0)
})

test_that("invalid base_rate cells remain NA", {
  fx <- make_lambda_fixture()
  fx$base_rate[1, 1] <- NA
  fx$valid_base <- !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate > 0
  ts_t <- fx$base_timeseries
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_true(is.na(out[1, 1]))
})

test_that("invalid base_timeseries cells remain NA", {
  fx <- make_lambda_fixture()
  fx$base_timeseries[1, 1] <- NA
  fx$base_timeseries[2, 1] <- 0
  ts_t <- matrix(c(1, 2, 3, 4), nrow = 2)
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_true(is.na(out[1, 1]))
  expect_true(is.na(out[2, 1]))
})

test_that("zero base_rate cells copy raw timeseries values in lambda method", {
  base_rate <- matrix(c(0, 20, 30, 40), nrow = 2)
  base_timeseries <- matrix(c(0, 4, 6, 8), nrow = 2)
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate >= 0
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  ts_t <- matrix(c(7, 5, 9, 11), nrow = 2)

  out <- scale_lambda_timestep(base_rate, ts_t, base_timeseries,
                               valid_base, lambda)

  expect_equal(out[1, 1], ts_t[1, 1])
  expect_true(!is.na(out[1, 1]))
})

test_that("internal error re-throws as a lambda_timestep_error with i/j/nlon/nlat", {
  # Provide a lambda array with wrong dims to force an error inside the loop.
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  bad_lambda <- matrix(1, nrow = 1, ncol = 1)  # wrong shape
  ts_t <- base_timeseries
  cond <- tryCatch(
    scale_lambda_timestep(base_rate, ts_t, base_timeseries, valid_base, bad_lambda),
    lambda_timestep_error = function(e) e
  )
  expect_s3_class(cond, "lambda_timestep_error")
  expect_true(!is.null(cond$i))
  expect_true(!is.null(cond$j))
  expect_equal(cond$nlon, 2)
  expect_equal(cond$nlat, 2)
  expect_s3_class(cond$original, "error")
})
