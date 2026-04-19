# `scale_with_timeseries` Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the 166-line `scale_with_timeseries` function in `fertilizer_scaling_functions.R` into five focused helpers behind a comprehensive test suite, with no change to observable behavior.

**Architecture:** `scale_with_timeseries` calls `prepare_scaling_inputs`, allocates output, dispatches per time step to `scale_relative_timestep` or `scale_lambda_timestep` (the latter after `compute_lambda` precomputes per-cell exponents), and ends with `diagnose_extreme_values`. The lambda diagnostic `tryCatch` is preserved via a custom R condition (`lambda_timestep_error`) so `t` and `scaled_data` dims can still be reported from the caller.

**Tech Stack:** R, testthat (with `local_mocked_bindings` for wiring checks).

**Workflow per step:** Code-writing agent implements → code-reviewing agent (`superpowers:code-reviewer`) reviews diff against this plan and the spec at `docs/superpowers/specs/2026-04-19-scale-with-timeseries-modularization-design.md` → commit only after reviewer approves.

**Running tests:** From `/workspace`, use:
```bash
Rscript tests/testthat.R
```
Expected across all tasks: all tests pass after every commit.

---

## Shared fixture (lives in `test-scale_with_timeseries.R`, reused via `source()` in per-helper tests)

```r
make_harness_fixture <- function() {
  # 2 lon x 2 lat x 3 time; base_year=1999, base_idx=2
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  ts <- array(NA_real_, dim = c(2, 2, 3))
  ts[, , 1] <- matrix(c(1, 2, 3, 4), nrow = 2)
  ts[, , 2] <- matrix(c(2, 4, 6, 8), nrow = 2)  # base year; all ts_base < base_rate
  ts[, , 3] <- matrix(c(4, 8, 12, 16), nrow = 2)
  list(
    base_rate  = base_rate,
    timeseries = ts,
    start_year = 1998,
    end_year   = 2000,
    base_year  = 1999
  )
}
```

Hand-computed relative expectations (base_timeseries = ts[,,2]):

| cell | t=1 | t=2 | t=3 |
|------|-----|-----|-----|
| [1,1] | 5   | 10  | 20  |
| [2,1] | 10  | 20  | 40  |
| [1,2] | 15  | 30  | 60  |
| [2,2] | 20  | 40  | 80  |

Lambda values (ts_base < base_rate everywhere): `lambda = sqrt(ts_base / base_rate)`:

| cell  | ts_base | base_rate | lambda        |
|-------|---------|-----------|---------------|
| [1,1] | 2       | 10        | sqrt(0.2)     |
| [2,1] | 4       | 20        | sqrt(0.2)     |
| [1,2] | 6       | 30        | sqrt(0.2)     |
| [2,2] | 8       | 40        | sqrt(0.2)     |

(Note: this fixture gives uniform lambda. Per-helper `compute_lambda` tests use a second fixture that exercises the `ts_base >= base_rate` branch.)

---

## Task 1: Harness-level test suite for `scale_with_timeseries` (CHECKPOINT)

**Files:**
- Create: `tests/testthat/test-scale_with_timeseries.R`

**Intent:** Lock down every observable behavior of the current function before any extraction. No source changes in this task.

- [ ] **Step 1.1: Write the harness tests**

Create `tests/testthat/test-scale_with_timeseries.R`:

```r
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
  capture.output(
    result <- scale_with_timeseries(fx$base_rate, fx$timeseries,
                                    fx$base_year, fx$start_year, fx$end_year,
                                    method = "relative")
  )
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
  # Hand-computed expectations from the plan's table.
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
  # Both cells have valid base_rate, so output = base_rate at every step
  # (rel_change defaults to 1 when ts_base is invalid).
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
  # Separate fixture so ts_base == base_rate at every cell.
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
  # With ts_base == base_rate: lambda = 1, base/ts_base = 1,
  # scaled = base * [1 + (ts[t] - ts_base)/base] = ts[t].
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
  # Construct a fixture whose relative scaling blows past 1000.
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
  # Function still returns the full result.
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
```

- [ ] **Step 1.2: Run the suite; confirm every test passes against the unchanged function**

Run:
```bash
Rscript tests/testthat.R
```
Expected: all tests pass, including the 16 new ones. If any fail, stop and debug — the current behavior doesn't match the test, which means the test or the plan's behavior claim needs correcting.

- [ ] **Step 1.3: Reviewer check**

Dispatch `superpowers:code-reviewer` with the diff from main. Prompt:

> Review the diff for Task 1 of the plan at `docs/superpowers/plans/2026-04-19-scale-with-timeseries-modularization.md`. Spec at `docs/superpowers/specs/2026-04-19-scale-with-timeseries-modularization-design.md`. Verify: (a) test coverage matches the spec's "Harness-level tests" list; (b) all test expectations correctly describe the current implementation at `fertilizer_scaling_functions.R:93-258` (not the idealized spec version — this is a strict refactor so tests lock down current behavior); (c) the diagnostic test captures `print()` output via `capture.output` correctly. Report any missing cases or incorrect expectations.

Address findings if any, re-run tests, re-review.

- [ ] **Step 1.4: Commit**

