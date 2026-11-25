# Tests for compute_lambda() in fertilizer_scaling_functions.R.

test_that("shape matches base_rate", {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  expect_equal(dim(lambda), c(2, 2))
})

test_that("lambda is sqrt(ts/base) when ts_base < base_rate", {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  expect_equal(lambda[1, 1], sqrt(2 / 10))
  expect_equal(lambda[2, 1], sqrt(4 / 20))
  expect_equal(lambda[1, 2], sqrt(6 / 30))
  expect_equal(lambda[2, 2], sqrt(8 / 40))
})

test_that("lambda is 1 when ts_base >= base_rate", {
  base_rate <- matrix(c(10, 10, 10, 10), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(10, 15, 20, 25), nrow = 2, ncol = 2)
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  expect_true(all(lambda == 1))
})

test_that("lambda is 1 at invalid-base cells", {
  base_rate <- matrix(c(NA, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  expect_equal(lambda[1, 1], 1)
})

test_that("lambda is 1 at zero base_rate cells marked valid", {
  base_rate <- matrix(c(0, 0, 30, 40), nrow = 2)
  base_timeseries <- matrix(c(5, 0, 6, 8), nrow = 2)
  valid_base <- is.finite(base_rate) & base_rate >= 0
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  expect_equal(lambda[1, 1], 1)
  expect_equal(lambda[2, 1], 1)
  expect_equal(lambda[1, 2], sqrt(6 / 30))
  expect_equal(lambda[2, 2], sqrt(8 / 40))
  expect_false(any(is.nan(lambda) | is.infinite(lambda)))
})

test_that("lambda is 1 at cells where base_timeseries is NA or non-positive", {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(NA, 0, -1, 8), nrow = 2, ncol = 2)
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  expect_equal(lambda[1, 1], 1)
  expect_equal(lambda[2, 1], 1)
  expect_equal(lambda[1, 2], 1)
  # [2,2] is valid and ts_base (8) < base_rate (40), so sqrt(8/40):
  expect_equal(lambda[2, 2], sqrt(8 / 40))
})
