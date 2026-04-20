---
title: Modularize test_scaling
date: 2026-04-20
status: draft
---

# Modularize `test_scaling`

## Goal

Break the ~125-line `test_scaling` function in
`fertilizer_scaling_functions.R` (lines 330–454) into four focused
check helpers with their own unit tests, without changing observable
behavior. Lock current behavior down with a comprehensive harness-level
test suite before touching the function body.

## Scope

This is a **strict refactor**. No behavior changes — the orchestrator
continues to fire `test_that` / `expect_*` blocks with the same text,
same order, same thresholds (0.99 base-year correlation, 0.95 trend
correlation, 1e-5 relative-change tolerance). The method-specific
branching (assert vs. `cat()` informational) is preserved verbatim.

The "testthat-as-runtime-assertion-framework" design debt is tracked
under "Next steps" and is out of scope for this spec.

## Decomposition

`test_scaling` is split into four pure check helpers, each returning a
structured value. The orchestrator calls them and wraps the returned
values in `test_that` / `expect_*` for the relative method or in
`cat()` informational output for the lambda method.

- `check_base_year_match(scaled_data, base_rate, base_idx)` —
  computes the correlation between `scaled_data[, , base_idx]` and
  `base_rate` across cells valid in both. Returns
  `list(n_valid = integer, correlation = numeric_or_NA)`. When
  `n_valid == 0`, `correlation` is `NA`.

- `check_no_negatives(scaled_data)` — returns `logical`: `TRUE` when
  `all(scaled_data >= 0 | is.na(scaled_data))`.

- `check_trends_preserved(scaled_data, timeseries, n_samples = 100, max_attempts = 1000)`
  — samples up to `n_samples` cells (attempting up to `max_attempts`
  times, mirroring the current code) and returns
  `list(n_sampled = integer, median_correlation = numeric_or_NA)`.
  Preserves the existing `sample()` usage (non-deterministic by
  default) so behavior is identical.

- `check_relative_changes_applied(scaled_data, timeseries, base_rate, base_idx, n_timesteps = 3, max_attempts = 1000)`
  — searches for a cell with a full valid time series (up to
  `max_attempts` sample attempts), then computes expected vs. actual
  scaled values at `n_timesteps` evenly-spaced time steps. Returns
  `list(found = logical, checks = list(t, expected, actual))`. The
  comparison tolerance (1e-5) is applied by the orchestrator.

After decomposition, `test_scaling` reduces to ~45 lines: compute
`base_idx`, call each helper, wrap return values in the appropriate
`test_that` / `expect_*` or `cat()` branch per method. All existing
`test_that` block titles, assertion text, tolerances, and method-branch
behavior are preserved.

## Test strategy

### Fixtures

Small synthetic `[lon, lat, time]` arrays. A `make_test_scaling_fixture()`
helper at the top of the new test file provides a good-input baseline.
Fixture shape must satisfy the existing sampler thresholds: the
trends-preserved check requires `sum(!is.na(ts_cell)) > 10` to count a
cell, so `ntime >= 12` (and a fixture like 3×3×12 with all cells valid
works well). Individual tests mutate copies of the fixture to exercise
specific bad-input paths (negative values, broken trends, wrong
scaling, no-valid-cell). A short-`ntime` fixture (e.g., `ntime = 5`)
is a convenient way to exercise the "no cell has > 10 valid time
points" branch of `check_trends_preserved`.

Determinism strategy: rely on fixture construction — fixtures where
**all** cells are valid (sampler succeeds on attempt 1) or where
**no** cells are valid (sampler exhausts `max_attempts`). Both
outcomes are stable without seed manipulation. For the one case that
needs a middle ground, wrap in `withr::with_seed()`.

### Harness-level tests for `test_scaling` (Task 1)

Added first, before any extraction. These lock down observable
behavior and run green against the current implementation. Captured
via `testthat::ListReporter` + `testthat::with_reporter()` so inner
`test_that` outcomes can be inspected without polluting the outer
runner's output.

Coverage:

- **Method dispatch**: on a good relative fixture, exactly 4 inner
  `test_that` blocks fire and all pass. On a good lambda fixture,
  exactly 2 fire and pass, plus the `"=== Lambda Method Validation ==="`
  header and the correlation+note lines appear in captured output.
- **Base-year match (relative)**: good fixture → inner block passes.
  Fixture where `scaled_data[, , base_idx]` diverges from `base_rate`
  (correlation < 0.99) → inner block fails.
- **Base-year match (lambda)**: produces the validation header and
  `"Base year spatial correlation: %.4f"` + note lines; does not
  fire an inner `test_that`.
- **No-negatives**: good fixture → passes; fixture with an injected
  negative value → fails.
- **Trends preserved (relative)**: good fixture → passes; fixture
  with broken trends (e.g., `scaled_data` constant while `timeseries`
  varies) → fails.
- **Trends preserved (lambda)**: prints
  `"Median trend correlation (lambda method): %.4f"`; does not
  assert.
- **Relative changes (relative)**: good fixture → passes; fixture
  where the scaling formula is deliberately wrong (e.g., `scaled` is
  2× the correct value) → inner `expect_equal` fails.
- **No-suitable-cell path**: fixture where no cell has a full valid
  time series → relative-changes block raises
  `warning("Could not find suitable cell for relative change test")`.

### Per-helper tests

Each helper gets its own `test-<helper>.R` file added alongside the
existing test files. Coverage:

- `check_base_year_match`: return-value shape; correlation matches
  hand-computed value on known inputs; `n_valid == 0` when all cells
  are NA in at least one side; `correlation == NA` when `n_valid == 0`.
- `check_no_negatives`: `TRUE` on all-non-negative input; `TRUE` when
  some cells are NA but non-NA cells are non-negative; `FALSE` when
  any non-NA cell is negative.
- `check_trends_preserved`: returns median correlation matching
  hand-computed value on a small fixture where all cells are valid;
  `median_correlation == NA` and `n_sampled == 0` when no cells have
  enough valid time points.
- `check_relative_changes_applied`: `found = TRUE` and `checks`
  contains the expected (t, expected, actual) triples on a good
  fixture; `found = FALSE` when no cell has a full valid time series.

### Wiring verification

Immediately after extracting each helper, the harness-level tests that
overlap with that helper's behavior are replaced by `local_mocked_globals`
wiring checks. Each wiring check verifies that `test_scaling` calls the
helper with the expected arguments and forwards its return value into
the correct branch (`expect_*` for relative, `cat()` for lambda).

## Execution plan

Every numbered step is one commit. The suite stays green after every
commit. Each step uses an explicit writer → reviewer → commit cycle
driven by subagents (matching the pattern established in the
`scale_with_timeseries` refactor):

### Writer → reviewer → commit cycle

For each step below:

1. **Writer subagent.** Dispatch a `general-purpose` agent (typically
   Sonnet) with the full task text, the working directory (the
   worktree), and explicit instructions on what to change, what not
   to touch, and how to verify (test commands + expected counts).
   The writer implements the step, runs tests, and commits with the
   standardised commit message.
2. **Spec reviewer subagent.** Dispatch a fresh `general-purpose`
   agent to verify the diff against this spec's requirements.
   Independently reads the new/changed files, runs the suite, and
   (for source-changing commits) runs a byte-identity check pre/post
   to confirm observable behavior is unchanged. Reports ✅ spec
   compliant or ❌ with file:line references.
3. **Code quality reviewer subagent.** Dispatch
   `superpowers:code-reviewer` on the same diff. Focuses on idiomatic
   style, naming, test clarity, and anything the spec reviewer's
   correctness focus might miss. Reports Strengths / Issues by
   severity / Assessment.
4. **Fixes if needed.** If either reviewer flags a blocking issue,
   dispatch another writer subagent (may be a lighter model like
   Haiku for tightly-scoped cleanup) to address the finding. Re-run
   the spec and/or code quality reviewer as applicable before
   committing the fix. No commit lands without reviewer approval on
   its own diff.
5. **Commit only after both reviewers approve.** Minor suggestions
   that don't block ("nice-to-have", "minor") can be deferred to a
   final cleanup pass; important/critical issues must be addressed
   before the step is considered complete.

