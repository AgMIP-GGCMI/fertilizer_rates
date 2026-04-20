---
title: Refactor plot_diagnostics
date: 2026-04-20
status: draft
---

# Refactor `plot_diagnostics`

## Goal

Break the ~647-line `plot_diagnostics` function in
`fertilizer_scaling_functions.R` (lines 540–1186) into a set of focused
top-level functions in a new file,
`fertilizer_scaling_plot_diagnostics_functions.R`, without changing the
rendered diagnostic PDFs at all. After the refactor, `plot_diagnostics`
itself remains the public entry point in `fertilizer_scaling_functions.R`
but is reduced to a short orchestrator (~30–50 lines) that wires the
extracted pieces together.

## Scope

This is a **strict refactor**. No visual changes: every diagnostic PDF
produced for a given input must be pixel-identical before and after.
Same console `print`/`cat` output, same `par()` state transitions, same
plot order, same legend text, same filename logic. Cleanup
opportunities (renames, comment pruning, migrating `print` → `message`,
etc.) are explicitly out of scope.

The two vestigial scripts `run_diagnostics_external.R` (which embeds
its own drifted copy of `plot_diagnostics`) and `compare_histsoc_future.R`
are **not** touched by this refactor. De-duplicating them is a separate
follow-up.

## Decomposition

All extracted functions live in the new file
`fertilizer_scaling_plot_diagnostics_functions.R`, sourced from
`fertilizer_scaling_functions.R`. All are top-level — no nested
closures. Closures in the original (`plot_map`, `add_sample_markers`)
are promoted and receive their previously-captured variables as
explicit arguments.

### Helpers

- `build_sample_locations()` — Returns the 10-row data frame of sample
  lat/lon/description values. Currently defined inline starting at
  line 572.
- `add_sample_markers(lon, lat, sample_locations)` — Promotes the
  closure at line 587. Draws the numbered circle markers on the
  currently-active map.
- `plot_map(lon, lat, data, title, diverging = FALSE, add_markers = TRUE, sample_locations = NULL)`
  — Promotes the closure at line 607. When `add_markers = TRUE`,
  `sample_locations` must be supplied; the function calls
  `add_sample_markers` internally.

### Plot-section functions

Each section function assumes the PDF device is already open and the
appropriate `par()` layout has been set by the caller. Each produces
plots on that device and returns invisibly.

- `plot_aggregation_comparison(base_rate, spatial_data_5min, lon, lat, lon_5min, lat_5min, crop)`
  — The optional 4-panel aggregation-comparison page (lines 651–723).
  Sets `par(mfrow = c(2, 2), ...)` on entry and resets to
  `par(mfrow = c(4, 3), ...)` on exit, exactly as the current code does.
- `plot_pattern_maps(base_rate, scaled_data, lon, lat, sample_locations, start_year, end_year, mid_idx, crop, method)`
  — Plots 1–5: original pattern, scaled first/middle/last, and the
  last–first difference map (lines 725–748).
- `plot_base_year_scatter(base_rate, scaled_data, base_idx, base_year, crop)`
  — Plot 6 (lines 750–780).
- `plot_relative_change_hist(scaled_data, base_idx, base_year, end_year, crop)`
  — Plot 7 (lines 782–804).
- `plot_spatial_ts_ratio(base_rate, timeseries, base_idx, lon, lat, sample_locations, crop)`
  — Plot 8 including the `print("Base/TS mismatch: ...")` diagnostic
  (lines 806–856).
- `plot_sample_timeseries(base_rate, scaled_data, timeseries, lon, lat, start_year, end_year, sample_locations, crop)`
  — Plot 9, including the coordinate-system comment block at lines
  863–896 and the `j_ts = length(lat) - j + 1` flip logic (lines
  858–984).
- `plot_distribution_histograms(base_rate, scaled_data, timeseries, base_idx, base_year, end_year, crop)`
  — Plots 10–12 (lines 986–1051). Grouped because they share no
  intermediate state but are conceptually "three overlay histograms of
  distributions and changes."
- `plot_outlier_scatter(base_rate, scaled_data, timeseries, base_idx, base_year, end_year)`
  — Plots 13–14 (lines 1053–1181). Kept together because Plot 14
  reuses `sf_valid`, `fv_valid`, `valid_mask`, and `is_outlier`
  computed in Plot 13, and also retains the `cat(...)` console output.

### What stays in `plot_diagnostics`

The slim `plot_diagnostics` retains:

1. Output-path construction (`plot_file <- paste0(...)` branch on
   `scenario == "histsoc"` vs future).
2. `pdf(plot_file, width = 16, height = 14)` / `dev.off()`.
3. Computation of `ntime`, `mid_idx`, `base_idx`, `valid_rel_count`.
4. The `sample_locations <- build_sample_locations()` call.
5. Initial `par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))`.
6. Conditional call to `plot_aggregation_comparison` when
   `spatial_data_5min` is non-NULL.
