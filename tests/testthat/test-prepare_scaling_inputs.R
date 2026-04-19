# Tests for prepare_scaling_inputs() in fertilizer_scaling_functions.R.

make_inputs_fixture <- function() {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  ts <- array(NA_real_, dim = c(2, 2, 3))
  ts[, , 1] <- matrix(c(1, 2, 3, 4), nrow = 2)
  ts[, , 2] <- matrix(c(2, 4, 6, 8), nrow = 2)
  ts[, , 3] <- matrix(c(4, 8, 12, 16), nrow = 2)
  list(base_rate = base_rate, timeseries = ts,
       start_year = 1998, end_year = 2000, base_year = 1999)
}

test_that("returns a list with base_idx, base_timeseries, valid_base", {
  fx <- make_inputs_fixture()
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_named(out, c("base_idx", "base_timeseries", "valid_base"))
})

test_that("base_idx is base_year - start_year + 1", {
  fx <- make_inputs_fixture()
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_equal(out$base_idx, 2)
})

test_that("base_timeseries is the [,,base_idx] slice of timeseries", {
  fx <- make_inputs_fixture()
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_equal(out$base_timeseries, fx$timeseries[, , 2])
})

test_that("valid_base is TRUE for finite, positive, non-NA cells", {
  fx <- make_inputs_fixture()
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_true(all(out$valid_base))
})

test_that("valid_base is FALSE for NA base_rate cells", {
  fx <- make_inputs_fixture()
  fx$base_rate[1, 1] <- NA
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_false(out$valid_base[1, 1])
  expect_true(out$valid_base[2, 1])
})

test_that("valid_base is FALSE for non-finite base_rate cells", {
  fx <- make_inputs_fixture()
  fx$base_rate[1, 1] <- Inf
  fx$base_rate[2, 1] <- -Inf
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_false(out$valid_base[1, 1])
  expect_false(out$valid_base[2, 1])
})

test_that("valid_base is FALSE for zero or negative base_rate cells", {
  fx <- make_inputs_fixture()
  fx$base_rate[1, 1] <- 0
  fx$base_rate[2, 1] <- -5
  out <- prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                                fx$base_year, fx$start_year, fx$end_year)
  expect_false(out$valid_base[1, 1])
  expect_false(out$valid_base[2, 1])
})

test_that("base_year below start_year raises out-of-range error", {
  fx <- make_inputs_fixture()
  expect_error(
    prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                           base_year = 1997, fx$start_year, fx$end_year),
    "is outside the time series range"
  )
})

test_that("base_year above end_year raises out-of-range error", {
  fx <- make_inputs_fixture()
  expect_error(
    prepare_scaling_inputs(fx$base_rate, fx$timeseries,
                           base_year = 2001, fx$start_year, fx$end_year),
    "is outside the time series range"
  )
})
