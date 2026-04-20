# `test_scaling` Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the ~125-line `test_scaling` function in `fertilizer_scaling_functions.R` into four focused check helpers behind a comprehensive harness-level test suite, with zero change to observable behavior.

**Architecture:** `test_scaling` becomes a ~45-line orchestrator that calls four pure check helpers (`check_base_year_match`, `check_no_negatives`, `check_trends_preserved`, `check_relative_changes_applied`) and wraps their structured return values in the existing `test_that` / `expect_*` / `cat()` branches per method.

**Tech Stack:** R, testthat. Wiring checks use `tests/testthat/helper-mock.R`'s `local_mocked_globals()`. Harness-level tests use `testthat::ListReporter` + `testthat::with_reporter()` to inspect inner `test_that` outcomes without polluting the outer runner.

---

## File structure

- **`fertilizer_scaling_functions.R`** — define 4 new helpers above `test_scaling` (starting around the current line 330). Replace `test_scaling` body with orchestrator logic.
- **`tests/testthat/test-test_scaling.R`** — new harness file. Contains `make_test_scaling_fixture()` + 10 harness tests (Task 1). Wiring tests added during Tasks 2-5.
- **`tests/testthat/test-check_base_year_match.R`** — new per-helper file (Task 2).
- **`tests/testthat/test-check_no_negatives.R`** — new per-helper file (Task 3).
- **`tests/testthat/test-check_trends_preserved.R`** — new per-helper file (Task 4).
- **`tests/testthat/test-check_relative_changes_applied.R`** — new per-helper file (Task 5).

All test files are auto-sourced by `tests/testthat/setup.R`. The existing `helper-mock.R` provides `local_mocked_globals()` for wiring checks.

---

## Execution workflow

**Every task uses the following writer → spec-reviewer → code-quality-reviewer → commit subagent cycle.** No commit lands without both reviewers approving its diff.

1. **Writer subagent** (usually Sonnet, general-purpose). Full task text + working directory + explicit instructions + test commands pasted into the prompt. Implements all sub-commits for the task, runs tests after each, commits each.
2. **Spec reviewer subagent** (Sonnet, general-purpose). Reads each commit diff, verifies against this plan + the spec at `docs/superpowers/specs/2026-04-20-test-scaling-modularization-design.md`. For source-changing commits, runs a byte-identity check on `test_scaling`'s observable behavior pre/post. Reports ✅ compliant or ❌ with file:line references.
3. **Code quality reviewer subagent** (`superpowers:code-reviewer`). Reads the same diff, focuses on idiomatic style, test clarity, naming, pattern consistency with the existing codebase.
4. **Fix cycle.** If either reviewer flags blocking issues, dispatch a follow-up writer subagent (Haiku is fine for tightly-scoped cleanup). Re-run the relevant reviewer(s) after the fix. Only bundle multiple blocking fixes if they're tightly related; otherwise one fix per commit.
5. **Proceed** to the next task only after both reviewers approve the current task's diff.

Minor/nice-to-have suggestions can be deferred to Task 6 (final cleanup) or noted in the branch description and left for follow-up. Critical/important findings block.

**Test command after every commit:** `Rscript tests/testthat.R` from the worktree root. Must report 0 FAIL.

---

## Task 0: Environment setup

**Files:**
- Create worktree at: `.worktrees/test-scaling-modularization`
- Branch: `feature/test-scaling-modularization` based on `main`

- [ ] **Step 0.1: Verify main is clean**

Run: `git status`
Expected: `On branch main ... nothing to commit, working tree clean`. If anything's dirty, stop and surface to the user.

- [ ] **Step 0.2: Create the worktree**

Run:
```bash
git worktree add .worktrees/test-scaling-modularization -b feature/test-scaling-modularization
cd .worktrees/test-scaling-modularization
```

Expected: `Preparing worktree (new branch 'feature/test-scaling-modularization')`.

- [ ] **Step 0.3: Baseline test run**

Run: `Rscript tests/testthat.R`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 128 ]`. If any failures, stop.

- [ ] **Step 0.4: Baseline coverage run**

Run: `Rscript tests/coverage.R`
Expected: prints `Line coverage: 12.78%` (or thereabouts) and exits 0.

(Task 0 has no commits — it's environment setup only. All subsequent tasks happen in this worktree.)

---

## Task 1: Comprehensive harness-level test suite for `test_scaling` (CHECKPOINT)

**Files:**
- Create: `tests/testthat/test-test_scaling.R`

**Intent:** Lock down every observable behavior of `test_scaling` before any extraction. Pass against the unchanged source. `test_scaling` itself is NOT modified in this task.

**Approach:** use `testthat::ListReporter` + `testthat::with_reporter()` to inspect inner `test_that` outcomes. Wrap inspection in a local helper `run_test_scaling_capture()` so the ListReporter-API details are localised to one place.

- [ ] **Step 1.1: Create `tests/testthat/test-test_scaling.R`**

Full content:

```r
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
#   list(output, n_tests, n_failures, n_warnings, results)
# - output:      character vector of captured stdout lines
# - n_tests:     count of inner test_that blocks that ran
# - n_failures:  count of test_that blocks containing at least one failure
# - n_warnings:  count of warnings raised during the run
# - results:     the raw reporter$get_results() list (for deeper inspection)
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
  list(
    output     = output,
    n_tests    = n_tests,
    n_failures = n_failures,
    n_warnings = length(warnings),
    warnings   = warnings,
    results    = results
  )
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
  fx <- make_test_scaling_fixture()
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
  expect_gte(r$n_failures, 1)
})