7. Sequential calls to the nine plot-section functions in the same
   order as the current plot numbering.

Expected length: ~30–50 lines.

## Plot-preservation verification

The correctness bar for this refactor is: **every diagnostic PDF is
pixel-identical** before and after. Verification happens after every
extraction commit, not just at the end.

### Reference invocations

Two runs cover both filename branches (`histsoc` vs future) and both
code paths for the aggregation-comparison block:

- `Rscript fertilizer_scaling.R mai histsoc`
- `Rscript fertilizer_scaling.R mai ssp126 image gfdl-esm4`

Both produce PDFs under `data/outputs/`.

### Rendering approach: shadow `pdf` with `png`

This devcontainer has no PDF rasterizer available (no `pdftoppm`,
`gs`, ImageMagick, Python `pdf2image`, or R `pdftools` — the last
needs `libpoppler-cpp-dev` at the OS level, which can't be installed
without sudo). Rather than trying to work around that, the
verification harness bypasses PDF entirely and renders each plot
directly to PNG via R's built-in cairo-backed `png()` device.

The harness is a small R wrapper script that:

1. Defines a top-level `pdf` function that shadows `grDevices::pdf`.
   The shadow forwards to `grDevices::png` with
   `type = "cairo"`, an `%03d`-numbered filename (R's multi-page PNG
   pattern), and width/height converted from PDF inches to pixels at a
   fixed DPI.
2. Sources `fertilizer_scaling_functions.R` and invokes `main()` for
   each reference scenario.
3. Writes all PNG pages into a designated output directory.

Because the refactor is strict — same draw calls, same order — the
resulting PNGs must be byte-identical before and after. This is
actually a stronger check than pixel comparison of rasterized PDFs,
since no rasterizer sits between the draw calls and the pixels to
potentially mask differences.

### Baseline capture

Before any refactor work:

1. On `main`, run both reference invocations through the PNG harness.
2. Stash the PNGs under `data/plot-refactor-baseline/` — `data/` is
   already in `.gitignore`, so this directory is transparent to git.
3. Record a manifest: `find data/plot-refactor-baseline -name '*.png' -print0 | sort -z | xargs -0 md5sum > data/plot-refactor-baseline/manifest.md5`.

### Per-step check

After each extraction commit:

1. Re-run both reference invocations through the same PNG harness into
   a sibling directory, e.g. `data/plot-refactor-current/`.
2. Generate the same manifest: `find data/plot-refactor-current -name '*.png' -print0 | sort -z | xargs -0 md5sum`.
3. `diff` the two manifests. Any difference fails the step. The
   reviewer does not approve the commit until the manifests match
   exactly. If the check fails, the writer either fixes the extraction
   or reverts it before proceeding.

### Step 0 sanity check (precondition)

Before doing any extraction, prove the PNG harness is deterministic:
run it twice against unchanged `main` code and confirm the two
manifests are identical. If that check fails, the rest of the
verification plan is unreliable. The fallback in that case is a
`trace()`-based approach that logs the arguments of every graphics
function call (`plot`, `lines`, `hist`, `image.plot`, `legend`,
`text`, `abline`, `par`, `points`, `axis`, etc.) to a file, then diffs
those logs before and after. That replaces PNG hashing with call-log
hashing — same idea at a different level of the graphics stack.

### Risks and determinism notes

- **Closure promotion is the highest-risk change.** `plot_map` closes
  over `lon`, `lat`, and (indirectly via `add_sample_markers`)
  `sample_locations`. A mismatch between the promoted signature and a
  call site can produce subtly different maps (wrong marker positions,
  wrong color scaling). The first extraction step isolates exactly
  this change so any regression is localized.
- **`par()` state is global.** `plot_aggregation_comparison` sets
  `mfrow = c(2, 2)` on entry and must reset to `mfrow = c(4, 3)` on
  exit, matching the current code exactly. Tested by the PNG diff.
- **No random state is introduced.** None of the extracted code uses
  `sample()`, `runif()`, or similar, so results are deterministic
  given the same inputs.

## Execution plan

Work happens on a dedicated git worktree, not on `main`. The worktree
is created once at the start of Step 1 and merged back with a
no-fast-forward merge at the end so the feature branch's commit
grouping is preserved.

Every numbered step is at least one commit; logically distinct changes
within a step are split into separate commits. The suite stays green
(and the PNG diff stays clean) after every commit.

Each step uses an explicit **subagent-driven writer → reviewer →
commit cycle**:

- A **code-writing subagent** implements the step.
- A **code-reviewing subagent** reviews the diff against this spec,
  confirms the PNG manifest matches the baseline exactly, and
  checks project conventions.
