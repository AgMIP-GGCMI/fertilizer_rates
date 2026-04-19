# Tests for scale_relative_timestep() in fertilizer_scaling_functions.R.

make_slice_fixture <- function() {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
  list(base_rate = base_rate, base_timeseries = base_timeseries,
       valid_base = valid_base)
}

test_that("scaled slice has same shape as base_rate", {
  fx <- make_slice_fixture()
  ts_t <- matrix(c(1, 2, 3, 4), nrow = 2)
  out <- scale_relative_timestep(fx$base_rate, ts_t,
                                 fx$base_timeseries, fx$valid_base)
  expect_equal(dim(out), dim(fx$base_rate))
})

test_that("known inputs produce known outputs", {
  fx <- make_slice_fixture()
  ts_t <- matrix(c(4, 8, 12, 16), nrow = 2)
  out <- scale_relative_timestep(fx$base_rate, ts_t,
                                 fx$base_timeseries, fx$valid_base)
  # scaled = base * (ts_t / base_timeseries) = base * 2 everywhere
  expect_equal(out, fx$base_rate * 2)
})

test_that("invalid base_rate cells remain NA", {
  fx <- make_slice_fixture()
  fx$base_rate[1, 1] <- NA
  fx$valid_base <- !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate > 0
  ts_t <- matrix(c(1, 2, 3, 4), nrow = 2)
  out <- scale_relative_timestep(fx$base_rate, ts_t,
                                 fx$base_timeseries, fx$valid_base)
  expect_true(is.na(out[1, 1]))
})

test_that("invalid base_timeseries cells default rel_change to 1", {
  fx <- make_slice_fixture()
  fx$base_timeseries[1, 1] <- NA
  fx$base_timeseries[2, 1] <- 0
  ts_t <- matrix(c(100, 200, 3, 4), nrow = 2)
  out <- scale_relative_timestep(fx$base_rate, ts_t,
                                 fx$base_timeseries, fx$valid_base)
  # rel_change = 1 at [1,1] and [2,1], so scaled == base_rate there.
  expect_equal(out[1, 1], fx$base_rate[1, 1])
  expect_equal(out[2, 1], fx$base_rate[2, 1])
})

test_that("NA in ts_t at valid-everything cell yields NA in output", {
  fx <- make_slice_fixture()
  ts_t <- matrix(c(NA, 2, 3, 4), nrow = 2)
  out <- scale_relative_timestep(fx$base_rate, ts_t,
                                 fx$base_timeseries, fx$valid_base)
  expect_true(is.na(out[1, 1]))
  expect_equal(out[2, 1], fx$base_rate[2, 1] * (2 / fx$base_timeseries[2, 1]))
})
