# Tests for scale_with_timeseries() in fertilizer_scaling_functions.R.
#
# These tests run against the current implementation to lock down behavior
# before the modularization refactor. Fixtures are small (2x2x3) so every
# expected value can be hand-computed.

make_harness_fixture <- function() {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  ts <- array(NA_real_, dim = c(2, 2, 3))
  ts[, , 1] <- matrix(c(1, 2, 3, 4), nrow = 2)
  ts[, , 2] <- matrix(c(2, 4, 6, 8), nrow = 2)
  ts[, , 3] <- matrix(c(4, 8, 12, 16), nrow = 2)
  list(
    base_rate  = base_rate,
    timeseries = ts,
    start_year = 1998,
    end_year   = 2000,
    base_year  = 1999
  )
}

# ---- Dispatch and shape ----------------------------------------------------

test_that("relative method returns an array with shape [nlon, nlat, ntimes]", {
  fx <- make_harness_fixture()
  out <- suppressMessages(capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  ))
  expect_equal(dim(result), c(2, 2, 3))
})

test_that("lambda method returns an array with shape [nlon, nlat, ntimes]", {
  fx <- make_harness_fixture()
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  expect_equal(dim(result), c(2, 2, 3))
})

test_that("unknown method raises 'Unknown scaling method'", {
  fx <- make_harness_fixture()
  expect_error(
    capture.output(
      scale_with_timeseries(fx$base_rate, fx$timeseries,
                            fx$base_year, fx$start_year, fx$end_year,
                            method = "bogus")
    ),
    "Unknown scaling method: bogus"
  )
})

# ---- base_year validation --------------------------------------------------

test_that("base_year below start_year raises out-of-range error", {
  fx <- make_harness_fixture()
  expect_error(
    capture.output(
      scale_with_timeseries(fx$base_rate, fx$timeseries,
                            base_year = 1997,
                            fx$start_year, fx$end_year, method = "relative")
    ),
    "is outside the time series range"
  )
})

test_that("base_year above end_year raises out-of-range error", {
  fx <- make_harness_fixture()
  expect_error(
    capture.output(
      scale_with_timeseries(fx$base_rate, fx$timeseries,
                            base_year = 2001,
                            fx$start_year, fx$end_year, method = "relative")
    ),
    "is outside the time series range"
  )
})

# ---- Relative semantics ---------------------------------------------------

test_that("relative: base-year slice equals base_rate at valid cells", {
  fx <- make_harness_fixture()
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_equal(result[, , 2], fx$base_rate)
})

test_that("relative: scaled[t] == base_rate * ts[t] / ts[base] at sampled cells", {
  fx <- make_harness_fixture()
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  # Hand-computed expectations.
  expect_equal(result[1, 1, 1], 5)
  expect_equal(result[1, 1, 3], 20)
  expect_equal(result[2, 1, 1], 10)
  expect_equal(result[1, 2, 3], 60)
  expect_equal(result[2, 2, 3], 80)
})

test_that("relative: NA base_rate yields NA in output at every time step", {
  fx <- make_harness_fixture()
  fx$base_rate[1, 1] <- NA
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_true(all(is.na(result[1, 1, ])))
})

test_that("relative: non-finite base_rate yields NA in output", {
  fx <- make_harness_fixture()
  fx$base_rate[1, 1] <- Inf
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_true(all(is.na(result[1, 1, ])))
})

test_that("relative: zero or negative base_rate yields NA in output", {
  fx <- make_harness_fixture()
  fx$base_rate[1, 1] <- 0
  fx$base_rate[2, 1] <- -5
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_true(all(is.na(result[1, 1, ])))
  expect_true(all(is.na(result[2, 1, ])))
})

test_that("relative: valid base_rate + invalid ts_base yields base_rate at every t", {
  fx <- make_harness_fixture()
  fx$timeseries[1, 1, 2] <- NA   # invalid ts_base at [1,1]
  fx$timeseries[2, 1, 2] <- 0    # invalid ts_base at [2,1]
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_equal(result[1, 1, ], rep(fx$base_rate[1, 1], 3))
  expect_equal(result[2, 1, ], rep(fx$base_rate[2, 1], 3))
})

test_that("relative: NA ts[t] at valid-everything cell yields NA at that t", {
  fx <- make_harness_fixture()
  fx$timeseries[1, 1, 3] <- NA
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_true(is.na(result[1, 1, 3]))
  expect_false(is.na(result[1, 1, 1]))
  expect_false(is.na(result[1, 1, 2]))
})

# ---- Lambda semantics -----------------------------------------------------

test_that("lambda: output is clamped to non-negative values", {
  fx <- make_harness_fixture()
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  expect_true(all(result >= 0 | is.na(result)))
})

test_that("lambda: base-year slice at cells where ts_base == base_rate equals base_rate", {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  ts <- array(NA_real_, dim = c(2, 2, 3))
  ts[, , 1] <- matrix(c(5, 15, 25, 35), nrow = 2)
  ts[, , 2] <- base_rate
  ts[, , 3] <- matrix(c(12, 22, 32, 42), nrow = 2)
  capture.output(
    result <- scale_with_timeseries(base_rate, ts,
                                    base_year = 1999,
                                    start_year = 1998, end_year = 2000,
                                    method = "lambda")
  )
  expect_equal(result[, , 2], base_rate)
})

test_that("lambda: when ts_base == base_rate, scaled[t] equals ts[t] at that cell", {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  ts <- array(NA_real_, dim = c(2, 2, 3))
  ts[, , 1] <- matrix(c(5, 15, 25, 35), nrow = 2)
  ts[, , 2] <- base_rate
  ts[, , 3] <- matrix(c(12, 22, 32, 42), nrow = 2)
  capture.output(
    result <- scale_with_timeseries(base_rate, ts,
                                    base_year = 1999,
                                    start_year = 1998, end_year = 2000,
                                    method = "lambda")
  )
  expect_equal(result[, , 1], ts[, , 1])
  expect_equal(result[, , 3], ts[, , 3])
})

test_that("lambda: NA base_rate yields NA in output", {
  fx <- make_harness_fixture()
  fx$base_rate[1, 1] <- NA
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  expect_true(all(is.na(result[1, 1, ])))
})

# ---- Diagnostics ----------------------------------------------------------

test_that("diagnostic warning fires when max scaled value exceeds 1000", {
  base_rate <- matrix(c(500, 10, 10, 10), nrow = 2, ncol = 2)
  ts <- array(NA_real_, dim = c(2, 2, 3))
  ts[, , 1] <- matrix(c(1, 1, 1, 1), nrow = 2)
  ts[, , 2] <- matrix(c(1, 1, 1, 1), nrow = 2)  # base year
  ts[, , 3] <- matrix(c(10, 1, 1, 1), nrow = 2) # scaled[1,1,3] = 500 * 10 = 5000
  out <- capture.output(
    result <- scale_with_timeseries(base_rate, ts,
                                    base_year = 1999,
                                    start_year = 1998, end_year = 2000,
                                    method = "relative")
  )
  expect_true(any(grepl("WARNING: Maximum scaled value", out)))
  expect_true(any(grepl("Found .* cells with values >", out)))
  expect_equal(dim(result), c(2, 2, 3))
  expect_equal(result[1, 1, 3], 5000)
})

test_that("no diagnostic warning when max scaled value is under 1000", {
  fx <- make_harness_fixture()
  out <- capture.output(
    scale_with_timeseries(fx$base_rate, fx$timeseries,
                          fx$base_year, fx$start_year, fx$end_year,
                          method = "relative")
  )
  expect_false(any(grepl("WARNING: Maximum scaled value", out)))
})