- Commit **only** after the reviewer approves. If the reviewer flags
  issues, the writer addresses them and the reviewer re-reviews. No
  commits without approval.

Chunk sizing: each extraction is a reasonably-sized chunk — one helper
or one plot-section function per extraction commit. Do not batch
multiple extractions into one commit.

### Step 1: Worktree, harness, baseline

1. Create a git worktree for the refactor branch.
2. Write the PNG harness script (call it
   `tools/render_diagnostics_png.R` or similar — place it wherever
   fits the project's convention). The script:
   - Accepts the same positional args as `fertilizer_scaling.R` plus
     an output directory.
   - Defines the `pdf`-shadow function described above.
   - Sources `fertilizer_scaling_functions.R` and calls `main()`.
3. Run the Step 0 sanity check: invoke the harness twice against
   unchanged code, `diff` the two manifests, confirm they match. If
   they don't, stop and switch to the `trace()`-based fallback before
   proceeding.
4. Generate the baseline: run both reference invocations on unchanged
   code, store PNGs under `data/plot-refactor-baseline/`, record the
   baseline manifest.
5. Commit the harness script (it's new code and lives in-tree); the
   baseline PNGs do not go into git (they're under the ignored
   `data/`).

### Step 2: Create the new file and wire the first helper

1. Create `fertilizer_scaling_plot_diagnostics_functions.R`.
2. Extract `build_sample_locations` into it.
3. Add `source("fertilizer_scaling_plot_diagnostics_functions.R")` to
   `fertilizer_scaling_functions.R`.
4. Replace the inline `sample_locations <- data.frame(...)` inside
   `plot_diagnostics` with a call to `build_sample_locations()`.
5. Run both reference invocations; PNG-diff against the baseline.
6. Writer → reviewer → commit.

**Checkpoint: pause here for user approval before proceeding.**
This is the early approval gate — it validates the file layout, the
sourcing wiring, and the PNG-diff workflow against a minimal change.

### Steps 3–12: Extract remaining functions

Steps 3–12 proceed sequentially without further user approval, but
each keeps the writer/reviewer/commit cadence and each runs the
PNG-diff check before the reviewer approves. Order is chosen so each
extraction strictly shrinks `plot_diagnostics` and doesn't depend on
not-yet-extracted code.

- **Step 3**: `add_sample_markers`
- **Step 4**: `plot_map` (highest-risk — closure promotion validated
  here by PNG diff)
- **Step 5**: `plot_aggregation_comparison`
- **Step 6**: `plot_pattern_maps`
- **Step 7**: `plot_base_year_scatter`
- **Step 8**: `plot_relative_change_hist`
- **Step 9**: `plot_spatial_ts_ratio`
- **Step 10**: `plot_sample_timeseries`
- **Step 11**: `plot_distribution_histograms`
- **Step 12**: `plot_outlier_scatter`

Each step:

1. Move the targeted block from `plot_diagnostics` into the new file
   as a top-level function. Replace the moved block with a call to
   the new function, passing all previously-captured variables as
   explicit arguments.
2. Run both reference invocations; PNG-diff against the baseline.
3. Writer → reviewer → commit.

If a step's diff is larger than a "reasonably sized chunk" — e.g.,
because the moved block carries substantial inline setup — split it:
one commit for the extraction itself, one for wiring up the call site
cleanly. Keep each commit independently reviewable.

### Step 13: Final review and merge

1. Re-read the now-thin `plot_diagnostics`; confirm it matches the
   "What stays" list above and is ~30–50 lines.
2. Re-run both reference invocations; PNG-diff one last time.
3. Reviewer confirms spec alignment.
4. Merge the worktree branch back into `main` with
   `git merge --no-ff` so the feature-branch grouping is preserved in
   the commit graph.

## Next steps (out of scope)

Deferred cleanups to tackle after this lands:

- **De-duplicate `run_diagnostics_external.R`.** It embeds a drifted
  copy of `plot_diagnostics`. Once the refactored version is stable,
  that file should either `source()` the new module or be deleted
  outright if it's truly vestigial.
- **Same for `compare_histsoc_future.R`** if it holds similar
  duplication.
- **Add a rendering-based test.** The PNG-diff check used here is a
  one-shot verification, not part of the test suite. Folding a small
  version of it into `tests/` would catch future regressions
  automatically.
- **Prune comments.** The coordinate-system block moved into
  `plot_sample_timeseries` is long and could be trimmed once its
  claims are verified, but doing so is out of scope for a strict
  refactor.

## Non-goals

- No visual changes of any kind. Same legends, same colors, same
  axes, same plot order.
- No interface change to `plot_diagnostics`: same arg names, same
  defaults, same return value, same side effects.
- No changes to callers (`fertilizer_scaling.R` / `main`).
- No refactor of the other two scripts that embed or reference
  `plot_diagnostics`.
- No performance work.