This cycle runs for **every** sub-commit, including the final cleanup
task. No silent self-review.

### Environment setup (Step 0, before Task 1)

- Create a dedicated worktree + branch (via
  `superpowers:using-git-worktrees`): something like
  `feature/test-scaling-modularization` in
  `.worktrees/test-scaling-modularization`. All Task 1-6 work happens
  there; main stays untouched until the final merge.
- Verify the worktree's baseline passes: `Rscript tests/testthat.R`
  should report 128 PASS, 0 FAIL before any changes.

### Task 1: Harness-level test suite for `test_scaling` (CHECKPOINT)

1. Create `tests/testthat/test-test_scaling.R` with the comprehensive
   harness tests listed in "Test strategy" above (method dispatch,
   each invariant × good + bad fixtures, no-suitable-cell path).
   Use `testthat::ListReporter` + `testthat::with_reporter()` to
   inspect inner `test_that` outcomes.
2. Run the full suite; confirm all existing tests still pass and the
   new ones pass against the unchanged `test_scaling`.
3. Writer → spec reviewer → code quality reviewer → commit (per the
   cycle above).

**Checkpoint: pause here for user approval before proceeding to Task 2.**

### Tasks 2–5: Extract helpers

Tasks 2–5 proceed sequentially without further user approval, but
each keeps the writer/reviewer/commit cadence. Each helper follows
the same three-sub-commit pattern, each sub-commit fully cycled
through the writer → reviewer → commit process:

1. **Extract + wire.** Add the helper to
   `fertilizer_scaling_functions.R`; update `test_scaling` to call it
   and wrap its return value in the existing `test_that`/`expect_*`
   or `cat()` branches. No behavior change.
2. **Per-helper tests.** Add `tests/testthat/test-<helper>.R` with
   the per-helper tests described above.
3. **Wiring-check swap.** Replace the now-duplicated harness-level
   tests with `local_mocked_globals` wiring checks. The mock verifies
   `test_scaling` calls the helper with the right args and uses its
   return value correctly.

Helper order (chosen so each extraction strictly shrinks `test_scaling`
without depending on later extractions):

- Task 2: `check_base_year_match`
- Task 3: `check_no_negatives`
- Task 4: `check_trends_preserved`
- Task 5: `check_relative_changes_applied`

### Task 6: Final cleanup

1. Re-read the now-thin `test_scaling` and tidy leftover comments,
   dead locals, or redundant dispatch logic that the extractions
   made obvious. No behavior changes.
2. Writer → both reviewers → commit.
3. Confirm `test_scaling` is ~45 lines and reads cleanly: compute
   `base_idx`, call each helper, dispatch per method.

### Integration (after Task 6)

- Invoke `superpowers:finishing-a-development-branch` to present
  merge / PR / keep / discard options and execute the chosen path.
- On merge to main, remove the worktree.

## Next steps (out of scope)

Deferred cleanup to tackle after this lands:

- **Redesign as `validate_scaling` (Approach 2).** Rename
  `test_scaling` → `validate_scaling`, drop `test_that` / `expect_*`
  from the function body, return a structured result like
  `list(checks = list(base_year_match = list(ok, correlation), no_negatives = list(ok), trends_preserved = list(ok, median_cor), relative_changes = list(ok, details)))`.
  Caller in `main()` prints a summary and optionally `stop()`s on
  failure. Tests become ordinary value-comparison tests — no
  reporter capture, no nested `test_that`. This fixes the design
  debt of using testthat as a runtime assertion framework in
  production code. Estimated 4–6 commits on top of this plan's final
  state.

## Non-goals

- No performance work. The sampling logic (up to 1000 attempts to
  find 100 cells) stays as-is even though it's a hot-spot candidate.
- No interface changes to `test_scaling`: same arg names, defaults,
  and return value (invisible NULL).
- No changes to the caller (`main()` in `fertilizer_scaling_functions.R`).
- No migration from `test_that`/`expect_*` to any alternative
  assertion API — that's Approach 2, explicitly deferred.