```bash
git add tests/testthat/test-scale_with_timeseries.R
git commit -m "$(cat <<'EOF'
Add comprehensive tests for scale_with_timeseries.

Lock down current observable behavior (dispatch, validation, relative
and lambda semantics, and the >1000 kg/ha diagnostic) before any
modularization. All new tests pass against the unchanged function.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 1.5: STOP — pause for user approval before Task 2**

Report to the user: "Task 1 complete. Harness test suite is in and green. Approve to proceed with Task 2 (extract `prepare_scaling_inputs`)?"

Do not start Task 2 until the user confirms.

---

## Task 2: Extract `prepare_scaling_inputs`

**Files:**
- Modify: `fertilizer_scaling_functions.R:93-258` (extract the validation + mask + base_timeseries setup)
- Create: `tests/testthat/test-prepare_scaling_inputs.R`

### Sub-task 2a: Extract helper, update caller

- [ ] **Step 2a.1: Add `prepare_scaling_inputs` just above `scale_with_timeseries`**

Insert immediately before the `scale_with_timeseries <- function(...)` line (currently line 93):

```r
# ============================================================================
# FUNCTION: prepare_scaling_inputs
# ============================================================================
# Common setup for scale_with_timeseries: validate base_year, extract the base
# year time slice, and compute the valid_base mask.
#
# Returns: list(base_idx, base_timeseries, valid_base).
# ============================================================================
prepare_scaling_inputs <- function(base_rate, timeseries, base_year,
                                   start_year, end_year) {
  ntimes <- dim(timeseries)[3]
  base_idx <- base_year - start_year + 1
  if (base_idx < 1 || base_idx > ntimes) {
    stop(paste("Base year", base_year, "is outside the time series range",
               start_year, "-", end_year))
  }
  base_timeseries <- timeseries[, , base_idx]
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
  list(
    base_idx        = base_idx,
    base_timeseries = base_timeseries,
    valid_base      = valid_base
  )
}
```

- [ ] **Step 2a.2: Update `scale_with_timeseries` to call it**

Inside `scale_with_timeseries`, replace the setup block currently at lines 101–122 (from `# get dimensions` through `valid_base <- ...`) with:

```r
  # get dimensions
  nlon <- dim(timeseries)[1]
  nlat <- dim(timeseries)[2]
  ntimes <- dim(timeseries)[3]

  # validate + precompute common pieces
  prep <- prepare_scaling_inputs(base_rate, timeseries, base_year,
                                 start_year, end_year)
  base_idx        <- prep$base_idx
  base_timeseries <- prep$base_timeseries
  valid_base      <- prep$valid_base

  # create output array [lon, lat, time]
  scaled_data <- array(NA, dim = c(nlon, nlat, ntimes))
```

Also delete the redundant `base_timeseries <- timeseries[, , base_idx]` inside the `method == "lambda"` branch (currently at line 159) — it's now set by `prepare_scaling_inputs`.

- [ ] **Step 2a.3: Run full suite to confirm harness tests still pass**

```bash
Rscript tests/testthat.R
```
Expected: all tests pass (behavior unchanged).

- [ ] **Step 2a.4: Reviewer check**

Dispatch `superpowers:code-reviewer`:
> Review the diff for Task 2a. Verify: (a) `prepare_scaling_inputs` is a pure extraction — same logic, same error message, no behavior change; (b) the only change inside `scale_with_timeseries` is replacing the extracted lines with a call to the helper + a destructure; (c) the redundant `base_timeseries` assignment in the lambda branch is removed. Harness tests should still pass.

- [ ] **Step 2a.5: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract prepare_scaling_inputs from scale_with_timeseries.

Pure extraction: moves base_year validation, base_timeseries slice
extraction, and valid_base mask computation into a shared helper.
No behavior change; harness tests continue to pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 2b: Add per-helper tests

- [ ] **Step 2b.1: Create `tests/testthat/test-prepare_scaling_inputs.R`**

```r
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
```

- [ ] **Step 2b.2: Run tests, confirm all pass**

```bash
Rscript tests/testthat.R
```

- [ ] **Step 2b.3: Reviewer check**

> Review Task 2b. Verify per-helper tests cover: return shape, base_idx math, base_timeseries slice, each invalid-cell case for valid_base, both error bounds. No wiring checks in this file — those come in 2c.

- [ ] **Step 2b.4: Commit**

```bash
git add tests/testthat/test-prepare_scaling_inputs.R
git commit -m "$(cat <<'EOF'
Add unit tests for prepare_scaling_inputs.

Cover return shape, base_idx arithmetic, base_timeseries slice, every
invalid-cell case for valid_base, and both out-of-range error bounds.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 2c: Replace duplicate harness tests with wiring check

- [ ] **Step 2c.1: Edit `tests/testthat/test-scale_with_timeseries.R`**

Remove these now-duplicated tests (their behavior is fully covered by `test-prepare_scaling_inputs.R`):
- `"base_year below start_year raises out-of-range error"`
- `"base_year above end_year raises out-of-range error"`

Add a wiring test at the bottom of the file:

```r
# ---- Wiring checks (verify helpers are called correctly) ----------------