# -----------------------------------------------------------------------------
# No negatives
# -----------------------------------------------------------------------------

test_that("no-negatives fails when scaled_data contains a negative value", {
  fx <- make_test_scaling_fixture()
  fx$scaled_data[1, 1, 1] <- -5
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_gte(r$n_failures, 1)
})

# -----------------------------------------------------------------------------
# Trends preserved
# -----------------------------------------------------------------------------

test_that("trends-preserved fails under relative when scaled is constant in time", {
  fx <- make_test_scaling_fixture()
  # Make scaled_data constant across time while timeseries varies → trends uncorrelated
  base_slice <- fx$scaled_data[, , 1]
  for (t in seq_len(dim(fx$scaled_data)[3])) {
    fx$scaled_data[, , t] <- base_slice
  }
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_gte(r$n_failures, 1)
})

test_that("trends-preserved under lambda does NOT assert, only prints", {
  fx <- make_test_scaling_fixture()
  # Even with broken trends, lambda should NOT record a failure for trends
  base_slice <- fx$scaled_data[, , 1]
  for (t in seq_len(dim(fx$scaled_data)[3])) {
    fx$scaled_data[, , t] <- base_slice
  }
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "lambda")
  # Trends block still runs (1 of 2) but should not have failures from trends.
  # Note: the base-year-match for lambda doesn't fire a test_that; only 2 blocks total.
  # The only possible failure under lambda is no-negatives.
  expect_true(any(grepl("Median trend correlation \\(lambda method\\):", r$output)))
  # Whatever the outcome, the 'trends' line printed — lambda reports, doesn't assert.
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
  expect_gte(r$n_failures, 1)
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

test_that("trends-preserved: on ntime<=10 fixture, no cells sampled, block still passes", {
  # ntime=5 means no cell has > 10 valid time points → no trends measured.
  # test_that block still runs clean: trend_cors stays empty, no expect_* fires.
  fx <- make_test_scaling_fixture(ntime = 5)
  # Recompute scaled_data with the shorter ntime; make_test_scaling_fixture already does.
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  # Because no sample landed, trends block has no expect_* calls; testthat records
  # a test_that with zero expectations, which does not count as failure.
  # The relative-changes block should still exercise the sampler successfully
  # (ntime=5 full-valid cells satisfy sum(!is.na)==ntime).
  expect_equal(r$n_failures, 0)
})
```

- [ ] **Step 1.2: Run the full test suite**

Run: `Rscript tests/testthat.R`
Expected: all existing tests pass PLUS the new harness tests pass. Report the post-Task-1 pass count; expect around 128 + 9 ≈ 137 (may vary depending on how testthat counts `expect_*` vs `test_that` blocks).

**If any test fails**, STOP and report BLOCKED. Do NOT modify the source — it's a strict refactor and failures mean either (a) the test assertion is wrong or (b) a behavior assumption is wrong; controller must decide.

One known caveat: the `run_test_scaling_capture` helper uses `reporter$get_results()`. If that method doesn't exist on this testthat's `ListReporter`, the helper will error. In that case, inspect `reporter$results` (note: no `$get_`) or `names(reporter)` at an R prompt to find the right accessor, and adjust the helper — keep the helper's return shape unchanged.

- [ ] **Step 1.3: Writer → spec-reviewer → code-quality-reviewer cycle**

Dispatch the spec reviewer with this prompt (paraphrased): "Verify `tests/testthat/test-test_scaling.R` covers the 10 harness behaviors listed in the plan's Task 1 (2 dispatch × 1 base-year-match × 1 no-negatives × 2 trends-preserved × 2 relative-changes × 1 short-ntime). Run `Rscript tests/testthat.R` and confirm 0 FAIL. Confirm `fertilizer_scaling_functions.R` is untouched (`git diff HEAD~1 HEAD -- fertilizer_scaling_functions.R` should be empty)."

Dispatch the code quality reviewer via `superpowers:code-reviewer` with BASE_SHA = worktree's initial commit and HEAD_SHA = after Task 1 commit. Focus areas: test clarity, grepl regex specificity, fixture helper design, the `run_test_scaling_capture` helper's robustness.

- [ ] **Step 1.4: Commit**

Only after both reviewers approve. Message:

```
git add tests/testthat/test-test_scaling.R
git commit -m "$(cat <<'EOF'
Add comprehensive tests for test_scaling.

Lock down current observable behavior (method dispatch, 4 inner
test_that blocks for relative + 2 for lambda, plus cat() informational
output, and the no-suitable-cell warning) before any modularization.
Uses testthat::ListReporter + with_reporter() to inspect inner
test_that outcomes without polluting the outer runner.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 1.5: STOP — pause for user approval before Task 2**

Report to the user: "Task 1 complete. Comprehensive harness tests for `test_scaling` are in and green. Approve to proceed with Tasks 2-6 autonomously?"

Do not start Task 2 until the user confirms.

---

## Task 2: Extract `check_base_year_match`

**Files:**
- Modify: `fertilizer_scaling_functions.R` (add helper just before `test_scaling`, then replace the base-year logic inside `test_scaling`)
- Create: `tests/testthat/test-check_base_year_match.R`
- Modify: `tests/testthat/test-test_scaling.R` (swap duplicated tests for wiring check)

### Sub-task 2a: Extract helper + update caller

- [ ] **Step 2a.1: Add `check_base_year_match` above `test_scaling`**

Insert immediately before the `test_scaling <- function(...)` declaration (currently line 330):

```r
# ============================================================================
# FUNCTION: check_base_year_match
# ============================================================================
# Compute the correlation between scaled_data's base-year slice and base_rate,
# across cells valid in both. Returns list(n_valid, correlation) where
# correlation is NA when n_valid == 0.
# ============================================================================
check_base_year_match <- function(scaled_data, base_rate, base_idx) {
  scaled_base <- scaled_data[, , base_idx]
  valid_cells <- !is.na(base_rate) & !is.na(scaled_base)
  n_valid <- sum(valid_cells)
  correlation <- if (n_valid > 0) {
    cor(
      as.vector(base_rate[valid_cells]),
      as.vector(scaled_base[valid_cells]),
      use = "complete.obs"
    )
  } else {
    NA_real_
  }
  list(n_valid = n_valid, correlation = correlation)
}
```

- [ ] **Step 2a.2: Update `test_scaling`'s base-year logic**

Replace the current block inside `test_scaling`:

```r
  # Test 1: Base year match - only applies to relative method
  if (method == "relative") {
    test_that("Scaled data at base year matches original pattern (relative method)", {
      # Extract base year from scaled data [lon, lat]
      scaled_base <- scaled_data[, , base_idx]
      
      # Compare (accounting for NA positions)
      valid_cells <- !is.na(base_rate) & !is.na(scaled_base)
      if (sum(valid_cells) > 0) {
        # Should be very close (allowing for numerical precision)
        expect_true(cor(as.vector(base_rate[valid_cells]), 
                       as.vector(scaled_base[valid_cells]), 
                       use = "complete.obs") > 0.99)
      }
    })
  } else {
    # For lambda method, just report correlation (informational only)
    cat(sprintf("\n=== Lambda Method Validation ===\n"))
    scaled_base <- scaled_data[, , base_idx]
    valid_cells <- !is.na(base_rate) & !is.na(scaled_base)
    if (sum(valid_cells) > 0) {
      # Pattern should still be correlated, just not identical
      cor_val <- cor(as.vector(base_rate[valid_cells]), 
                    as.vector(scaled_base[valid_cells]), 
                    use = "complete.obs")
      cat(sprintf("Base year spatial correlation: %.4f\n", cor_val))
      cat(sprintf("Note: Lambda method doesn't preserve exact base year values\n"))
    }
  }
```

with:

```r
  # Test 1: Base year match - only applies to relative method
  bym <- check_base_year_match(scaled_data, base_rate, base_idx)
  if (method == "relative") {
    test_that("Scaled data at base year matches original pattern (relative method)", {
      if (bym$n_valid > 0) {
        expect_true(bym$correlation > 0.99)
      }
    })
  } else {
    # For lambda method, just report correlation (informational only)
    cat(sprintf("\n=== Lambda Method Validation ===\n"))
    if (bym$n_valid > 0) {
      cat(sprintf("Base year spatial correlation: %.4f\n", bym$correlation))
      cat(sprintf("Note: Lambda method doesn't preserve exact base year values\n"))
    }
  }
```

- [ ] **Step 2a.3: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL. Test count should match Task 1's final count (no tests added yet).

- [ ] **Step 2a.4: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract check_base_year_match from test_scaling.

Pure extraction of the base-year correlation computation. Caller
still wraps the return value in the same test_that / cat() branches
per method. No behavior change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 2b: Per-helper tests

- [ ] **Step 2b.1: Create `tests/testthat/test-check_base_year_match.R`**

```r
# Tests for check_base_year_match() in fertilizer_scaling_functions.R.

test_that("returns a list with n_valid and correlation", {
  base_rate   <- matrix(c(10, 20, 30, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- base_rate
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_named(out, c("n_valid", "correlation"))
})

test_that("perfect match yields correlation very near 1 and n_valid = n cells", {
  base_rate   <- matrix(c(10, 20, 30, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- base_rate
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 4)
  expect_equal(out$correlation, 1, tolerance = 1e-12)
})

test_that("NA in base_rate excludes those cells from n_valid", {
  base_rate   <- matrix(c(10, NA, 30, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- matrix(c(10, 20, 30, 40), nrow = 2)
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 3)
})

test_that("NA in scaled base-year slice excludes those cells from n_valid", {
  base_rate   <- matrix(c(10, 20, 30, 40), nrow = 2)
  scaled_slice <- matrix(c(10, 20, NA, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- scaled_slice
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 3)
})

test_that("when n_valid == 0, correlation is NA (no crash)", {
  base_rate   <- matrix(NA_real_, nrow = 2, ncol = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 0)
  expect_true(is.na(out$correlation))
})

test_that("correlation matches hand-computed value on partial overlap", {
  # Cells (1,1)=(10,10), (2,1)=(20,20), others NA in base_rate
  base_rate <- matrix(c(10, 20, NA, NA), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- matrix(c(10, 20, 100, 200), nrow = 2)
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 2)
  # With only 2 matched points both identical, correlation is exactly 1
  expect_equal(out$correlation, 1, tolerance = 1e-12)
})
```

- [ ] **Step 2b.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL, test count increased by 6 new blocks.

- [ ] **Step 2b.3: Commit**

```bash
git add tests/testthat/test-check_base_year_match.R
git commit -m "$(cat <<'EOF'
Add unit tests for check_base_year_match.

Cover return shape, perfect-match correlation, NA handling in both
inputs, the n_valid == 0 corner case, and hand-computed partial
overlap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 2c: Wiring-check swap

- [ ] **Step 2c.1: Edit `tests/testthat/test-test_scaling.R`**

REMOVE the `test_that("relative: base-year match fails when scaled diverges from base_rate", ...)` block. Its behavior is now covered by `test-check_base_year_match.R`.

ADD a wiring test at the bottom of the file (under a new `# ---- Wiring checks ----` divider):

```r
# ---- Wiring checks --------------------------------------------------------

test_that("test_scaling calls check_base_year_match with correct args", {
  fx <- make_test_scaling_fixture()
  captured <- list()
  local_mocked_globals(
    check_base_year_match = function(scaled_data, base_rate, base_idx) {
      captured <<- list(
        scaled_data = scaled_data,
        base_rate   = base_rate,
        base_idx    = base_idx
      )
      list(n_valid = 10, correlation = 0.999)  # valid return so caller can proceed
    }
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_equal(captured$scaled_data, fx$scaled_data)
  expect_equal(captured$base_rate, fx$base_rate)
  expect_equal(captured$base_idx, fx$base_year - fx$start_year + 1)
  # Wiring test: mock returned correlation=0.999 > 0.99, so the inner
  # expect_true(bym$correlation > 0.99) should not fire a failure.
  expect_equal(r$n_failures, 0)
})
```

- [ ] **Step 2c.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 2c.3: Commit**

```bash
git add tests/testthat/test-test_scaling.R
git commit -m "$(cat <<'EOF'
Swap duplicated base-year test for a wiring check.

Behavior of check_base_year_match is verified directly in its own
test file. The harness retains an integration check ensuring
test_scaling forwards arguments correctly and uses the return value
in the expect_* branch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 2 reviewer cycle

After all three sub-commits land, dispatch spec reviewer + code quality reviewer on the Task 2 diff (`git diff <pre-Task-2> <post-Task-2>`). Fix any findings; re-review. Only proceed to Task 3 after both approve.

---

## Task 3: Extract `check_no_negatives`

### Sub-task 3a: Extract helper + update caller

- [ ] **Step 3a.1: Add `check_no_negatives` after `check_base_year_match`**

```r
# ============================================================================
# FUNCTION: check_no_negatives
# ============================================================================
# TRUE when all non-NA values in scaled_data are non-negative. NA cells are
# ignored. Returns a single logical.
# ============================================================================
check_no_negatives <- function(scaled_data) {
  all(scaled_data >= 0 | is.na(scaled_data))
}
```

- [ ] **Step 3a.2: Update `test_scaling`'s no-negatives block**

Replace:

```r
  test_that("No negative values introduced by scaling", {
    # Negative fertilizer rates are physically impossible
    expect_true(all(scaled_data >= 0 | is.na(scaled_data)))
  })
```

with:

```r
  test_that("No negative values introduced by scaling", {
    expect_true(check_no_negatives(scaled_data))
  })
```

- [ ] **Step 3a.3: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 3a.4: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract check_no_negatives from test_scaling.

One-line predicate lifted into a named helper. Caller wraps the
result in the same test_that as before.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 3b: Per-helper tests

- [ ] **Step 3b.1: Create `tests/testthat/test-check_no_negatives.R`**

```r
# Tests for check_no_negatives() in fertilizer_scaling_functions.R.

test_that("TRUE when all values are non-negative", {
  x <- array(c(0, 1, 2, 3), dim = c(2, 2, 1))
  expect_true(check_no_negatives(x))
})

test_that("TRUE when some values are NA and the rest are non-negative", {
  x <- array(c(NA_real_, 1, 2, 3), dim = c(2, 2, 1))
  expect_true(check_no_negatives(x))
})

test_that("FALSE when a single non-NA cell is negative", {
  x <- array(c(0, 1, -0.001, 3), dim = c(2, 2, 1))
  expect_false(check_no_negatives(x))
})

test_that("TRUE on an all-NA array", {
  x <- array(NA_real_, dim = c(2, 2, 2))
  expect_true(check_no_negatives(x))
})

test_that("accepts 2D matrices as well as 3D arrays", {
  expect_true(check_no_negatives(matrix(c(0, 1, 2, 3), nrow = 2)))
  expect_false(check_no_negatives(matrix(c(0, -1, 2, 3), nrow = 2)))
})
```

- [ ] **Step 3b.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 3b.3: Commit**

```bash
git add tests/testthat/test-check_no_negatives.R
git commit -m "$(cat <<'EOF'
Add unit tests for check_no_negatives.

Cover all-non-negative, NA handling, single negative cell, all-NA
array, and both 2D/3D inputs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 3c: Wiring-check swap

- [ ] **Step 3c.1: Edit `tests/testthat/test-test_scaling.R`**

REMOVE the `test_that("no-negatives fails when scaled_data contains a negative value", ...)` block.

ADD a wiring test under the `# ---- Wiring checks ----` section:

```r
test_that("test_scaling calls check_no_negatives with scaled_data", {
  fx <- make_test_scaling_fixture()
  captured <- list()
  local_mocked_globals(
    check_no_negatives = function(scaled_data) {
      captured <<- list(scaled_data = scaled_data)
      TRUE  # valid pass so caller doesn't fail
    }
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_equal(captured$scaled_data, fx$scaled_data)
  expect_equal(r$n_failures, 0)
})
```

- [ ] **Step 3c.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 3c.3: Commit**

```bash
git add tests/testthat/test-test_scaling.R
git commit -m "$(cat <<'EOF'
Swap duplicated no-negatives test for a wiring check.

Behavior of check_no_negatives is verified in its own test file.
The harness retains a wiring test confirming test_scaling forwards
scaled_data correctly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3 reviewer cycle

Same pattern as Task 2: spec reviewer + code quality reviewer on the Task 3 diff. Address findings before proceeding.

---

## Task 4: Extract `check_trends_preserved`

### Sub-task 4a: Extract helper + update caller

- [ ] **Step 4a.1: Add `check_trends_preserved` after `check_no_negatives`**

```r
# ============================================================================
# FUNCTION: check_trends_preserved
# ============================================================================
# Sample up to n_samples cells (attempting up to max_attempts times) and
# compute the correlation between the original and scaled time series at
# each sampled cell. Returns list(n_sampled, median_correlation) where
# median_correlation is NA when no valid samples were collected.
#
# Preserves the current non-deterministic sample() behavior.
# ============================================================================
check_trends_preserved <- function(scaled_data, timeseries,
                                   n_samples = 100, max_attempts = 1000) {
  nlon <- dim(scaled_data)[1]
  nlat <- dim(scaled_data)[2]

  sampled <- 0
  trend_cors <- numeric()

  for (attempt in 1:max_attempts) {
    i <- sample(1:nlon, 1)
    j <- sample(1:nlat, 1)

    ts_orig <- timeseries[i, j, ]
    ts_scaled <- scaled_data[i, j, ]

    if (sum(!is.na(ts_orig)) > 10 && sum(!is.na(ts_scaled)) > 10) {
      valid <- !is.na(ts_orig) & !is.na(ts_scaled)
      if (sum(valid) > 10 && sd(ts_orig[valid]) > 0 && sd(ts_scaled[valid]) > 0) {
        cor_val <- cor(ts_orig[valid], ts_scaled[valid])
        trend_cors <- c(trend_cors, cor_val)
        sampled <- sampled + 1
      }
    }

    if (sampled >= n_samples) break
  }

  median_correlation <- if (length(trend_cors) > 0) {
    median(trend_cors, na.rm = TRUE)
  } else {
    NA_real_
  }
  list(n_sampled = sampled, median_correlation = median_correlation)
}
```

- [ ] **Step 4a.2: Update `test_scaling`'s trends block**

Replace:

```r
  test_that("Trends are preserved from time series", {
    # Sample some grid cells and check if trends match
    nlon <- dim(scaled_data)[1]
    nlat <- dim(scaled_data)[2]
    ntime <- dim(scaled_data)[3]
    
    # Sample 100 random cells with data
    sampled <- 0
    trend_cors <- numeric()
    
    for (attempt in 1:1000) {
      i <- sample(1:nlon, 1)
      j <- sample(1:nlat, 1)
      
      # Check if both have valid time series
      # timeseries is [lon, lat, time]
      ts_orig <- timeseries[i, j, ]
      ts_scaled <- scaled_data[i, j, ]
      
      if (sum(!is.na(ts_orig)) > 10 && sum(!is.na(ts_scaled)) > 10) {
        # Calculate correlation of trends
        valid <- !is.na(ts_orig) & !is.na(ts_scaled)
        if (sum(valid) > 10 && sd(ts_orig[valid]) > 0 && sd(ts_scaled[valid]) > 0) {
          cor_val <- cor(ts_orig[valid], ts_scaled[valid])
          trend_cors <- c(trend_cors, cor_val)
          sampled <- sampled + 1
        }
      }
      
      if (sampled >= 100) break
    }
    
    if (length(trend_cors) > 0) {
      # Trends should be highly correlated (relative scaling preserves shape)
      median_cor <- median(trend_cors, na.rm = TRUE)
      if (method == "relative") {
        expect_true(median_cor > 0.95)
      } else {
        # For lambda method, just report (trends may differ)
        cat(sprintf("Median trend correlation (lambda method): %.4f\n", median_cor))
      }
    }
  })
```

with:

```r
  trends <- check_trends_preserved(scaled_data, timeseries)
  test_that("Trends are preserved from time series", {
    if (trends$n_sampled > 0) {
      if (method == "relative") {
        expect_true(trends$median_correlation > 0.95)
      } else {
        cat(sprintf("Median trend correlation (lambda method): %.4f\n",
                    trends$median_correlation))
      }
    }
  })
```

- [ ] **Step 4a.3: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 4a.4: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract check_trends_preserved from test_scaling.

Move the sample-and-correlate logic into a pure helper. The sampler
threshold constants (n_samples=100, max_attempts=1000, > 10 valid
time points) are preserved verbatim. Caller now receives the median
correlation and applies the method-specific branch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 4b: Per-helper tests

- [ ] **Step 4b.1: Create `tests/testthat/test-check_trends_preserved.R`**

```r
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
```

- [ ] **Step 4b.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 4b.3: Commit**

```bash
git add tests/testthat/test-check_trends_preserved.R
git commit -m "$(cat <<'EOF'
Add unit tests for check_trends_preserved.

Cover return shape, perfect-match median, ntime <= 10 short-circuit
(n_sampled == 0, median is NA), sd == 0 skip path, and the
n_samples early-exit behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 4c: Wiring-check swap

- [ ] **Step 4c.1: Edit `tests/testthat/test-test_scaling.R`**

REMOVE these two harness tests:
- `test_that("trends-preserved fails under relative when scaled is constant in time", ...)`
- `test_that("trends-preserved under lambda does NOT assert, only prints", ...)`

KEEP the short-ntime test (`"trends-preserved: on ntime<=10 fixture, no cells sampled, block still passes"`) — it's a relevant integration invariant.

ADD wiring tests:

```r
test_that("test_scaling calls check_trends_preserved with scaled_data and timeseries", {
  fx <- make_test_scaling_fixture()
  captured <- list()
  local_mocked_globals(
    check_trends_preserved = function(scaled_data, timeseries, ...) {
      captured <<- list(scaled_data = scaled_data, timeseries = timeseries)
      list(n_sampled = 50, median_correlation = 0.99)  # valid pass
    }
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_equal(captured$scaled_data, fx$scaled_data)
  expect_equal(captured$timeseries, fx$timeseries)
  expect_equal(r$n_failures, 0)
})

test_that("test_scaling under lambda prints median correlation when n_sampled > 0", {
  fx <- make_test_scaling_fixture()
  local_mocked_globals(
    check_trends_preserved = function(scaled_data, timeseries, ...) {
      list(n_sampled = 50, median_correlation = 0.7777)
    }
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "lambda")
  expect_true(any(grepl("Median trend correlation \\(lambda method\\): 0\\.7777",
                        r$output)))
  expect_equal(r$n_failures, 0)
})
```

- [ ] **Step 4c.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 4c.3: Commit**

```bash
git add tests/testthat/test-test_scaling.R
git commit -m "$(cat <<'EOF'
Swap duplicated trends tests for wiring checks.

Behavior of check_trends_preserved is now covered by its own file.
The harness retains the short-ntime integration invariant and adds
two wiring checks: one for the relative branch's expect_true path,
one for the lambda branch's cat() path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 4 reviewer cycle

Same pattern: spec reviewer + code quality reviewer.

---

## Task 5: Extract `check_relative_changes_applied`

### Sub-task 5a: Extract helper + update caller

- [ ] **Step 5a.1: Add `check_relative_changes_applied` after `check_trends_preserved`**

```r
# ============================================================================
# FUNCTION: check_relative_changes_applied
# ============================================================================
# Sample up to max_attempts cells searching for one with a full valid time
# series (sum(!is.na(ts_orig)) == ntime, non-NA base-year value). On success,
# computes expected vs. actual scaled values at n_timesteps evenly-spaced
# time steps. Returns list(found, checks) where checks is a list of
# list(t, expected, actual). The caller applies the tolerance.
# ============================================================================
check_relative_changes_applied <- function(scaled_data, timeseries, base_rate,
                                           base_idx,
                                           n_timesteps = 3,
                                           max_attempts = 1000) {
  nlon <- dim(scaled_data)[1]
  nlat <- dim(scaled_data)[2]
  ntime <- dim(scaled_data)[3]

  checks <- list()
  found <- FALSE

  # n_timesteps=3 preserves the original c(1, ntime %/% 2, ntime) choice.
  timestep_indices <- unique(c(1, ntime %/% 2, ntime))
  if (length(timestep_indices) > n_timesteps) {
    timestep_indices <- timestep_indices[1:n_timesteps]
  }

  for (attempt in 1:max_attempts) {
    i <- sample(1:nlon, 1)
    j <- sample(1:nlat, 1)

    ts_orig <- timeseries[i, j, ]
    ts_scaled <- scaled_data[i, j, ]

    if (!is.na(base_rate[i, j]) && base_rate[i, j] > 0 &&
        !is.na(ts_orig[base_idx]) && ts_orig[base_idx] > 0 &&
        sum(!is.na(ts_orig)) == ntime) {

      for (t in timestep_indices) {
        rel_change <- ts_orig[t] / ts_orig[base_idx]
        expected <- base_rate[i, j] * rel_change
        checks[[length(checks) + 1]] <- list(
          t = t, expected = expected, actual = ts_scaled[t]
        )
      }

      found <- TRUE
      break
    }
  }

  list(found = found, checks = checks)
}
```

- [ ] **Step 5a.2: Update `test_scaling`'s relative-changes block**

Replace:

```r
  # Test relative changes only for relative method
  if (method == "relative") {
    test_that("Relative changes are correctly applied", {
    # Pick a cell with valid data throughout
    nlon <- dim(scaled_data)[1]
    nlat <- dim(scaled_data)[2]
    ntime <- dim(scaled_data)[3]
    
    found <- FALSE
    for (attempt in 1:1000) {
      i <- sample(1:nlon, 1)
      j <- sample(1:nlat, 1)
      
      # timeseries is [lon, lat, time]
      ts_orig <- timeseries[i, j, ]
      ts_scaled <- scaled_data[i, j, ]
      
      if (!is.na(base_rate[i, j]) && base_rate[i, j] > 0 &&
          !is.na(ts_orig[base_idx]) && ts_orig[base_idx] > 0 &&
          sum(!is.na(ts_orig)) == ntime) {
        
        # Calculate expected scaling for a few time steps
        for (t in c(1, ntime %/% 2, ntime)) {
          rel_change <- ts_orig[t] / ts_orig[base_idx]
          expected <- base_rate[i, j] * rel_change
          
          # Should match within numerical precision
          expect_equal(ts_scaled[t], expected, tolerance = 1e-5)
        }
        
        found <- TRUE
        break
      }
    }
    
    # Report if we couldn't find suitable test cell
    if (!found) {
      warning("Could not find suitable cell for relative change test")
    }
    })
  }  # End of method == "relative" conditional
```

with:

```r
  # Test relative changes only for relative method
  if (method == "relative") {
    rel <- check_relative_changes_applied(scaled_data, timeseries, base_rate, base_idx)
    test_that("Relative changes are correctly applied", {
      if (rel$found) {
        for (check in rel$checks) {
          expect_equal(check$actual, check$expected, tolerance = 1e-5)
        }
      } else {
        warning("Could not find suitable cell for relative change test")
      }
    })
  }  # End of method == "relative" conditional
```

- [ ] **Step 5a.3: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 5a.4: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract check_relative_changes_applied from test_scaling.

Move the cell-sampling and expected-vs-actual computation into a
pure helper. Caller iterates over the returned checks and applies
the existing 1e-5 tolerance. The "no suitable cell" warning is
preserved verbatim at the caller.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 5b: Per-helper tests

- [ ] **Step 5b.1: Create `tests/testthat/test-check_relative_changes_applied.R`**

```r
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

test_that("found=FALSE when base_rate is all NA or zero", {
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
```

- [ ] **Step 5b.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 5b.3: Commit**

```bash
git add tests/testthat/test-check_relative_changes_applied.R
git commit -m "$(cat <<'EOF'
Add unit tests for check_relative_changes_applied.

Cover return shape, found=TRUE on good fixture with every check's
expected matching actual, found=FALSE when every cell is broken,
found=FALSE when base_rate is all invalid, and the incorrect-scaling
detection path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Sub-task 5c: Wiring-check swap

- [ ] **Step 5c.1: Edit `tests/testthat/test-test_scaling.R`**

REMOVE these two harness tests:
- `test_that("relative-changes fails when scaling is off by a factor", ...)`
- `test_that("relative-changes warns when no suitable cell is found", ...)`

ADD wiring tests:

```r
test_that("test_scaling calls check_relative_changes_applied with all four args (relative)", {
  fx <- make_test_scaling_fixture()
  captured <- list()
  local_mocked_globals(
    check_relative_changes_applied = function(scaled_data, timeseries, base_rate,
                                              base_idx, ...) {
      captured <<- list(
        scaled_data = scaled_data,
        timeseries  = timeseries,
        base_rate   = base_rate,
        base_idx    = base_idx
      )
      list(found = TRUE, checks = list())  # empty checks → no expect_* fires
    }
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_equal(captured$scaled_data, fx$scaled_data)
  expect_equal(captured$timeseries, fx$timeseries)
  expect_equal(captured$base_rate, fx$base_rate)
  expect_equal(captured$base_idx, fx$base_year - fx$start_year + 1)
  expect_equal(r$n_failures, 0)
})

test_that("test_scaling does NOT call check_relative_changes_applied under lambda", {
  fx <- make_test_scaling_fixture()
  call_count <- 0
  local_mocked_globals(
    check_relative_changes_applied = function(...) {
      call_count <<- call_count + 1
      list(found = TRUE, checks = list())
    }
  )
  run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                           fx$start_year, fx$base_year, method = "lambda")
  expect_equal(call_count, 0)
})

test_that("test_scaling warns when check_relative_changes_applied returns found=FALSE", {
  fx <- make_test_scaling_fixture()
  local_mocked_globals(
    check_relative_changes_applied = function(...) {
      list(found = FALSE, checks = list())
    }
  )
  r <- run_test_scaling_capture(fx$scaled_data, fx$timeseries, fx$base_rate,
                                fx$start_year, fx$base_year, method = "relative")
  expect_true(any(grepl("Could not find suitable cell for relative change test",
                        r$warnings)))
})
```

- [ ] **Step 5c.2: Run tests**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL.

- [ ] **Step 5c.3: Commit**

```bash
git add tests/testthat/test-test_scaling.R
git commit -m "$(cat <<'EOF'
Swap duplicated relative-changes tests for wiring checks.

Behavior now lives in test-check_relative_changes_applied.R. The
harness adds three wiring tests: arg forwarding for relative, no-call
confirmation for lambda, and the warning path when found=FALSE.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5 reviewer cycle

Same pattern.

---

## Task 6: Final cleanup

**Files:**
- Modify: `fertilizer_scaling_functions.R` (tidy the now-thin `test_scaling`)
- Modify (maybe): `tests/testthat/test-test_scaling.R` (header comment refresh if stale)

- [ ] **Step 6.1: Re-read the refactored `test_scaling`**

It should now look approximately like:

```r
test_scaling <- function(scaled_data, timeseries, base_rate, start_year, base_year, method = "relative") {

  base_idx <- base_year - start_year + 1

  # Test 1: Base year match - only applies to relative method
  bym <- check_base_year_match(scaled_data, base_rate, base_idx)
  if (method == "relative") {
    test_that("Scaled data at base year matches original pattern (relative method)", {
      if (bym$n_valid > 0) {
        expect_true(bym$correlation > 0.99)
      }
    })
  } else {
    cat(sprintf("\n=== Lambda Method Validation ===\n"))
    if (bym$n_valid > 0) {
      cat(sprintf("Base year spatial correlation: %.4f\n", bym$correlation))
      cat(sprintf("Note: Lambda method doesn't preserve exact base year values\n"))
    }
  }

  test_that("No negative values introduced by scaling", {
    expect_true(check_no_negatives(scaled_data))
  })

  trends <- check_trends_preserved(scaled_data, timeseries)
  test_that("Trends are preserved from time series", {
    if (trends$n_sampled > 0) {
      if (method == "relative") {
        expect_true(trends$median_correlation > 0.95)
      } else {
        cat(sprintf("Median trend correlation (lambda method): %.4f\n",
                    trends$median_correlation))
      }
    }
  })

  # Test relative changes only for relative method
  if (method == "relative") {
    rel <- check_relative_changes_applied(scaled_data, timeseries, base_rate, base_idx)
    test_that("Relative changes are correctly applied", {
      if (rel$found) {
        for (check in rel$checks) {
          expect_equal(check$actual, check$expected, tolerance = 1e-5)
        }
      } else {
        warning("Could not find suitable cell for relative change test")
      }
    })
  }
}
```

Look for and fix:
- **Stale comments** referring to detail that's now inside helpers. E.g., "Sample some grid cells and check if trends match" — no longer relevant inside the orchestrator.
- **Unused locals**: check the orchestrator doesn't compute anything it doesn't use (e.g., `nlon`, `nlat`, `ntime`).
- **Dead blank lines.**

Target length: ~45 lines.

- [ ] **Step 6.2: Update the function's docstring (currently lines 311-329)**

Current docstring lists the 4 tests. After refactor, those are still conceptually the 4 checks — but the docstring could be trimmed to the public contract (args, return, which checks run per method). Do a light editorial pass; don't rewrite from scratch.

- [ ] **Step 6.3: Run the full suite**

Run: `Rscript tests/testthat.R`
Expected: 0 FAIL at the same count as post-Task-5.

- [ ] **Step 6.4: Commit**

```bash
git add fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Tidy test_scaling after modularization.

Remove stale inline comments, unused locals, and orphaned blank
lines that the helper extractions made obvious. No behavior changes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 6 reviewer cycle

Same pattern.

---

## Integration

After Task 6 passes both reviewers:

- [ ] **Step 7.1: Final full-branch review**

Dispatch a `superpowers:code-reviewer` on the entire branch (`git diff main`) as a sanity check. Focus on overall coherence, interface quality across the four helpers, and anything that doesn't feel right once you can see the whole diff.

- [ ] **Step 7.2: Invoke `superpowers:finishing-a-development-branch`**

Present merge / PR / keep / discard options to the user.

- [ ] **Step 7.3: On merge, clean up**

```bash
git worktree remove .worktrees/test-scaling-modularization
git branch -d feature/test-scaling-modularization
```

---

## Self-review

**Spec coverage.** Each item in the spec maps to a task:
- Decomposition (4 helpers) → Tasks 2–5, one per helper.
- Harness tests comprehensive → Task 1.
- Per-helper tests → Tasks 2b, 3b, 4b, 5b.
- Wiring verification → Tasks 2c, 3c, 4c, 5c.
- Writer → reviewer → commit cycle → "Execution workflow" at top of plan + per-task reviewer cycle notes.
- Approach 2 deferred → not in this plan (correctly scoped out).

**Placeholder scan.** No TBD/TODO/vague items. Every step has concrete code or a concrete command.

**Type consistency.** Helper signatures match between Task 2a extraction, Task 2b test usage, and Task 2c wiring mock (likewise for 3/4/5). The four return shapes used by the orchestrator match what's defined at extraction time:
- `check_base_year_match` → `list(n_valid, correlation)` ✓
- `check_no_negatives` → `logical` ✓
- `check_trends_preserved` → `list(n_sampled, median_correlation)` ✓
- `check_relative_changes_applied` → `list(found, checks)` where `checks[[k]] = list(t, expected, actual)` ✓

**Known caveat (flagged).** The Task 1 `run_test_scaling_capture` helper uses `reporter$get_results()`. If that specific method isn't in this testthat's `ListReporter` API, the implementer should inspect the reporter's available methods (`names(reporter)` or `methods(class="ListReporter")`) and adjust the one line that extracts results, keeping the helper's return shape unchanged. Step 1.2 notes this.
