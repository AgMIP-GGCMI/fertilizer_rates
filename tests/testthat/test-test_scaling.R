# Tests for test_scaling() in fertilizer_scaling_functions.R.
#
# These tests run against the current implementation to lock down behavior
# before modularization. They use testthat::ListReporter + with_reporter()
# to inspect inner test_that outcomes without letting that output pollute
# the outer runner.

# -----------------------------------------------------------------------------
# Fixture
# -----------------------------------------------------------------------------

# 3x3x12 grid where every cell is valid and every invariant holds by
# construction (scaled = base_rate * ts / ts_base). ntime=12 so cells have
# > 10 valid time points, which the trends-preserved sampler requires.
make_test_scaling_fixture <- function(ntime = 12) {
  nlon <- 3
  nlat <- 3
  base_rate <- matrix(
    seq(10, 10 + (nlon * nlat - 1) * 5, length.out = nlon * nlat),
    nrow = nlon, ncol = nlat
  )
  timeseries <- array(NA_real_, dim = c(nlon, nlat, ntime))
  for (i in 1:nlon) {
    for (j in 1:nlat) {
      # Each cell grows linearly with a small per-cell offset so trends differ.
      timeseries[i, j, ] <- seq(1, 10, length.out = ntime) + (i - 1) * 0.3 + (j - 1) * 0.1
    }
  }
  start_year <- 2000
  base_year  <- 2005   # base_idx = 6
  base_idx   <- base_year - start_year + 1
  scaled_data <- array(NA_real_, dim = c(nlon, nlat, ntime))
  for (t in 1:ntime) {
    scaled_data[, , t] <- base_rate * (timeseries[, , t] / timeseries[, , base_idx])
  }
  list(
    scaled_data = scaled_data,
    timeseries  = timeseries,
    base_rate   = base_rate,
    start_year  = start_year,
    base_year   = base_year
  )
}

# -----------------------------------------------------------------------------
# Capture helper
# -----------------------------------------------------------------------------

# Runs test_scaling() with a ListReporter so inner test_that outcomes are
# recorded structurally, and captures cat() output to stdout. Returns:
#   list(output, n_tests, n_failures, n_warnings, warnings, results,
#        failures_by_block)
# - output:           character vector of captured stdout lines
# - n_tests:          count of inner test_that blocks that ran
# - n_failures:       count of test_that blocks containing at least one failure
# - n_warnings:       count of warnings raised during the run
# - warnings:         vector of captured warning messages
# - results:          the raw reporter$get_results() list (for deeper inspection)
# - failures_by_block: named logical vector (one entry per inner test_that block,
#                      keyed by block title, TRUE if that block had any failures)
#
# If the exact method name on ListReporter differs in this testthat version
# (it's been stable in testthat 3.x), adjust the two `reporter$...` calls
# below and keep this helper's return shape unchanged.
run_test_scaling_capture <- function(...) {
  reporter <- testthat::ListReporter$new()
  warnings <- character()
  output <- withCallingHandlers(
    capture.output({
      testthat::with_reporter(reporter, {
        # start_file() must be called so that ListReporter$start_test() finds a
        # non-empty current_file key; with_reporter() alone does not call it.
        reporter$start_file("inner")
        test_scaling(...)
      })
    }),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  results <- reporter$get_results()
  n_tests <- length(results)
  n_failures <- sum(vapply(results, function(r) {
    any(vapply(r$results, function(e) inherits(e, "expectation_failure"),
               logical(1)))
  }, logical(1)))
  # Merge expectation_warning objects from testthat's reporter into our warnings
  exp_warnings <- character()
  for (res in results) {
    for (expct in res$results) {
      if (inherits(expct, "expectation_warning")) {
        exp_warnings <- c(exp_warnings, conditionMessage(expct))
      }
    }
  }
  warnings <- c(warnings, exp_warnings)
  failures_by_block <- vapply(results, function(res) {
    any(vapply(res$results, function(e) inherits(e, "expectation_failure"),
               logical(1)))
  }, logical(1))
  names(failures_by_block) <- vapply(results, function(res) res$test,
                                     character(1))
  list(
    output           = output,
    n_tests          = n_tests,
    n_failures       = n_failures,
    n_warnings       = length(warnings),
    warnings         = warnings,
    results          = results,
    failures_by_block = failures_by_block
  )
}

# Convenience: did any inner test_that block whose title matches `regex` fail?
# Returns FALSE if no block matches the regex at all.
block_failed <- function(r, regex) {
  match <- grepl(regex, names(r$failures_by_block))
  if (!any(match)) return(FALSE)
  any(r$failures_by_block[match])
}

# -----------------------------------------------------------------------------
# Method dispatch
# -----------------------------------------------------------------------------

test_that("relative method fires 4 inner test_that blocks and all pass on good fixture", {
  fx <- make_test_scaling_fixture()
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_equal(r$n_tests, 4)
  expect_equal(r$n_failures, 0)
  expect_equal(r$n_warnings, 0)
})

test_that("lambda method fires 2 inner test_that blocks and prints validation lines", {
  fx <- make_test_scaling_fixture()
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "lambda")
  expect_equal(r$n_tests, 2)
  expect_equal(r$n_failures, 0)
  expect_true(any(grepl("=== Lambda Method Validation ===", r$output)))
  expect_true(any(grepl("Base year spatial correlation:", r$output)))
  expect_true(any(grepl("Note: Lambda method doesn't preserve exact base year values",
                        r$output)))
  expect_true(any(grepl("Median trend correlation \\(lambda method\\):", r$output)))
})

