# Tests for scale_with_timeseries() in fertilizer_scaling_functions.R.
#
# These tests lock down the end-to-end behavior of scale_with_timeseries()
# across the modularization refactor, and now also verify the wiring to
# extracted helpers. Fixtures are small (2x2x3) so every expected value can
# be hand-computed.

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
  local_mocked_globals(
    prepare_scaling_inputs = function(base_rate, timeseries, base_year,
                                      start_year, end_year,
                                      base_timeseries_override = NULL) {
      captured <<- list(
        base_rate = base_rate, timeseries = timeseries,
        base_year = base_year, start_year = start_year, end_year = end_year,
        base_timeseries_override = base_timeseries_override
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
  expect_null(captured$base_timeseries_override)
})

test_that("scale_with_timeseries calls scale_relative_timestep once per t with correct args", {
  fx <- make_harness_fixture()
  calls <- list()
  local_mocked_globals(
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
  fx$base_rate[1, 1] <- 0
  called_with <- NULL
  call_count <- 0
  local_mocked_globals(
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
               !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate >= 0)
})

test_that("scale_with_timeseries does not call compute_lambda for relative method", {
  fx <- make_harness_fixture()
  call_count <- 0
  local_mocked_globals(
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
  fx$base_rate[1, 1] <- 0
  calls <- list()
  local_mocked_globals(
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
    !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate >= 0
  )
  expect_equal(calls[[1]]$lambda, expected_lambda)
  expect_true(all(result == -999))
})

test_that("lambda method uses raw TS for zero base-rate cells", {
  fx <- make_harness_fixture()
  fx$base_rate[1, 1] <- 0
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  expect_equal(result[1, 1, ], fx$timeseries[1, 1, ])
})

test_that("scale_with_timeseries applies hard 500 kgN/ha cap for lambda method", {
  fx <- make_harness_fixture()
  local_mocked_globals(
    scale_lambda_timestep = function(base_rate, ts_t, base_timeseries,
                                     valid_base, lambda) {
      matrix(c(100, 500, 650, 1200), nrow = 2)
    }
  )
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  expect_true(all(result <= 500, na.rm = TRUE))
  expect_equal(result[, , 1], matrix(c(100, 500, 500, 500), nrow = 2))
  expect_equal(result[, , 2], matrix(c(100, 500, 500, 500), nrow = 2))
  expect_equal(result[, , 3], matrix(c(100, 500, 500, 500), nrow = 2))
})

test_that("lambda delayed-anchor fallback applies when TS(base_year) < 1, anchor after base year", {
  base_rate <- matrix(c(100, 20, 30, 40), nrow = 2)
  ts <- array(NA_real_, dim = c(2, 2, 4))

  # Cell [1,1]: base_year ts is 0 (<1), anchor from full series is t=3 (value 2).
  ts[1, 1, ] <- c(0.5, 0, 2, 4)
  # Other cells: regular positive series to keep default lambda behavior active.
  ts[2, 1, ] <- c(2, 2, 2, 2)
  ts[1, 2, ] <- c(3, 3, 3, 3)
  ts[2, 2, ] <- c(4, 4, 4, 4)

  capture.output(
    result <- scale_with_timeseries(
      base_rate = base_rate,
      timeseries = ts,
      base_year = 1999,
      start_year = 1998,
      end_year = 2001,
      method = "lambda"
    )
  )

  # Fallback uses base_rate * TS(t)/TS(anchor), anchor value = 0.5 at t=1
  # (first value >= 0 that is the first positive in the series).
  # Actually anchor threshold is 1, and ts[1,1,] = c(0.5, 0, 2, 4):
  # first value >= 1 is at t=3 (value 2).
  expect_equal(result[1, 1, 1], 25)   # 100 * 0.5/2
  expect_equal(result[1, 1, 2], 0)    # 100 * 0/2
  expect_equal(result[1, 1, 3], 100)  # 100 * 2/2
  expect_equal(result[1, 1, 4], 200)  # 100 * 4/2
})

test_that("lambda delayed-anchor finds anchor BEFORE base_year for histsoc-style series", {
  # Simulates histsoc: TS has positive values in early years, zero at base_year.
  base_rate <- matrix(c(100, 20, 30, 40), nrow = 2)
  ts <- array(NA_real_, dim = c(2, 2, 5))

  # Cell [1,1]: positive in early period (t=1,2 = pre-2000), zero at base year (t=3), more zeros after.
  ts[1, 1, ] <- c(3, 6, 0, 0, 0)  # anchor should be t=1, value=3
  ts[2, 1, ] <- c(2, 2, 2, 2, 2)
  ts[1, 2, ] <- c(3, 3, 3, 3, 3)
  ts[2, 2, ] <- c(4, 4, 4, 4, 4)

  capture.output(
    result <- scale_with_timeseries(
      base_rate = base_rate,
      timeseries = ts,
      base_year = 2000,    # corresponds to t=3
      start_year = 1998,
      end_year = 2002,
      method = "lambda"
    )
  )

  # anchor = first t with TS >= 1 in full series = t=1, value=3
  # scaled(t) = base_rate * TS(t)/3
  expect_equal(result[1, 1, 1], 100)   # 100 * 3/3
  expect_equal(result[1, 1, 2], 200)   # 100 * 6/3
  expect_equal(result[1, 1, 3], 0)     # 100 * 0/3
  expect_equal(result[1, 1, 4], 0)     # 100 * 0/3
  expect_equal(result[1, 1, 5], 0)     # 100 * 0/3
})

test_that("lambda delayed-anchor unresolved cells fall back to raw TS(t)", {
  base_rate <- matrix(c(100, 20, 30, 40), nrow = 2)
  ts <- array(NA_real_, dim = c(2, 2, 5))

  # Cell [1,1]: TS(base_year)=0 and no value >= 1 in entire series.
  ts[1, 1, ] <- c(0, 0.2, 0, 0.4, 0)
  ts[2, 1, ] <- c(2, 2, 2, 2, 2)
  ts[1, 2, ] <- c(3, 3, 3, 3, 3)
  ts[2, 2, ] <- c(4, 4, 4, 4, 4)

  capture.output(
    result <- scale_with_timeseries(
      base_rate = base_rate,
      timeseries = ts,
      base_year = 2000,
      start_year = 1998,
      end_year = 2002,
      method = "lambda"
    )
  )

  expect_equal(as.numeric(result[1, 1, ]), as.numeric(ts[1, 1, ]))
  expect_true(all(is.finite(result[1, 1, ])))
})

test_that("delayed-anchor search accepts TS exactly equal to the threshold", {
  base_rate <- matrix(c(100, 20, 30, 40), nrow = 2)
  ts <- array(NA_real_, dim = c(2, 2, 4))

  # Cell [1,1]: TS(base_year) = 0 (< 1). The first year with TS == 1 is the
  # anchor, so the later value 4 is not used.
  ts[1, 1, ] <- c(0.5, 0, 1, 4)
  ts[2, 1, ] <- c(2, 2, 2, 2)
  ts[1, 2, ] <- c(3, 3, 3, 3)
  ts[2, 2, ] <- c(4, 4, 4, 4)

  capture.output(
    result <- scale_with_timeseries(
      base_rate = base_rate,
      timeseries = ts,
      base_year = 1999,
      start_year = 1998,
      end_year = 2001,
      method = "lambda"
    )
  )

  expect_equal(as.numeric(result[1, 1, ]), c(50, 0, 100, 400))
})

test_that("delayed-anchor search skips NA and Inf years", {
  base_rate <- matrix(c(100, 20, 30, 40), nrow = 2)
  ts <- array(NA_real_, dim = c(2, 2, 5))

  # Cell [1,1]: the NA and Inf years precede the first finite TS >= 1, which
  # is t=4 (value 2). TS(base_year = t3) = 0 (< 1).
  ts[1, 1, ] <- c(NA, Inf, 0, 2, 4)
  ts[2, 1, ] <- c(2, 2, 2, 2, 2)
  ts[1, 2, ] <- c(3, 3, 3, 3, 3)
  ts[2, 2, ] <- c(4, 4, 4, 4, 4)

  capture.output(
    result <- scale_with_timeseries(
      base_rate = base_rate,
      timeseries = ts,
      base_year = 2000,
      start_year = 1998,
      end_year = 2002,
      method = "lambda"
    )
  )

  expect_equal(as.numeric(result[1, 1, 3:5]), c(0, 100, 200))
  expect_equal(as.numeric(result[1, 1, 1:2]), c(NA_real_, NA_real_))
})

test_that("lambda cap leaves NA cells NA and caps only values above 500", {
  fx <- make_harness_fixture()
  local_mocked_globals(
    scale_lambda_timestep = function(base_rate, ts_t, base_timeseries,
                                     valid_base, lambda) {
      matrix(c(NA, 600, 500, 499.5), nrow = 2)
    }
  )
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "lambda")
  )
  for (t in 1:3) {
    expect_equal(result[, , t], matrix(c(NA, 500, 500, 499.5), nrow = 2))
  }
})

test_that("lambda cap applies to delayed-anchor fallback values", {
  base_rate <- matrix(c(100, 20, 30, 40), nrow = 2)
  ts <- array(NA_real_, dim = c(2, 2, 4))

  # Cell [1,1]: TS(base_year) = 0 (< 1), anchor at t=3 (value 1). The
  # fallback 100 * 8/1 = 800 in the last year is capped to 500. An unresolved
  # delayed-anchor cell is not covered: its raw TS is < 1, so it cannot
  # exceed the cap.
  ts[1, 1, ] <- c(0, 0, 1, 8)
  ts[2, 1, ] <- c(2, 2, 2, 2)
  ts[1, 2, ] <- c(3, 3, 3, 3)
  ts[2, 2, ] <- c(4, 4, 4, 4)

  capture.output(
    result <- scale_with_timeseries(
      base_rate = base_rate,
      timeseries = ts,
      base_year = 1999,
      start_year = 1998,
      end_year = 2001,
      method = "lambda"
    )
  )

  expect_equal(as.numeric(result[1, 1, ]), c(0, 0, 100, 500))
})

test_that("lambda loop reports the time step for any error and lets it propagate", {
  fx <- make_harness_fixture()
  calls <- 0
  local_mocked_globals(
    scale_lambda_timestep = function(base_rate, ts_t, base_timeseries,
                                     valid_base, lambda) {
      calls <<- calls + 1
      if (calls == 2) stop("boom")
      base_rate
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
  expect_match(conditionMessage(err), "boom")
  expect_true(any(grepl("ERROR in lambda loop at time step t=2:", out)))
  expect_true(any(grepl("Message: boom", out)))
  expect_true(any(grepl("scaled_data dims: 2 x 2 x 3", out)))
})

test_that("scale_with_timeseries calls diagnose_extreme_values with scaled_data and context", {
  fx <- make_harness_fixture()
  captured <- list()
  local_mocked_globals(
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

test_that("relative and lambda scaling keep [lon, lat, t] dims on grids with a length-1 dimension", {
  for (dims in list(c(2, 1), c(1, 1))) {
    nlon <- dims[1]; nlat <- dims[2]
    base_rate <- array(100, dim = dims)
    # TS(base) = 2 >= 1, so lambda takes its ordinary (non-delayed-anchor) path
    ts <- array(rep(c(2, 3, 4), each = nlon * nlat), dim = c(dims, 3))
    for (method in c("relative", "lambda")) {
      out <- scale_with_timeseries(base_rate, ts, base_year = 2020,
                                   start_year = 2020, end_year = 2022,
                                   method = method)
      expect_equal(dim(out), c(dims, 3))
      expect_equal(as.vector(out[, , 1]), rep(100, nlon * nlat))
      if (method == "relative") {
        expect_equal(as.vector(out[, , 3]), rep(200, nlon * nlat))
      } else {
        # Formula from the scale_lambda_timestep header, with
        # lambda = sqrt(ts_base / base) since 0 < ts_base < base
        lambda <- sqrt(2 / 100)
        expected <- 100 * (1 + (c(3, 4) - 2) / 100 * (100 / 2)^lambda)
        expect_equal(as.vector(out[, , 2]), rep(expected[1], nlon * nlat))
        expect_equal(as.vector(out[, , 3]), rep(expected[2], nlon * nlat))
        # Same per-cell inputs on a 3x3 grid, which never drops dims
        ref <- scale_with_timeseries(array(100, c(3, 3)),
                                     array(rep(c(2, 3, 4), each = 9), c(3, 3, 3)),
                                     base_year = 2020, start_year = 2020,
                                     end_year = 2022, method = "lambda")
        expect_equal(as.vector(out[, , 3]), rep(ref[1, 1, 3], nlon * nlat))
        expect_equal(expected[2], ref[1, 1, 3])
      }
    }
  }
})
