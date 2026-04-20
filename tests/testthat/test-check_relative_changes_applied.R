# Tests for check_relative_changes_applied() in fertilizer_scaling_functions.R.

# Helper to build a fixture where all cells have a full valid time series.
.make_full_fixture <- function(ntime = 12) {
  nlon <- 3
  nlat <- 3
  base_rate <- matrix(
    seq(10, 10 + (nlon * nlat - 1) * 5, length.out = nlon * nlat),
    nrow = nlon, ncol = nlat
  )
  timeseries <- array(NA_real_, dim = c(nlon, nlat, ntime))
  for (i in 1:nlon) for (j in 1:nlat) {
    timeseries[i, j, ] <- seq(1, 10, length.out = ntime) + (i - 1) * 0.3 + (j - 1) * 0.1
  }
  base_idx <- 6
  scaled_data <- array(NA_real_, dim = c(nlon, nlat, ntime))
  for (t in 1:ntime) {
    scaled_data[, , t] <- base_rate * (timeseries[, , t] / timeseries[, , base_idx])
  }
  list(scaled_data = scaled_data, timeseries = timeseries,
       base_rate = base_rate, base_idx = base_idx)
}

test_that("returns a list with found and checks", {
  fx <- .make_full_fixture()
  out <- check_relative_changes_applied(fx$scaled_data, fx$timeseries,
                                        fx$base_rate, fx$base_idx)
  expect_named(out, c("found", "checks"))
})

test_that("found=TRUE and checks contain expected/actual pairs on good fixture", {
  fx <- .make_full_fixture()
  out <- check_relative_changes_applied(fx$scaled_data, fx$timeseries,
                                        fx$base_rate, fx$base_idx)
  expect_true(out$found)
  expect_gt(length(out$checks), 0)
  # Every check's expected matches actual within numerical precision.
  for (check in out$checks) {
    expect_equal(check$actual, check$expected, tolerance = 1e-5)
    expect_true(is.numeric(check$t))
  }
})

test_that("found=FALSE when no cell has a full valid time series", {
  fx <- .make_full_fixture()
  # Break every cell by setting one NA in each cell's time series
  fx$timeseries[, , 1] <- NA_real_
  out <- check_relative_changes_applied(fx$scaled_data, fx$timeseries,
                                        fx$base_rate, fx$base_idx)
  expect_false(out$found)
  expect_equal(length(out$checks), 0)
})

test_that("found=FALSE when base_rate is all NA", {
  fx <- .make_full_fixture()
  fx$base_rate[, ] <- NA
  out <- check_relative_changes_applied(fx$scaled_data, fx$timeseries,
                                        fx$base_rate, fx$base_idx)
  expect_false(out$found)
})

test_that("detects incorrect scaling: actual != expected", {
  fx <- .make_full_fixture()
  fx$scaled_data <- fx$scaled_data * 2  # double everything
  out <- check_relative_changes_applied(fx$scaled_data, fx$timeseries,
                                        fx$base_rate, fx$base_idx)
  expect_true(out$found)
  # At least one check pair should differ substantially
  any_mismatch <- any(vapply(out$checks, function(check) {
    abs(check$actual - check$expected) > 1e-3
  }, logical(1)))
  expect_true(any_mismatch)
})
