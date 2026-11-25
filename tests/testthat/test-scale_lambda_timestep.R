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

# make_lambda_fixture's grid with cell [1,1] set to a zero base_rate; valid_base uses >= 0 so that cell is admitted.
make_zero_base_fixture <- function() {
  fx <- make_lambda_fixture()
  fx$base_rate[1, 1] <- 0
  fx$valid_base <- is.finite(fx$base_rate) & fx$base_rate >= 0
  fx$lambda <- compute_lambda(fx$base_rate, fx$base_timeseries, fx$valid_base)
  fx
}

test_that("zero base_rate cell with NA ts_t stays NA", {
  fx <- make_zero_base_fixture()
  ts_t <- fx$base_timeseries
  ts_t[1, 1] <- NA
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_true(is.na(out[1, 1]))
})

test_that("zero base_rate cell with negative ts_t is clamped to 0", {
  fx <- make_zero_base_fixture()
  ts_t <- fx$base_timeseries
  ts_t[1, 1] <- -5
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_equal(out[1, 1], 0)
})

test_that("zero base_rate takes precedence over positive base_timeseries", {
  fx <- make_zero_base_fixture()
  fx$base_timeseries[1, 1] <- 4
  fx$lambda <- compute_lambda(fx$base_rate, fx$base_timeseries, fx$valid_base)
  ts_t <- fx$base_timeseries
  ts_t[1, 1] <- 7
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_equal(out[1, 1], 7)
})

test_that("positive-base cell with NA ts_t stays NA", {
  fx <- make_lambda_fixture()
  ts_t <- fx$base_timeseries
  ts_t[2, 2] <- NA
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_true(is.na(out[2, 2]))
})

test_that("vectorized output is bit-identical to per-cell formula", {
  set.seed(42)
  nlon <- 30
  nlat <- 20
  n <- nlon * nlat
  base_rate <- array(sample(c(NA, 0, 1), n, replace = TRUE, prob = c(0.15, 0.15, 0.7)),
                     dim = c(nlon, nlat))
  pos <- !is.na(base_rate) & base_rate == 1
  base_rate[pos] <- runif(sum(pos), 0.5, 100)
  base_timeseries <- array(sample(c(NA, 0, 1), n, replace = TRUE, prob = c(0.15, 0.15, 0.7)),
                           dim = c(nlon, nlat))
  pos_ts <- !is.na(base_timeseries) & base_timeseries == 1
  base_timeseries[pos_ts] <- runif(sum(pos_ts), 0.5, 150)
  ts_t <- array(runif(n, -200, 500), dim = c(nlon, nlat))
  ts_t[sample(n, 40)] <- NA

  valid_base <- is.finite(base_rate) & base_rate >= 0
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)

  # Guard against the random grid silently losing a case.
  expect_gt(sum(is.na(base_rate)), 0)
  expect_gt(sum(base_rate == 0, na.rm = TRUE), 0)
  expect_gt(sum(base_rate > 0, na.rm = TRUE), 0)
  expect_gt(sum(is.na(base_timeseries)), 0)
  expect_gt(sum(base_timeseries == 0, na.rm = TRUE), 0)
  expect_gt(sum(base_timeseries > 0, na.rm = TRUE), 0)
  expect_gt(sum(is.na(ts_t)), 0)
  expect_gt(sum(valid_base & base_rate == 0 & !is.na(ts_t) & ts_t < 0), 0)
  expect_gt(sum(lambda != 1), 0)
  formula_cells <- valid_base & !is.na(base_rate) & base_rate != 0 &
    !is.na(base_timeseries) & base_timeseries > 0
  expect_gt(sum(formula_cells & !is.na(ts_t)), 0)

  expected <- array(NA_real_, dim = c(nlon, nlat))
  for (i in 1:nlon) {
    for (j in 1:nlat) {
      if (valid_base[i, j]) {
        if (base_rate[i, j] == 0) {
          expected[i, j] <- ts_t[i, j]
        } else if (!is.na(base_timeseries[i, j]) && base_timeseries[i, j] > 0) {
          fert_diff <- ts_t[i, j] - base_timeseries[i, j]
          ratio_term <- (base_rate[i, j] / base_timeseries[i, j]) ^ lambda[i, j]
          expected[i, j] <- base_rate[i, j] *
            (1 + (fert_diff / base_rate[i, j]) * ratio_term)
        }
        if (!is.na(expected[i, j]) && expected[i, j] < 0) expected[i, j] <- 0
      }
    }
  }
  expect_gt(sum(expected == 0, na.rm = TRUE), 0)
  expect_gt(sum(is.na(expected) & formula_cells), 0)

  out <- scale_lambda_timestep(base_rate, ts_t, base_timeseries, valid_base, lambda)
  expect_identical(out, expected)
})
