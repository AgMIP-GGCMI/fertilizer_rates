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

# ---- Diagnostics ----------------------------------------------------------

# ---- Wiring checks (verify helpers are called correctly) ----------------

test_that("scale_with_timeseries calls prepare_scaling_inputs with raw args", {
  fx <- make_harness_fixture()
  captured <- list()
  local_mock(
    prepare_scaling_inputs = function(base_rate, timeseries, base_year,
                                      start_year, end_year) {
      captured <<- list(
        base_rate = base_rate, timeseries = timeseries,
        base_year = base_year, start_year = start_year, end_year = end_year
      )
      # Return a valid prep so scale_with_timeseries can proceed.
      list(
        base_idx = base_year - start_year + 1,
        base_timeseries = timeseries[, , base_year - start_year + 1],
        valid_base = !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
      )
    }
  )
  capture.output(
    scale_with_timeseries(fx$base_rate, fx$timeseries,
                          fx$base_year, fx$start_year, fx$end_year,
                          method = "relative")
  )
  expect_equal(captured$base_rate, fx$base_rate)
  expect_equal(captured$timeseries, fx$timeseries)
  expect_equal(captured$base_year, fx$base_year)
  expect_equal(captured$start_year, fx$start_year)
  expect_equal(captured$end_year, fx$end_year)
})

test_that("scale_with_timeseries calls scale_relative_timestep once per t with correct args", {
  fx <- make_harness_fixture()
  calls <- list()
  local_mock(
    scale_relative_timestep = function(base_rate, ts_t, base_timeseries, valid_base) {
      calls[[length(calls) + 1]] <<- list(
        base_rate = base_rate, ts_t = ts_t,
        base_timeseries = base_timeseries, valid_base = valid_base
      )
      matrix(-999, nrow = dim(base_rate)[1], ncol = dim(base_rate)[2])
    }
  )
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  ntime <- dim(fx$timeseries)[3]
  expect_equal(length(calls), ntime)
  for (t in seq_len(ntime)) {
    expect_equal(calls[[t]]$base_rate, fx$base_rate)
    expect_equal(calls[[t]]$ts_t, fx$timeseries[, , t])
    expect_equal(calls[[t]]$base_timeseries, fx$timeseries[, , 2])
  }
  expect_true(all(result == -999))
})

test_that("scale_with_timeseries calls compute_lambda once for lambda method with correct args", {
  fx <- make_harness_fixture()
  called_with <- NULL
  call_count <- 0
  local_mock(
    compute_lambda = function(base_rate, base_timeseries, valid_base) {
      call_count <<- call_count + 1
      called_with <<- list(base_rate = base_rate,
                           base_timeseries = base_timeseries,
                           valid_base = valid_base)
      matrix(1, nrow = dim(base_rate)[1], ncol = dim(base_rate)[2])
    }
  )
  capture.output(
    scale_with_timeseries(fx$base_rate, fx$timeseries,
                          fx$base_year, fx$start_year, fx$end_year,
                          method = "lambda")
  )
  expect_equal(call_count, 1)
  expect_equal(called_with$base_rate, fx$base_rate)
  expect_equal(called_with$base_timeseries, fx$timeseries[, , 2])
  expect_equal(called_with$valid_base,
               !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate > 0)
})

test_that("scale_with_timeseries does not call compute_lambda for relative method", {
  fx <- make_harness_fixture()
  call_count <- 0
  local_mock(
    compute_lambda = function(...) {
      call_count <<- call_count + 1
      matrix(1, nrow = dim(fx$base_rate)[1], ncol = dim(fx$base_rate)[2])
    }
  )
  capture.output(
    scale_with_timeseries(fx$base_rate, fx$timeseries,
                          fx$base_year, fx$start_year, fx$end_year,
                          method = "relative")
  )
  expect_equal(call_count, 0)
})

test_that("scale_with_timeseries calls scale_lambda_timestep once per t with correct args", {
  fx <- make_harness_fixture()
  calls <- list()
  local_mock(
    scale_lambda_timestep = function(base_rate, ts_t, base_timeseries,
                                     valid_base, lambda) {
      calls[[length(calls) + 1]] <<- list(
        base_rate = base_rate, ts_t = ts_t,
        base_timeseries = base_timeseries,
        valid_base = valid_base, lambda = lambda
      )
      matrix(-999, nrow = dim(base_rate)[1], ncol = dim(base_rate)[2])
    }
  )
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  ntime <- dim(fx$timeseries)[3]
  expect_equal(length(calls), ntime)
  for (t in seq_len(ntime)) {
    expect_equal(calls[[t]]$base_rate, fx$base_rate)
    expect_equal(calls[[t]]$ts_t, fx$timeseries[, , t])
    expect_equal(calls[[t]]$base_timeseries, fx$timeseries[, , 2])
  }
  expected_lambda <- compute_lambda(
    fx$base_rate, fx$timeseries[, , 2],
    !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate > 0
  )
  expect_equal(calls[[1]]$lambda, expected_lambda)
  expect_true(all(result == -999))
})

test_that("scale_with_timeseries enriches lambda_timestep_error with t and dims", {
  fx <- make_harness_fixture()
  local_mock(
    scale_lambda_timestep = function(base_rate, ts_t, base_timeseries,
                                     valid_base, lambda) {
      stop(structure(
        class = c("lambda_timestep_error", "error", "condition"),
        list(message = "boom",
             original = simpleError("boom"),
             i = 1, j = 1, nlon = 2, nlat = 2)
      ))
    }
  )
  # capture.output propagates errors and loses the captured text, so use
  # sink() directly so we can inspect the diagnostic output even though the
  # call errors out.
  tmpfile <- tempfile()
  sink(tmpfile)
  withr::defer(if (sink.number() > 0) sink())
  err <- tryCatch(
    scale_with_timeseries(fx$base_rate, fx$timeseries,
                          fx$base_year, fx$start_year, fx$end_year,
                          method = "lambda"),
    error = function(e) e
  )
  sink()
  out <- readLines(tmpfile)

  expect_s3_class(err, "error")
  expect_equal(err$message, "boom")
  expect_true(any(grepl("ERROR in lambda loop at time step t=1", out)))
  expect_true(any(grepl("Message: boom", out)))
  expect_true(any(grepl("scaled_data dims: 2 x 2 x 3", out)))
  expect_true(any(grepl("Last indices: i=1 \\(max=2\\), j=1 \\(max=2\\)", out)))
})

test_that("scale_with_timeseries calls diagnose_extreme_values with scaled_data and context", {
  fx <- make_harness_fixture()
  captured <- list()
  local_mock(
    diagnose_extreme_values = function(scaled_data, base_rate,
                                       base_timeseries, timeseries,
                                       start_year) {
      captured <<- list(
        scaled_data = scaled_data, base_rate = base_rate,
        base_timeseries = base_timeseries, timeseries = timeseries,
        start_year = start_year
      )
      invisible(NULL)
    }
  )
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
  expect_equal(dim(captured$scaled_data), dim(fx$timeseries))
  expect_equal(captured$base_rate, fx$base_rate)
  expect_equal(captured$base_timeseries, fx$timeseries[, , 2])
  expect_equal(captured$timeseries, fx$timeseries)
  expect_equal(captured$start_year, fx$start_year)
  # The diagnostic is called AFTER scaling is complete, so captured$scaled_data
  # should be the final result.
  expect_equal(captured$scaled_data, result)
})
