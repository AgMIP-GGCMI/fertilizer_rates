---
title: Modularize scale_with_timeseries
date: 2026-04-19
status: draft
---

# Modularize `scale_with_timeseries`

## Goal

Break the 166-line `scale_with_timeseries` function in
`fertilizer_scaling_functions.R` (lines 93–258) into a small set of
focused helpers with their own unit tests, without changing observable
behavior. Lock current behavior down with a comprehensive harness-level
test suite before touching the function body.

## Scope

This is a **strict refactor**. No behavior changes — same outputs, same
warnings, same print text, same error on unknown method, same nested
loop structure in the lambda branch. Cleanup opportunities are tracked
under "Next steps" and are out of scope for this spec.

## Decomposition

`scale_with_timeseries` is split into the following helpers, all defined
in `fertilizer_scaling_functions.R`:

- `prepare_scaling_inputs(base_rate, timeseries, base_year, start_year, end_year)`
  — Validates that `base_year` is in range (raises the existing error
  otherwise) and returns `list(base_idx, base_timeseries, valid_base)`
  where `valid_base <- !is.na(base_rate) & is.finite(base_rate) & base_rate > 0`.

- `scale_relative_timestep(base_rate, ts_t, base_timeseries, valid_base)`
  — Returns a single `[lon, lat]` scaled slice for the relative method.
  Encapsulates the inner body of the relative `for (t in 1:ntimes)` loop.

- `compute_lambda(base_rate, base_timeseries, valid_base)` — Returns a
  per-cell `[lon, lat]` array. `1` everywhere except where
  `valid_base & base_timeseries > 0 & base_timeseries < base_rate`, in
  which case `sqrt(base_timeseries / base_rate)`. Called once before
  the lambda time loop. Preserves the current nested `for (i, j)` loop.

- `scale_lambda_timestep(base_rate, ts_t, base_timeseries, valid_base, lambda)`
  — Returns a single `[lon, lat]` scaled slice for the lambda method.
  Encapsulates the inner body of the lambda `for (t in 1:ntimes)` loop,
  including the existing `tryCatch` and non-negativity clamp.

- `diagnose_extreme_values(scaled_data, base_rate, base_timeseries, timeseries, start_year)`
  — The >1000 kg/ha warning block, unchanged.

After decomposition, `scale_with_timeseries` reduces to: print method,
call `prepare_scaling_inputs`, allocate output array, precompute
`lambda` if method is "lambda", loop over time steps dispatching to the
appropriate `scale_*_timestep`, call `diagnose_extreme_values`, return.
Expected length ~25 lines.

## Test strategy

### Fixtures

Small synthetic `[lon, lat, time]` arrays (e.g., 4×3×5) stamped with
known values. A single `make_ts_fixture()` helper lives at the top of
the new test file and is reused across all tests. No real NetCDF data.

### Harness-level tests for `scale_with_timeseries` (Step 1)

Added first, before any extraction. These lock down observable behavior
and run green against the current implementation:

- **Method dispatch**: unknown method raises
  `"Unknown scaling method: <x>"`; `"relative"` and `"lambda"` each
  return an array of shape `[nlon, nlat, ntimes]`.
- **Validation**: `base_year < start_year` and `base_year > end_year`
  both raise the existing out-of-range error message.
- **Relative semantics**:
  - Base-year slice matches `base_rate` at cells valid in both.
  - For sampled valid cells, `scaled[i,j,t] == base_rate[i,j] * ts[i,j,t] / ts[i,j,base_idx]`.
  - Cells where `base_rate` is NA / non-finite / ≤ 0 remain NA in output.
  - Cells where `base_timeseries` is NA / non-finite / ≤ 0 remain NA in output.
- **Lambda semantics**:
  - For cells where `ts_base < base_rate`, lambda equals `sqrt(ts_base / base_rate)`.
  - For cells where `ts_base >= base_rate`, lambda equals 1.
  - Output is clamped to ≥ 0.
  - Invalid cells remain NA.
- **Diagnostics**: a fixture that produces a value > 1000 triggers the
  warning block (captured via `expect_output` on the existing `print`
  calls) and does not stop execution.

### Per-helper tests

