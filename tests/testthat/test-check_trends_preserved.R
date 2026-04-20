# Tests for check_trends_preserved() in fertilizer_scaling_functions.R.

# Helper: build a [nlon, nlat, ntime] array where every cell's trend equals
# the given generator applied to t.
.fill_cells <- function(nlon, nlat, ntime, f = function(i, j, t) t) {
  a <- array(NA_real_, dim = c(nlon, nlat, ntime))
  for (i in 1:nlon) for (j in 1:nlat) a[i, j, ] <- f(i, j, 1:ntime)
  a
}

test_that("returns a list with n_sampled and median_correlation", {
  ts <- .fill_cells(3, 3, 12)
  scaled <- .fill_cells(3, 3, 12)
  out <- check_trends_preserved(scaled, ts)
  expect_named(out, c("n_sampled", "median_correlation"))
})

test_that("perfect match yields median_correlation very near 1", {
  ts <- .fill_cells(3, 3, 12)
  scaled <- ts  # exact copy
  out <- check_trends_preserved(scaled, ts)
  expect_gt(out$n_sampled, 0)
  expect_equal(out$median_correlation, 1, tolerance = 1e-12)
})

test_that("no valid samples when ntime <= 10", {
  ts <- .fill_cells(3, 3, 5)
  scaled <- ts
  out <- check_trends_preserved(scaled, ts)
  expect_equal(out$n_sampled, 0)
  expect_true(is.na(out$median_correlation))
})

test_that("constant scaled with varying ts yields sd(scaled) == 0, sample skipped", {
  # No cell will be counted because sd(ts_scaled[valid]) == 0 at every cell.
  ts <- .fill_cells(3, 3, 12, function(i, j, t) t + i * 0.1)
  scaled <- .fill_cells(3, 3, 12, function(i, j, t) rep(5, length(t)))
  out <- check_trends_preserved(scaled, ts)
  expect_equal(out$n_sampled, 0)
  expect_true(is.na(out$median_correlation))
})

test_that("respects n_samples early-exit", {
  ts <- .fill_cells(3, 3, 12)
  scaled <- ts
  out <- check_trends_preserved(scaled, ts, n_samples = 3)
  expect_lte(out$n_sampled, 3)
})