test_that("scale_with_timeseries calls prepare_scaling_inputs with raw args", {
  fx <- make_harness_fixture()
  captured <- list()
  local_mocked_bindings(
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
```

- [ ] **Step 2c.2: Run tests; confirm all pass**

```bash
Rscript tests/testthat.R
```

- [ ] **Step 2c.3: Reviewer check**

> Review Task 2c. Verify: (a) exactly the two validation tests were removed, no others; (b) the wiring test uses `local_mocked_bindings` and asserts each arg is forwarded verbatim; (c) the mock returns a structurally-valid `prep` so `scale_with_timeseries` can continue running.

- [ ] **Step 2c.4: Commit**

```bash
git add tests/testthat/test-scale_with_timeseries.R
git commit -m "$(cat <<'EOF'
Swap duplicated validation tests for a wiring check.

Behavior is now fully verified in test-prepare_scaling_inputs.R. The
harness retains one test that verifies scale_with_timeseries forwards
its raw arguments to prepare_scaling_inputs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Extract `scale_relative_timestep`

**Files:**
- Modify: `fertilizer_scaling_functions.R`
- Create: `tests/testthat/test-scale_relative_timestep.R`

### Sub-task 3a: Extract helper, update caller

- [ ] **Step 3a.1: Add `scale_relative_timestep`**

Insert immediately after `prepare_scaling_inputs`:

```r
# ============================================================================
# FUNCTION: scale_relative_timestep
# ============================================================================
# Compute one [lon, lat] scaled slice using the relative-change method:
#   scaled = base_rate * (ts_t / base_timeseries)
# Cells where base_rate is invalid remain NA; cells where base_rate is valid
# but base_timeseries is invalid get base_rate (rel_change defaults to 1).
# ============================================================================
scale_relative_timestep <- function(base_rate, ts_t, base_timeseries, valid_base) {
  result <- array(NA_real_, dim = dim(base_rate))
  valid_ts_base <- valid_base & !is.na(base_timeseries) & is.finite(base_timeseries) & base_timeseries > 0
  rel_change <- array(1, dim = dim(base_rate))
  rel_change[valid_ts_base] <- ts_t[valid_ts_base] / base_timeseries[valid_ts_base]
  result[valid_base] <- base_rate[valid_base] * rel_change[valid_base]
  result
}
```

- [ ] **Step 3a.2: Update `scale_with_timeseries` to call it**

Replace the body of the `if (method == "relative") { ... }` branch with:

```r
  if (method == "relative") {
    for (t in 1:ntimes) {
      scaled_data[, , t] <- scale_relative_timestep(
        base_rate, timeseries[, , t], base_timeseries, valid_base
      )
    }
```

- [ ] **Step 3a.3: Run tests; confirm all pass**

```bash
Rscript tests/testthat.R
```

- [ ] **Step 3a.4: Reviewer check**

> Review Task 3a. Verify the body of `scale_relative_timestep` matches the inner body of the original relative `for (t)` loop line-for-line (modulo returning `result` instead of writing into `scaled_data[, , t]`). Confirm behavior identical.

- [ ] **Step 3a.5: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract scale_relative_timestep from scale_with_timeseries.

Pure extraction of the per-time-step body of the relative branch into
a helper that takes one [lon, lat] slice and returns a scaled slice.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 3b: Add per-helper tests

- [ ] **Step 3b.1: Create `tests/testthat/test-scale_relative_timestep.R`**

```r
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
```

- [ ] **Step 3b.2: Run tests; confirm all pass**

- [ ] **Step 3b.3: Reviewer check**

> Review Task 3b. Verify tests cover: shape preservation, known-value scaling, invalid base_rate, invalid base_timeseries (the rel_change=1 default), and NA ts_t propagation. No wiring tests in this file.

- [ ] **Step 3b.4: Commit**

```bash
git add tests/testthat/test-scale_relative_timestep.R
git commit -m "$(cat <<'EOF'
Add unit tests for scale_relative_timestep.

Cover shape preservation, known-value scaling, invalid base_rate,
the rel_change=1 fallback for invalid base_timeseries, and NA
propagation from ts_t.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 3c: Replace duplicate harness tests with wiring check

- [ ] **Step 3c.1: Edit `test-scale_with_timeseries.R`**

Remove the following now-duplicated tests:
- `"relative: scaled[t] == base_rate * ts[t] / ts[base] at sampled cells"`
- `"relative: NA base_rate yields NA in output at every time step"`
- `"relative: non-finite base_rate yields NA in output"`
- `"relative: zero or negative base_rate yields NA in output"`
- `"relative: valid base_rate + invalid ts_base yields base_rate at every t"`
- `"relative: NA ts[t] at valid-everything cell yields NA at that t"`

Keep `"relative: base-year slice equals base_rate at valid cells"` — it's an invariant of `scale_with_timeseries` as a whole (depending on `prep$base_idx` and helper wiring), so keep it as an integration check.

Add a wiring test:

```r
test_that("scale_with_timeseries calls scale_relative_timestep once per t with correct args", {
  fx <- make_harness_fixture()
  calls <- list()
  local_mocked_bindings(
    scale_relative_timestep = function(base_rate, ts_t, base_timeseries, valid_base) {
      calls[[length(calls) + 1]] <<- list(
        base_rate = base_rate, ts_t = ts_t,
        base_timeseries = base_timeseries, valid_base = valid_base
      )
      # Return a sentinel slice so we can check it reaches the output.
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
  # Per-step: ts_t is the t-th slice; everything else is constant.
  for (t in seq_len(ntime)) {
    expect_equal(calls[[t]]$base_rate, fx$base_rate)
    expect_equal(calls[[t]]$ts_t, fx$timeseries[, , t])
    expect_equal(calls[[t]]$base_timeseries, fx$timeseries[, , 2])
  }
  # Helper's return value is written to the output at each t.
  expect_true(all(result == -999))
})
```

- [ ] **Step 3c.2: Run tests; confirm all pass**

- [ ] **Step 3c.3: Reviewer check**

> Review Task 3c. Verify: (a) only the six listed duplicated tests were removed and the base-year-slice test was kept as an integration check; (b) the wiring test verifies call count (= ntimes), per-call ts_t slice, constant args, and that the mock's return value reaches the output array.

- [ ] **Step 3c.4: Commit**

```bash
git add tests/testthat/test-scale_with_timeseries.R
git commit -m "$(cat <<'EOF'
Swap duplicated relative-method tests for a wiring check.

Behavior now lives in test-scale_relative_timestep.R. The harness
retains the base-year integration check and adds a wiring test that
verifies per-t invocation and arg forwarding.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extract `compute_lambda`

**Files:**
- Modify: `fertilizer_scaling_functions.R`
- Create: `tests/testthat/test-compute_lambda.R`

### Sub-task 4a: Extract helper, update caller

- [ ] **Step 4a.1: Add `compute_lambda`**

Insert after `scale_relative_timestep`:

```r
# ============================================================================
# FUNCTION: compute_lambda
# ============================================================================
# Compute the per-cell lambda exponent used by the lambda scaling method.
# lambda = sqrt(base_timeseries / base_rate) when base_timeseries < base_rate
# (at cells where both are valid and positive). Otherwise lambda = 1.
# ============================================================================
compute_lambda <- function(base_rate, base_timeseries, valid_base) {
  nlon <- dim(base_rate)[1]
  nlat <- dim(base_rate)[2]
  lambda <- array(1, dim = c(nlon, nlat))
  for (i in 1:nlon) {
    for (j in 1:nlat) {
      if (valid_base[i, j] && !is.na(base_timeseries[i, j]) && base_timeseries[i, j] > 0) {
        ts_base_val <- base_timeseries[i, j]
        spatial_val <- base_rate[i, j]
        if (ts_base_val < spatial_val) {
          lambda[i, j] <- sqrt(ts_base_val / spatial_val)
        } else {
          lambda[i, j] <- 1
        }
      }
    }
  }
  lambda
}
```

- [ ] **Step 4a.2: Update `scale_with_timeseries`'s lambda branch**

In the `else if (method == "lambda")` block, replace the current lambda-array computation (the block that builds `lambda <- array(1, ...)` via nested loops, currently lines 161–179) with:

```r
    lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
```

Leave the per-time-step loop that applies lambda untouched for now — Task 5 extracts it.

- [ ] **Step 4a.3: Run tests; confirm all pass**

```bash
Rscript tests/testthat.R
```

- [ ] **Step 4a.4: Reviewer check**

> Review Task 4a. Verify: (a) `compute_lambda` body is a line-for-line move of the original lambda-computation block; (b) the nested for-loop is preserved (vectorization is explicitly deferred); (c) the application loop (the second nested loop over t/i/j) is untouched.

- [ ] **Step 4a.5: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract compute_lambda from scale_with_timeseries.

Pure extraction of the per-cell lambda exponent computation. The
nested for-loop is preserved as-is; vectorization is tracked in the
spec's Next steps section.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 4b: Add per-helper tests

- [ ] **Step 4b.1: Create `tests/testthat/test-compute_lambda.R`**

```r
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
```

- [ ] **Step 4b.2: Run tests; confirm all pass**

- [ ] **Step 4b.3: Reviewer check**

> Review Task 4b. Verify tests cover: shape, the `ts < base` branch, the `ts >= base` branch, invalid base cells defaulting to 1, invalid ts cells defaulting to 1.

- [ ] **Step 4b.4: Commit**

```bash
git add tests/testthat/test-compute_lambda.R
git commit -m "$(cat <<'EOF'
Add unit tests for compute_lambda.

Cover shape, both comparison branches (ts < base and ts >= base),
and the default-to-1 behavior for invalid base and invalid ts cells.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 4c: Replace duplicate harness tests with wiring check

- [ ] **Step 4c.1: Edit `test-scale_with_timeseries.R`**

No lambda-specific harness tests are yet fully duplicated by `compute_lambda` alone (the existing lambda harness tests verify end-to-end scaling, which still depends on `scale_lambda_timestep` in Task 5). So at this stage we only **add** a wiring test:

```r
test_that("scale_with_timeseries calls compute_lambda once for lambda method with correct args", {
  fx <- make_harness_fixture()
  called_with <- NULL
  call_count <- 0
  local_mocked_bindings(
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
  local_mocked_bindings(
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
```

- [ ] **Step 4c.2: Run tests; confirm all pass**

- [ ] **Step 4c.3: Reviewer check**

> Review Task 4c. Verify: (a) no harness tests were removed (removals come in 5c when the lambda integration tests are subsumed); (b) two new wiring tests check the lambda-only call-once behavior and confirm `compute_lambda` is not called for the relative method.

- [ ] **Step 4c.4: Commit**

```bash
git add tests/testthat/test-scale_with_timeseries.R
git commit -m "$(cat <<'EOF'
Add wiring checks for compute_lambda invocation.

Verify scale_with_timeseries calls compute_lambda exactly once with
the correct args for the lambda method, and never for the relative
method. No existing harness tests are removed at this point; the
lambda end-to-end tests wait for scale_lambda_timestep extraction.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Extract `scale_lambda_timestep` (with custom condition)

**Files:**
- Modify: `fertilizer_scaling_functions.R`
- Create: `tests/testthat/test-scale_lambda_timestep.R`

### Sub-task 5a: Extract helper with custom condition; update caller

- [ ] **Step 5a.1: Add `scale_lambda_timestep`**

Insert after `compute_lambda`:

```r
# ============================================================================
# FUNCTION: scale_lambda_timestep
# ============================================================================
# Compute one [lon, lat] scaled slice using the lambda scaling method.
#   scaled = base * [1 + (ts_t - ts_base) / base * (base / ts_base) ^ lambda]
# Clamped to >= 0. Invalid cells remain NA.
#
# On an internal error, this function re-throws a 'lambda_timestep_error'
# condition carrying i, j, nlon, nlat so the caller can enrich the
# diagnostic with time-step-level context (t, scaled_data dims).
# ============================================================================
scale_lambda_timestep <- function(base_rate, ts_t, base_timeseries,
                                  valid_base, lambda) {
  nlon <- dim(base_rate)[1]
  nlat <- dim(base_rate)[2]
  result <- array(NA_real_, dim = c(nlon, nlat))
  tryCatch({
    for (i in 1:nlon) {
      for (j in 1:nlat) {
        if (valid_base[i, j] && !is.na(base_timeseries[i, j]) && base_timeseries[i, j] > 0) {
          fert_diff <- ts_t[i, j] - base_timeseries[i, j]
          ratio_base <- base_rate[i, j] / base_timeseries[i, j]
          ratio_term <- ratio_base ^ lambda[i, j]
          result[i, j] <- base_rate[i, j] * (1 + (fert_diff / base_rate[i, j]) * ratio_term)
          if (!is.na(result[i, j]) && result[i, j] < 0) {
            result[i, j] <- 0
          }
        }
      }
    }
  }, error = function(e) {
    stop(structure(
      class = c("lambda_timestep_error", "error", "condition"),
      list(
        message  = e$message,
        call     = e$call,
        original = e,
        i        = i,
        j        = j,
        nlon     = nlon,
        nlat     = nlat
      )
    ))
  })
  result
}
```

- [ ] **Step 5a.2: Update `scale_with_timeseries`'s lambda branch**

Replace the lambda application loop (currently the `for (t in 1:ntimes)` block with its nested tryCatch and nested i/j loops) with:

```r
    for (t in 1:ntimes) {
      tryCatch({
        scaled_data[, , t] <- scale_lambda_timestep(
          base_rate, timeseries[, , t], base_timeseries, valid_base, lambda
        )
      }, lambda_timestep_error = function(e) {
        cat(sprintf("\nERROR in lambda loop at time step t=%d:\n", t))
        cat(sprintf("  Message: %s\n", e$message))
        cat(sprintf("  Last indices: i=%d (max=%d), j=%d (max=%d)\n",
                    e$i, e$nlon, e$j, e$nlat))
        cat(sprintf("  scaled_data dims: %d x %d x %d\n",
                    dim(scaled_data)[1], dim(scaled_data)[2], dim(scaled_data)[3]))
        stop(e$original)
      })
    }
```

- [ ] **Step 5a.3: Run tests; confirm all pass**

```bash
Rscript tests/testthat.R
```

- [ ] **Step 5a.4: Reviewer check**

> Review Task 5a carefully. Verify: (a) `scale_lambda_timestep`'s inner loop body is identical to the original lambda application loop body; (b) the custom condition signals `i, j, nlon, nlat` and wraps the original error in `$original`; (c) the caller's `tryCatch` prints the same four diagnostic lines as the original with the same text and order, pulling `i/j/nlon/nlat` from the condition and `t`/`scaled_data` dims from its local scope; (d) final `stop(e$original)` re-throws the original error class, matching the original's `stop(e)`.

- [ ] **Step 5a.5: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract scale_lambda_timestep; route diagnostic via custom condition.

Move the lambda method's inner timestep body into a helper. The
original tryCatch diagnostic (which reports t, scaled_data dims, and
i/j/nlon/nlat) is preserved by splitting it across both scopes via a
lambda_timestep_error condition: the helper reports i/j/nlon/nlat, and
the caller wraps the call to add t and scaled_data dims.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 5b: Add per-helper tests

- [ ] **Step 5b.1: Create `tests/testthat/test-scale_lambda_timestep.R`**

```r
# Tests for scale_lambda_timestep() in fertilizer_scaling_functions.R.

make_lambda_fixture <- function() {
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  list(base_rate = base_rate, base_timeseries = base_timeseries,
       valid_base = valid_base, lambda = lambda)
}

test_that("scaled slice has same shape as base_rate", {
  fx <- make_lambda_fixture()
  ts_t <- fx$base_timeseries
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_equal(dim(out), dim(fx$base_rate))
})

test_that("at the base time step (fert_diff = 0), output equals base_rate", {
  fx <- make_lambda_fixture()
  ts_t <- fx$base_timeseries
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_equal(out, fx$base_rate)
})

test_that("when ts_base == base_rate (lambda = 1), output equals ts_t", {
  # lambda = 1 and base/ts_base = 1 → scaled = ts_t.
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- base_rate
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  lambda <- matrix(1, nrow = 2, ncol = 2)
  ts_t <- matrix(c(12, 25, 35, 45), nrow = 2)
  out <- scale_lambda_timestep(base_rate, ts_t, base_timeseries,
                               valid_base, lambda)
  expect_equal(out, ts_t)
})

test_that("output is clamped to non-negative", {
  # Force a negative raw result: pick a fixture where fert_diff is very
  # negative. base=10, ts_base=2 (lambda=sqrt(0.2)), ts_t=-50 → very negative.
  base_rate <- matrix(10, nrow = 1, ncol = 1)
  base_timeseries <- matrix(2, nrow = 1, ncol = 1)
  valid_base <- matrix(TRUE, nrow = 1, ncol = 1)
  lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
  ts_t <- matrix(-50, nrow = 1, ncol = 1)
  out <- scale_lambda_timestep(base_rate, ts_t, base_timeseries,
                               valid_base, lambda)
  expect_equal(out[1, 1], 0)
})

test_that("invalid base_rate cells remain NA", {
  fx <- make_lambda_fixture()
  fx$base_rate[1, 1] <- NA
  fx$valid_base <- !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate > 0
  ts_t <- fx$base_timeseries
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_true(is.na(out[1, 1]))
})

test_that("invalid base_timeseries cells remain NA", {
  fx <- make_lambda_fixture()
  fx$base_timeseries[1, 1] <- NA
  fx$base_timeseries[2, 1] <- 0
  ts_t <- matrix(c(1, 2, 3, 4), nrow = 2)
  out <- scale_lambda_timestep(fx$base_rate, ts_t, fx$base_timeseries,
                               fx$valid_base, fx$lambda)
  expect_true(is.na(out[1, 1]))
  expect_true(is.na(out[2, 1]))
})

test_that("internal error re-throws as a lambda_timestep_error with i/j/nlon/nlat", {
  # Provide a lambda array with wrong dims to force an error inside the loop.
  base_rate <- matrix(c(10, 20, 30, 40), nrow = 2, ncol = 2)
  base_timeseries <- matrix(c(2, 4, 6, 8), nrow = 2, ncol = 2)
  valid_base <- matrix(TRUE, nrow = 2, ncol = 2)
  bad_lambda <- matrix(1, nrow = 1, ncol = 1)  # wrong shape
  ts_t <- base_timeseries
  cond <- tryCatch(
    scale_lambda_timestep(base_rate, ts_t, base_timeseries, valid_base, bad_lambda),
    lambda_timestep_error = function(e) e
  )
  expect_s3_class(cond, "lambda_timestep_error")
  expect_true(!is.null(cond$i))
  expect_true(!is.null(cond$j))
  expect_equal(cond$nlon, 2)
  expect_equal(cond$nlat, 2)
  expect_s3_class(cond$original, "error")
})
```

- [ ] **Step 5b.2: Run tests; confirm all pass**

- [ ] **Step 5b.3: Reviewer check**

> Review Task 5b. Verify tests cover: shape, the fert_diff=0 invariant, the ts_base==base invariant, the non-negativity clamp, invalid base_rate, invalid base_timeseries, and the custom condition on internal error.

- [ ] **Step 5b.4: Commit**

```bash
git add tests/testthat/test-scale_lambda_timestep.R
git commit -m "$(cat <<'EOF'
Add unit tests for scale_lambda_timestep.

Cover shape, the fert_diff=0 and ts_base==base identities, the
non-negativity clamp, NA propagation from invalid inputs, and that
internal errors surface as a lambda_timestep_error condition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 5c: Replace duplicate harness tests with wiring check

- [ ] **Step 5c.1: Edit `test-scale_with_timeseries.R`**

Remove the following now-duplicated lambda tests (their behavior lives in `test-compute_lambda.R` and `test-scale_lambda_timestep.R`):
- `"lambda: output is clamped to non-negative values"`
- `"lambda: base-year slice at cells where ts_base == base_rate equals base_rate"`
- `"lambda: when ts_base == base_rate, scaled[t] equals ts[t] at that cell"`
- `"lambda: NA base_rate yields NA in output"`

Keep the dispatch/shape test `"lambda method returns an array with shape [nlon, nlat, ntimes]"` — it's a pure integration check.

Add a wiring test:

```r
test_that("scale_with_timeseries calls scale_lambda_timestep once per t with correct args", {
  fx <- make_harness_fixture()
  calls <- list()
  local_mocked_bindings(
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
  # Lambda passed in should be the one compute_lambda produces.
  expected_lambda <- compute_lambda(
    fx$base_rate, fx$timeseries[, , 2],
    !is.na(fx$base_rate) & is.finite(fx$base_rate) & fx$base_rate > 0
  )
  expect_equal(calls[[1]]$lambda, expected_lambda)
  expect_true(all(result == -999))
})

test_that("scale_with_timeseries enriches lambda_timestep_error with t and dims", {
  fx <- make_harness_fixture()
  local_mocked_bindings(
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
  expect_true(any(grepl("scaled_data dims: 2 x 2 x 3", out)))
  expect_true(any(grepl("Last indices: i=1 \\(max=2\\), j=1 \\(max=2\\)", out)))
})
```

- [ ] **Step 5c.2: Run tests; confirm all pass**

- [ ] **Step 5c.3: Reviewer check**

> Review Task 5c. Verify: (a) exactly the four listed lambda tests were removed, and the dispatch/shape test was kept; (b) the wiring test checks call count, per-t ts_t, and that `lambda` matches what `compute_lambda` would produce; (c) the error-enrichment test raises a `lambda_timestep_error` from the mock and asserts all four diagnostic lines appear in output before the error propagates.

- [ ] **Step 5c.4: Commit**

```bash
git add tests/testthat/test-scale_with_timeseries.R
git commit -m "$(cat <<'EOF'
Swap duplicated lambda tests for wiring and error-enrichment checks.

Behavior now lives in test-scale_lambda_timestep.R and
test-compute_lambda.R. The harness retains the dispatch/shape test
and adds wiring tests that verify per-t invocation and that the
caller enriches lambda_timestep_error with t and scaled_data dims.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Extract `diagnose_extreme_values`

**Files:**
- Modify: `fertilizer_scaling_functions.R`
- Create: `tests/testthat/test-diagnose_extreme_values.R`

### Sub-task 6a: Extract helper, update caller

- [ ] **Step 6a.1: Add `diagnose_extreme_values`**

Insert after `scale_lambda_timestep`:

```r
# ============================================================================
# FUNCTION: diagnose_extreme_values
# ============================================================================
# Print a warning and details for cells whose scaled value exceeds
# 1000 kg/ha. Never alters scaled_data. Returns invisibly.
# ============================================================================
diagnose_extreme_values <- function(scaled_data, base_rate, base_timeseries,
                                    timeseries, start_year) {
  max_val <- max(scaled_data, na.rm = TRUE)
  if (max_val > 1000) {
    print(paste("WARNING: Maximum scaled value is", round(max_val, 1), "kg/ha"))
    extreme_threshold <- 1000
    extreme_cells <- which(
      apply(scaled_data, c(1, 2), function(x) any(x > extreme_threshold, na.rm = TRUE)),
      arr.ind = TRUE
    )
    if (nrow(extreme_cells) > 0) {
      print(paste("Found", nrow(extreme_cells), "cells with values >",
                  extreme_threshold, "kg/ha"))
      n_report <- min(5, nrow(extreme_cells))
      for (i in 1:n_report) {
        idx_lon <- extreme_cells[i, 1]
        idx_lat <- extreme_cells[i, 2]
        ts_cell <- scaled_data[idx_lon, idx_lat, ]
        max_year_idx <- which.max(ts_cell)
        max_year <- start_year + max_year_idx - 1
        print(paste("\nCell", i, "at lon index", idx_lon, ", lat index", idx_lat))
        print(paste("  Base rate (year 2000 spatial):",
                    round(base_rate[idx_lon, idx_lat], 2), "kg/ha"))
        print(paste("  TS at base year (2000):",
                    round(base_timeseries[idx_lon, idx_lat], 2), "kg/ha"))
        print(paste("  TS at year", max_year, ":",
                    round(timeseries[idx_lon, idx_lat, max_year_idx], 2), "kg/ha"))
        print(paste("  Relative change:",
                    round(timeseries[idx_lon, idx_lat, max_year_idx] / base_timeseries[idx_lon, idx_lat], 2)))
        print(paste("  Scaled value at year", max_year, ":",
                    round(ts_cell[max_year_idx], 2), "kg/ha"))
        ratio_base_to_ts <- base_rate[idx_lon, idx_lat] / base_timeseries[idx_lon, idx_lat]
        if (abs(ratio_base_to_ts - 1) > 0.5) {
          print(paste("  MISMATCH: Spatial base / TS base ratio =",
                      round(ratio_base_to_ts, 2)))
        }
      }
    }
  }
  invisible(NULL)
}
```

- [ ] **Step 6a.2: Update `scale_with_timeseries`**

Replace the extreme-values block (currently lines 219–255, beginning with `max_val <- max(scaled_data, ...)` and ending at the final `}` before `return(scaled_data)`) with:

```r
  diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                          timeseries, start_year)
```

- [ ] **Step 6a.3: Run tests; confirm all pass**

- [ ] **Step 6a.4: Reviewer check**

> Review Task 6a. Verify `diagnose_extreme_values` body is a line-for-line move of the original block, every `print()` has identical text, the `MISMATCH` conditional is preserved, and the function returns `invisible(NULL)` so the caller's return path is unaffected.

- [ ] **Step 6a.5: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract diagnose_extreme_values from scale_with_timeseries.

Pure extraction of the >1000 kg/ha warning block. All print() text
is preserved verbatim; the helper never mutates scaled_data and
returns invisible(NULL).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 6b: Add per-helper tests

- [ ] **Step 6b.1: Create `tests/testthat/test-diagnose_extreme_values.R`**

```r
# Tests for diagnose_extreme_values() in fertilizer_scaling_functions.R.

make_scaled_fixture <- function(max_val) {
  # 2x2x3 scaled_data with a single cell reaching `max_val` at t=3.
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
                                   start_year = 1998)
  )
  expect_null(ret)
  expect_equal(fx$scaled_data, before)
})

test_that("prints warning and cell details when max > 1000", {
  fx <- make_scaled_fixture(5000)
  out <- capture.output(
    diagnose_extreme_values(fx$scaled_data, fx$base_rate,
                            fx$base_timeseries, fx$timeseries,
                            start_year = 1998)
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
                            start_year = 1998)
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
                            timeseries, start_year = 1998)
  )
  expect_true(any(grepl("Found 9 cells", out)))
  # "Cell 1" through "Cell 5" appear; "Cell 6" does not.
  expect_true(any(grepl("Cell 5 at lon index", out)))
  expect_false(any(grepl("Cell 6 at lon index", out)))
})

test_that("prints MISMATCH line when base_rate / base_timeseries diverges >0.5", {
  scaled_data <- array(10, dim = c(2, 2, 3))
  scaled_data[1, 1, 3] <- 5000
  base_rate <- matrix(c(500, 10, 10, 10), nrow = 2, ncol = 2)   # 500 / 1 = 500, |500-1| > 0.5
  base_timeseries <- matrix(c(1, 1, 1, 1), nrow = 2, ncol = 2)
  timeseries <- array(1, dim = c(2, 2, 3))
  timeseries[1, 1, 3] <- 10
  out <- capture.output(
    diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                            timeseries, start_year = 1998)
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
                            timeseries, start_year = 1998)
  )
  expect_false(any(grepl("MISMATCH", out)))
})
```

- [ ] **Step 6b.2: Run tests; confirm all pass**

- [ ] **Step 6b.3: Reviewer check**

> Review Task 6b. Verify tests cover: invisible return + immutability of scaled_data, warning trigger above threshold, silence below threshold, the 5-cell cap, the MISMATCH conditional on both sides.

- [ ] **Step 6b.4: Commit**

```bash
git add tests/testthat/test-diagnose_extreme_values.R
git commit -m "$(cat <<'EOF'
Add unit tests for diagnose_extreme_values.

Cover: invisible return, immutability of scaled_data, threshold
trigger, silence below threshold, 5-cell reporting cap, and the
MISMATCH conditional.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 6c: Replace duplicate harness tests with wiring check

- [ ] **Step 6c.1: Edit `test-scale_with_timeseries.R`**

Remove the two diagnostic tests now fully covered by `test-diagnose_extreme_values.R`:
- `"diagnostic warning fires when max scaled value exceeds 1000"`
- `"no diagnostic warning when max scaled value is under 1000"`

Add a wiring test:

```r
test_that("scale_with_timeseries calls diagnose_extreme_values with scaled_data and context", {
  fx <- make_harness_fixture()
  captured <- list()
  local_mocked_bindings(
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
```

- [ ] **Step 6c.2: Run tests; confirm all pass**

- [ ] **Step 6c.3: Reviewer check**

> Review Task 6c. Verify: (a) exactly the two diagnostic tests were removed; (b) the wiring test confirms all five args forwarded correctly and that diagnose is called *after* scaling (captured scaled_data equals the returned result).

- [ ] **Step 6c.4: Commit**

```bash
git add tests/testthat/test-scale_with_timeseries.R
git commit -m "$(cat <<'EOF'
Swap duplicated diagnostic tests for a wiring check.

Behavior now lives in test-diagnose_extreme_values.R. The harness
wiring test confirms scale_with_timeseries forwards all five
arguments and invokes diagnose_extreme_values after scaling.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Final cleanup pass on `scale_with_timeseries`

**Files:**
- Modify: `fertilizer_scaling_functions.R`

- [ ] **Step 7.1: Read the refactored `scale_with_timeseries` end-to-end**

At this point the function should look approximately like:

```r
scale_with_timeseries <- function(base_rate, timeseries, base_year = 2000,
                                   start_year, end_year, method = "relative") {
  print(paste("Using scaling method:", method))

  nlon <- dim(timeseries)[1]
  nlat <- dim(timeseries)[2]
  ntimes <- dim(timeseries)[3]

  prep <- prepare_scaling_inputs(base_rate, timeseries, base_year,
                                 start_year, end_year)
  base_idx        <- prep$base_idx
  base_timeseries <- prep$base_timeseries
  valid_base      <- prep$valid_base

  scaled_data <- array(NA, dim = c(nlon, nlat, ntimes))

  if (method == "relative") {
    for (t in 1:ntimes) {
      scaled_data[, , t] <- scale_relative_timestep(
        base_rate, timeseries[, , t], base_timeseries, valid_base
      )
    }
  } else if (method == "lambda") {
    lambda <- compute_lambda(base_rate, base_timeseries, valid_base)
    for (t in 1:ntimes) {
      tryCatch({
        scaled_data[, , t] <- scale_lambda_timestep(
          base_rate, timeseries[, , t], base_timeseries, valid_base, lambda
        )
      }, lambda_timestep_error = function(e) {
        cat(sprintf("\nERROR in lambda loop at time step t=%d:\n", t))
        cat(sprintf("  Message: %s\n", e$message))
        cat(sprintf("  Last indices: i=%d (max=%d), j=%d (max=%d)\n",
                    e$i, e$nlon, e$j, e$nlat))
        cat(sprintf("  scaled_data dims: %d x %d x %d\n",
                    dim(scaled_data)[1], dim(scaled_data)[2], dim(scaled_data)[3]))
        stop(e$original)
      })
    }
  } else {
    stop(paste("Unknown scaling method:", method))
  }

  diagnose_extreme_values(scaled_data, base_rate, base_timeseries,
                          timeseries, start_year)

  return(scaled_data)
}
```

Look for and fix:
- **Unused locals:** `base_idx` is no longer read by `scale_with_timeseries` directly after helper extraction (only used by helpers internally). If unused, drop the `base_idx <- prep$base_idx` line.
- **Orphaned comments:** remove comments inside `scale_with_timeseries` that referred to since-moved code (e.g., "vectorized scaling over time steps" inside the relative branch).
- **Dead blank lines.**

Do NOT change any behavior, print text, or error messages.

- [ ] **Step 7.2: Update the function docstring (lines 71–92)**

The current docstring describes the function's internal algorithm. Keep the purpose/args/returns/method-options text; trim the algorithm detail that's now in the helpers' docstrings. If you shrink it, ensure the "Method options" section still accurately describes what the user sees.

- [ ] **Step 7.3: Run the full suite**

```bash
Rscript tests/testthat.R
```
Expected: all tests pass.

- [ ] **Step 7.4: Reviewer check**

> Review Task 7. Verify: (a) `scale_with_timeseries` is ~25–35 lines and reads as "validate → allocate → dispatch → diagnose → return"; (b) no behavior changes from the pre-cleanup commit — all prints, errors, and diagnostics identical; (c) no unused locals or orphaned comments remain inside the function; (d) docstring is accurate and focused on the user-facing contract.

- [ ] **Step 7.5: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Final cleanup of scale_with_timeseries after modularization.

Remove unused locals, orphaned comments left behind by the helper
extractions, and trim the docstring to the user-facing contract. No
behavior changes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review (spec coverage)

- Spec: "comprehensive harness-level test suite" → Task 1 creates `test-scale_with_timeseries.R` with 16 tests covering every item in the spec's "Harness-level tests" list.
- Spec: `prepare_scaling_inputs` → Task 2 (2a extract, 2b test, 2c wiring).
- Spec: `scale_relative_timestep` → Task 3.
- Spec: `compute_lambda` → Task 4.
- Spec: `scale_lambda_timestep` with preserved tryCatch → Task 5, implemented via custom condition per user's choice of Option B.
- Spec: `diagnose_extreme_values` → Task 6.
- Spec: final state "~25 lines" → Task 7 verifies and trims.
- Spec: "writer/reviewer/commit at every step" → every sub-task has explicit reviewer step before commit.
- Spec: "pause after Step 1" → Step 1.5 is a hard stop.
- Spec: "Next steps" (vectorization, `message()`/`warning()`, diagnostic placement) → out of scope for this plan, tracked in spec only.

No placeholder text, no "TODO", all code blocks are complete.