Each helper gets its own `test-<helper>.R` file added alongside
`test-aggregate_to_halfdegree.R`. Coverage:

- `prepare_scaling_inputs`: returns correct `base_idx`, correct
  `valid_base` mask (NA, non-finite, ≤ 0 all masked out), correct
  `base_timeseries` slice; raises on out-of-range `base_year`.
- `scale_relative_timestep`: known input → known output; invalid cells
  remain NA; division-by-zero at `base_timeseries == 0` is masked out.
- `compute_lambda`: 1 everywhere by default; `sqrt(ts/base)` where
  `ts < base`; 1 where `ts >= base`; invalid cells unaffected.
- `scale_lambda_timestep`: known input → known output (using lambda
  from `compute_lambda`); non-negativity clamp works; invalid cells
  remain NA.
- `diagnose_extreme_values`: doesn't alter input; prints the warning
  when max > 1000; silent otherwise.

### Wiring verification

Immediately after extracting each helper, the harness-level tests that
overlap with that helper's behavior are replaced by
`testthat::local_mocked_bindings()` checks that verify
`scale_with_timeseries` calls the helper with the expected arguments
and forwards its return value correctly. This keeps tests focused:
behavior is verified in the helper's own test file, wiring is verified
at the harness level.

## Execution plan

Every numbered step is one commit. The suite stays green after every
commit. Each step uses an explicit writer → reviewer → commit cycle:

- A **code-writing agent** implements the step.
- A **code-reviewing agent** reviews the diff against this spec and
  this project's conventions.
- Commit **only** after the reviewer approves. If the reviewer flags
  issues, the writer addresses them and the reviewer re-reviews. No
  commits without approval.

### Step 1: Harness-level test suite

1. Create `tests/testthat/test-scale_with_timeseries.R` covering the
   harness-level tests listed above.
2. Run the full test suite; confirm all pass against the unchanged
   function.
3. Reviewer confirms coverage matches the spec.
4. Commit.

**Checkpoint: pause here for user approval before proceeding.**

### Steps 2–6: Extract helpers

Steps 2–6 proceed sequentially without further user approval, but each
keeps the writer/reviewer/commit cadence. Each helper follows the same
sub-pattern, each sub-step committed individually:

1. Extract the helper into `fertilizer_scaling_functions.R`; update
   `scale_with_timeseries` to call it. Writer → reviewer → commit.
2. Add `tests/testthat/test-<helper>.R` with the per-helper tests
   described above. Writer → reviewer → commit.
3. Replace the now-duplicated harness-level tests with
   `local_mocked_bindings()` wiring checks. Writer → reviewer → commit.

Helper order (chosen so each extraction strictly shrinks
`scale_with_timeseries` and doesn't depend on not-yet-extracted code):

- Step 2: `prepare_scaling_inputs`
- Step 3: `scale_relative_timestep`
- Step 4: `compute_lambda`
- Step 5: `scale_lambda_timestep`
- Step 6: `diagnose_extreme_values`

### Step 7: Final cleanup

1. Re-read the now-thin `scale_with_timeseries` and tidy any leftover
   comments, dead locals, or redundant allocations that the extractions
   made obvious. No behavior changes.
2. Reviewer confirms `scale_with_timeseries` is as thin as the design
   intends (~25 lines) and matches this spec.
3. Commit.

## Next steps (out of scope)

Deferred cleanups to tackle after this lands:

- **Vectorize the lambda path.** `compute_lambda` and
  `scale_lambda_timestep` currently use nested `for (i, j)` loops. The
  relative path is vectorized; making the two branches consistent
  should be a mechanical follow-up once the helpers are in place.
- **Migrate logging.** Replace `print(paste(...))` status output with
  `message()`, and route the >1000 kg/ha diagnostic through `warning()`
  instead of `print()`. This is idiomatic R and lets users suppress it.
- **Reconsider the diagnostic's placement.** The extreme-values warning
  arguably belongs in a separate helper that callers invoke
  explicitly, not inside the scaling function. Worth revisiting once
  call sites are cleaner.

## Non-goals

- No performance work beyond what falls out naturally from the split.
- No interface changes to `scale_with_timeseries`: same arg names,
  same defaults, same return value.
- No changes to callers (`fertilizer_scaling.R` and friends).
