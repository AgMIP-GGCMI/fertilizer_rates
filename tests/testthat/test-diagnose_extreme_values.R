# Tests for diagnose_extreme_values() in fertilizer_scaling_functions.R.

make_scaled_fixture <- function(max_val) {
  scaled_data <- array(10, dim = c(2, 2, 3))
  scaled_data[1, 1, 3] <- max_val
  base_rate <- matrix(c(500, 10, 10, 10), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(1, 1, 1, 1), nrow = 2, ncol = 2)
  timeseries <- array(1, dim = c(2, 2, 3))
  timeseries[1, 1, 3] <- max_val / 500
  list(scaled_data = scaled_data, base_rate = base_rate,
       base_timeseries = base_timeseries, timeseries = timeseries)
}

test_that("returns invisibly and does not alter scaled_data", {
  fx <- make_scaled_fixture(5000)
  before <- fx$scaled_data
  out <- capture.output(
    ret <- diagnose_extreme_values(fx$scaled_data, fx$base_rate,
                                   fx$base_timeseries, fx$timeseries,
                                   start_year = 1998, base_year = 2000)
  )
  expect_null(ret)
  expect_equal(fx$scaled_data, before)
})

test_that("prints warning and cell details when max > 1000", {
  fx <- make_scaled_fixture(5000)
  out <- capture.output(
    diagnose_extreme_values(fx$scaled_data, fx$base_rate,
                            fx$base_timeseries, fx$timeseries,
                            start_year = 1998, base_year = 2000)
  )
  expect_true(any(grepl("WARNING: Maximum scaled value is 5000", out)))
  expect_true(any(grepl("Found 1 cells with values >", out)))
  expect_true(any(grepl("Cell 1 at lon index 1 , lat index 1", out)))
})

test_that("prints nothing when max <= 1000", {
  fx <- make_scaled_fixture(500)  # below threshold
  out <- capture.output(
    diagnose_extreme_values(fx$scaled_data, fx$base_rate,
                            fx$base_timeseries, fx$timeseries,
                            start_year = 1998, base_year = 2000)
  )
  expect_false(any(grepl("WARNING:", out)))
})

test_that("reports at most 5 cells even when more exceed threshold", {
  scaled_data <- array(5000, dim = c(3, 3, 2))  # 9 extreme cells
  base_rate <- matrix(500, nrow = 3, ncol = 3)
  base_timeseries <- matrix(1, nrow = 3, ncol = 3)
  timeseries <- array(10, dim = c(3, 3, 2))
  out <- capture.output(
    diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                            timeseries, start_year = 1998, base_year = 2000)
  )
  expect_true(any(grepl("Found 9 cells", out)))
  expect_true(any(grepl("Cell 5 at lon index", out)))
  expect_false(any(grepl("Cell 6 at lon index", out)))
})

test_that("prints MISMATCH line when base_rate / base_timeseries diverges >0.5", {
  scaled_data <- array(10, dim = c(2, 2, 3))
  scaled_data[1, 1, 3] <- 5000
  base_rate <- matrix(c(500, 10, 10, 10), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(1, 1, 1, 1), nrow = 2, ncol = 2)
  timeseries <- array(1, dim = c(2, 2, 3))
  timeseries[1, 1, 3] <- 10
  out <- capture.output(
    diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                            timeseries, start_year = 1998, base_year = 2000)
  )
  expect_true(any(grepl("MISMATCH: Spatial base / TS base ratio", out)))
})

test_that("omits MISMATCH line when ratio is near 1", {
  scaled_data <- array(10, dim = c(2, 2, 3))
  scaled_data[1, 1, 3] <- 5000
  base_rate <- matrix(c(1, 1, 1, 1), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(1, 1, 1, 1), nrow = 2, ncol = 2)
  timeseries <- array(1, dim = c(2, 2, 3))
  timeseries[1, 1, 3] <- 5000
  out <- capture.output(
    diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                            timeseries, start_year = 1998, base_year = 2000)
  )
  expect_false(any(grepl("MISMATCH", out)))
})

test_that("prints the supplied base year in the cell details", {
  fx <- make_scaled_fixture(5000)
  out <- capture.output(
    diagnose_extreme_values(fx$scaled_data, fx$base_rate,
                            fx$base_timeseries, fx$timeseries,
                            start_year = 1998, base_year = 2020)
  )
  expect_true(any(grepl("Base rate (year 2020 spatial)", out, fixed = TRUE)))
  expect_true(any(grepl("TS at base year (2020)", out, fixed = TRUE)))
  expect_false(any(grepl("(year 2000", out, fixed = TRUE)))
})