# -----------------------------------------------------------------------------
# Base-year match
# -----------------------------------------------------------------------------

test_that("relative: base-year match fails when scaled diverges from base_rate", {
  # Use ntime=11 so relative-changes checks t=c(1,5,11) (ntime%/%2=5), which
  # excludes base_idx=6. This lets us corrupt scaled_data[,,base_idx] to break
  # the base-year spatial correlation without incidentally tripping the
  # relative-changes check.
  fx <- make_test_scaling_fixture(ntime = 11)
  # Replace base-year slice with uncorrelated values to force correlation <= 0.99
  base_idx <- fx$base_year - fx$start_year + 1
  fx$scaled_data[, , base_idx] <- matrix(
    rev(as.vector(fx$base_rate)),
    nrow = nrow(fx$base_rate),
    ncol = ncol(fx$base_rate)
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_equal(r$n_tests, 4)
  expect_true(block_failed(r, "Scaled data at base year matches"))
})

# -----------------------------------------------------------------------------
# No negatives
# -----------------------------------------------------------------------------

test_that("no-negatives fails when scaled_data contains a negative value", {
  fx <- make_test_scaling_fixture()
  fx$scaled_data[1, 1, 2] <- -5
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_true(block_failed(r, "No negative values"))
  # Guard the fixture's t=2 choice: if the negative-value injection leaked
  # into the relative-changes check (which samples t=1, ntime%/%2, ntime),
  # the isolation we designed in would silently disappear. Fail loudly.
  expect_false(block_failed(r, "Relative changes are correctly applied"))
})

# -----------------------------------------------------------------------------
# Trends preserved
# -----------------------------------------------------------------------------

test_that("relative: random data fails base-year, trends, and relative-changes", {
  fx <- make_test_scaling_fixture()
  fx$scaled_data <- withr::with_seed(42, array(
    runif(length(fx$scaled_data), min = 0.1, max = 100),
    dim = dim(fx$scaled_data)
  ))
  # runif(min=0.1) guarantees no-negatives passes. The random values break
  # the base-year pattern, per-cell trends, and relative-change ratios.
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_true(block_failed(r, "Scaled data at base year matches"))
  expect_true(block_failed(r, "Trends are preserved"))
  expect_true(block_failed(r, "Relative changes are correctly applied"))
  # Guard the runif(min=0.1) choice: it's specifically bounded positive so
  # the no-negatives block cannot fire. If someone later switches to rnorm()
  # or allows negative values, this claim would silently weaken to "all four
  # blocks fail" and the test title would lie.
  expect_false(block_failed(r, "No negative values"))
})

test_that("lambda: random data that breaks relative does NOT cause lambda to fail", {
  fx <- make_test_scaling_fixture()
  fx$scaled_data <- withr::with_seed(42, array(
    runif(length(fx$scaled_data), min = 0.1, max = 100),
    dim = dim(fx$scaled_data)
  ))
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "lambda")
  # The same random fixture causes multiple inner failures under the relative
  # method (see test "relative: random data fails base-year, trends, and
  # relative-changes"). Lambda treats all three as informational, so
  # n_failures must be 0 here. This contrast is what proves lambda's
  # "informational only" semantics for its inner blocks.
  expect_equal(r$n_failures, 0)
})

# -----------------------------------------------------------------------------
# Relative changes correctly applied
# -----------------------------------------------------------------------------

test_that("relative-changes fails when scaling is off by a factor", {
  fx <- make_test_scaling_fixture()
  # Double all scaled values → rel_change will mismatch expected by 2x everywhere
  fx$scaled_data <- fx$scaled_data * 2
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_true(block_failed(r, "Relative changes are correctly applied"))
})

test_that("relative-changes warns when no suitable cell is found", {
  fx <- make_test_scaling_fixture()
  # Break every cell's time series by setting the base-year slice to NA so
  # no cell has sum(!is.na(ts_orig)) == ntime.
  base_idx <- fx$base_year - fx$start_year + 1
  fx$timeseries[, , base_idx] <- NA_real_
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_true(any(grepl("Could not find suitable cell for relative change test",
                        r$warnings)))
})

# -----------------------------------------------------------------------------
# Short-ntime fixture (exercises trends-preserved "no sampled cells" branch)
# -----------------------------------------------------------------------------

test_that("trends-preserved: ntime<=10 records zero expectations (no failures)", {
  # ntime=8: > base_idx (6) so the fixture is valid, but <= 10 so no cell has
  # > 10 valid time points → trends sampler finds nothing.
  # test_that block still runs clean: trend_cors stays empty, no expect_* fires.
  fx <- make_test_scaling_fixture(ntime = 8)
  # Recompute scaled_data with the shorter ntime; make_test_scaling_fixture already does.
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  # Because no sample landed, trends block has no expect_* calls; testthat records
  # a test_that with zero expectations, which does not count as failure.
  # The relative-changes block should still exercise the sampler successfully
  # (ntime=5 full-valid cells satisfy sum(!is.na)==ntime).
  expect_equal(r$n_failures, 0)
})
