# Fix Upside-Down Output NetCDFs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task ends with a writer-agent diff → reviewer-agent approval → commit cycle (per project CLAUDE.md).

**Goal:** Stop producing upside-down output NetCDFs. `aggregate_to_halfdegree` currently synthesizes `lat_halfdeg <- seq(-89.75, 89.75, by = 0.5)` while emitting data that is indexed north→south (because the Mueller 5-min input is north→south), so the output NetCDF has `lat[1]=south` paired with `data[*,1]=north` — viewers honoring the `lat` axis show the map upside-down. Replace the hardcoded `lon`/`lat` synthesis with values derived from the actual input coordinates, and canonicalize the function's output to (ascending lat, south→north-indexed data) so downstream code has an unambiguous contract.

**Architecture:** `aggregate_to_halfdegree` computes new `lon_halfdeg` / `lat_halfdeg` by averaging each block of 6 input coords (preserving whatever convention the input file uses), then — if the derived `lat_halfdeg` is descending — reverses both `lat_halfdeg` and the lat dimension of `data_halfdeg` so the function always returns ascending lat with data aligned in south→north order. Five plot-helper call sites currently do a `data[, c(length(lat):1)]` flip to compensate for the (lat_ascending, data_N→S) mismatch the function produced; with the function now emitting (lat_ascending, data_S→N), those flips become a double-flip that breaks the display. Each one is removed. Plot output ends up byte-identical (same pixel rendering via a different code path); NetCDF data array values change positions, so the two committed baselines must be regenerated.

**Tech Stack:**
- R 4.5 inside the devcontainer
- `ncdf4` (NetCDF read/write)
- `testthat` edition 3
- `fields::image.plot` (lat-must-be-ascending requirement)

---

## File structure

**Modified (production code):**
- `fertilizer_scaling_functions.R` — `aggregate_to_halfdegree` body (lines 32–70); remove `data[, c(length(lat):1)]` flips at lines 1004 (inside `plot_map_comp`) and 1130 (inside `plot_mask_panel`); the data arg now arrives pre-aligned with ascending lat.
- `fertilizer_scaling_plot_diagnostics_functions.R` — remove `data[, c(length(lat):1)]` flips at lines 73 (`plot_map`), 138 (`plot_aggregation_comparison` half-degree path), and 321 (inside `plot_spatial_ts_ratio`). The 5-min path at lines 129–131 stays as-is: it consumes raw 5-min input which is still descending; that helper continues to `rev(lat_5min)` + flip data locally.

**Modified (regenerated baselines):**
- `tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2017.nc` — re-sliced from a fresh ssp126 mai run with the fixed aggregator. Data orientation is now south→north along the lat axis.
- `tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc` — same.

**Unchanged:**
- PNG snapshots under `tests/testthat-slow/_snaps/plot_diagnostics_regression/` — should remain byte-identical (the plot helpers now skip a flip that the aggregator now performs once; the final `image.plot` inputs are the same). Task 3 verifies this; if a snapshot regresses, Task 3 has an authorized regeneration step.
- All fast-suite tests, the comparison helper `compare_relative_lambda`'s file-existence / lon-sort / all-NA / pretty-mock branches.

---

## Per-task writer/reviewer/commit cadence (applies to every task below)

Per project CLAUDE.md, every task ends with:

1. Writer subagent implements the step(s).
2. Reviewer subagent reviews the diff against this plan and project conventions (no comments unless WHY is non-obvious; no scope creep).
3. Commit only after reviewer approval. If issues are flagged, writer fixes and reviewer re-reviews.
4. Where a task has logically-distinct sub-changes, split commits per CLAUDE.md.

No mid-plan checkpoint — proceed straight through.

---

## Task 0: Worktree setup

**Files:**
- None (git + .Renviron operations)

- [ ] **Step 1: Create the worktree**

```bash
cd /workspace
git fetch
git worktree add .worktrees/fix-output-orientation -b fix-output-orientation main
```

- [ ] **Step 2: Worktree-local `.Renviron`**

```bash
cat > /workspace/.worktrees/fix-output-orientation/.Renviron <<'EOF'
RENV_CONFIG_SANDBOX_ENABLED=FALSE
FERT_BASE_PATH_5MIN=/workspace/data/inputs/Napprate_gadm_subnational
FERT_BASE_PATH_TIMESERIES=/workspace/data/inputs/isimip_files
FERT_OUTPUT_BASE_PATH=/workspace/.worktrees/fix-output-orientation/data/outputs
EOF
```

`FERT_OUTPUT_BASE_PATH` is deliberately pointed at the worktree-local outputs directory so Task 2's fresh `main()` run does NOT overwrite the production `/workspace/data/outputs/` tree.

- [ ] **Step 3: Confirm the fast suite still passes (baseline check)**

```bash
cd /workspace/.worktrees/fix-output-orientation
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -3
```

Expected: 0 FAIL, ~212 PASS (matching `main` at HEAD).

No commit at end of Task 0.

---

## Task 1: Fix `aggregate_to_halfdegree` + remove compensating flips

**Why one commit:** The aggregator change and the plot-helper flip removals are a coupled pair — neither half makes sense without the other. Reverting one without the other re-creates the upside-down state. The commit message naturally describes them as one fix.

**Files:**
- Modify: `fertilizer_scaling_functions.R` (lines 32–70, 1004, 1130)
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (lines 73, 138, 321)

- [ ] **Step 1: Update `aggregate_to_halfdegree` body**

Open `fertilizer_scaling_functions.R`. Find lines 32–70 (the entire `aggregate_to_halfdegree` function). Replace the existing function body with:

```r
aggregate_to_halfdegree <- function(data_5min, lon_5min, lat_5min) {
  # input: 4320 x 2160 (5 arcmin)
  # output: 720 x 360 (0.5 degree)
  # aggregation factor: 6 cells in each direction (6x6 = 36 cells per output cell)

  nlon_out <- 720
  nlat_out <- 360
  agg_factor <- 6

  # Derive output coordinates by averaging each 6-cell block of the input
  # coordinates rather than synthesizing from scratch, so we inherit
  # whatever convention the input file uses (Mueller 5-min files are
  # north->south).
  lon_halfdeg <- colMeans(matrix(lon_5min, nrow = agg_factor))
  lat_halfdeg <- colMeans(matrix(lat_5min, nrow = agg_factor))

  # create output array
  data_halfdeg <- array(NA, dim = c(nlon_out, nlat_out))

  # vectorized aggregation using array operations
  # process one output longitude at a time (still faster than nested loop)
  for (i in 1:nlon_out) {
    i_start <- (i - 1) * agg_factor + 1
    i_end <- i * agg_factor

    # extract longitude slice for all latitudes at once
    lon_slice <- data_5min[i_start:i_end, ]

    # vectorized aggregation over latitude
    for (j in 1:nlat_out) {
      j_start <- (j - 1) * agg_factor + 1
      j_end <- j * agg_factor

      # extract block and calculate mean
      block <- lon_slice[, j_start:j_end]
      data_halfdeg[i, j] <- mean(block, na.rm = TRUE)
      if (is.nan(data_halfdeg[i, j])) data_halfdeg[i, j] <- NA
    }
  }

  # Canonicalize to ascending lat with data aligned south->north along the
  # lat axis. This gives downstream code (write_netcdf_file, plot helpers,
  # fields::image.plot) an unambiguous contract regardless of which
  # convention the input file used.
  if (any(diff(lat_halfdeg) < 0)) {
    lat_halfdeg <- rev(lat_halfdeg)
    data_halfdeg <- data_halfdeg[, ncol(data_halfdeg):1]
  }

  return(list(data = data_halfdeg, lon = lon_halfdeg, lat = lat_halfdeg))
}
```

Three changes vs. the original:
- Lines that synthesized `lon_halfdeg <- seq(-179.75, 179.75, by = 0.5)` and `lat_halfdeg <- seq(-89.75, 89.75, by = 0.5)` are gone; replaced by `colMeans(matrix(..., nrow = agg_factor))` near the top.
- A canonicalization block is added immediately before the `return(...)`.
- Two short header comments explain the WHY of each change. No other comment changes.

- [ ] **Step 2: Remove the `data[, c(length(lat):1)]` flip in `plot_map_comp`**

Open `fertilizer_scaling_functions.R`. Find line 1004 inside `plot_map_comp`:

```r
    data_plot <- data[, c(length(lat):1)]
```

Replace that single line with:

```r
    data_plot <- data
```

No other changes inside `plot_map_comp`. The subsequent `image.plot(lon, lat, data_for_plot, ...)` calls at lines 1066 and 1072 keep working because the data arg now arrives pre-aligned with ascending lat.

- [ ] **Step 3: Remove the flip in `plot_mask_panel`**

Open `fertilizer_scaling_functions.R`. Find line 1130 inside `plot_mask_panel`:

```r
    data_plot <- mask_numeric[, c(length(lat):1)]
```

Replace with:

```r
    data_plot <- mask_numeric
```

- [ ] **Step 4: Remove the flip in `plot_map` (in `fertilizer_scaling_plot_diagnostics_functions.R`)**

Open `fertilizer_scaling_plot_diagnostics_functions.R`. Find line 73:

```r
  data_plot <- data[, c(length(lat):1)]
```

Replace with:

```r
  data_plot <- data
```

- [ ] **Step 5: Remove the flip in `plot_aggregation_comparison` (half-degree path)**

Same file, line 138:

```r
  data_halfdeg_plot <- base_rate[, c(length(lat):1)]
```

Replace with:

```r
  data_halfdeg_plot <- base_rate
```

**Important:** Do NOT change lines 129–131 (the 5-min path with `lat_5min_plot <- rev(lat_5min)` and `data_5min_plot <- spatial_data_5min[, ncol(spatial_data_5min):1]`). Those still consume raw 5-min input which is unchanged (descending lat from the production NetCDF).

- [ ] **Step 6: Remove the flip in `plot_spatial_ts_ratio`**

Same file, line 321 (inside `plot_spatial_ts_ratio`, defined at line 305):

```r
      data_plot <- ratio_capped[, c(length(lat):1)]
```

Replace with:

```r
      data_plot <- ratio_capped
```

- [ ] **Step 7: Sanity-check the fast suite still passes**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -3
```

Expected: 0 FAIL. None of the fast tests should be affected (they don't exercise the aggregator with production-shaped data, and the synthetic-data tests in `tests/testthat/test-main_full_runs.R` were already running with `aggregate_to_halfdegree` mocked to a pass-through).

- [ ] **Step 8: Commit**

```bash
git add fertilizer_scaling_functions.R fertilizer_scaling_plot_diagnostics_functions.R
git commit -m "$(cat <<'EOF'
fix: derive aggregate_to_halfdegree output coords from input files

The function previously synthesized lon_halfdeg/lat_halfdeg with hardcoded
ascending seq() calls, while emitting data indexed in the same order as
the input (north->south, because the Mueller 5-min files are N->S). The
output NetCDFs paired lat[1]=south with data[*,1]=north and viewers
honoring the lat axis showed maps upside-down.

Derive the coords by averaging each 6-cell block of the input coords,
then canonicalize to ascending lat with data aligned south->north along
the lat axis. This gives write_netcdf_file and the plot helpers an
unambiguous contract regardless of input convention.

Five plot helpers used to do data[, c(length(lat):1)] to compensate for
the previous (lat_ascending, data_N->S) mismatch. With the aggregator
canonicalizing once, those flips become a double-flip and are removed.
The 5-min path in plot_aggregation_comparison still rev()s locally
because its input (raw 5-min) remains descending.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Regenerate the two NetCDF baselines

The committed baselines under `tests/testthat-slow/baselines/` were sliced from outputs produced before the fix, so their data arrays are in the old north→south order. After Task 1, a fresh `main()` run produces south→north data; the slow comparison test would fail on `expect_equal(obs$data, exp$data, tolerance = 0)` until both baselines are regenerated.

**Files:**
- Modify: `tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2017.nc`
- Modify: `tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc`

- [ ] **Step 1: Run `main()` once to produce a fresh full ssp126 mai output**

```bash
cd /workspace/.worktrees/fix-output-orientation
Rscript -e '
source("fertilizer_scaling_settings.R")
source("fertilizer_scaling_functions.R")
main("mai", "ssp126", iam = "image", gcm = "gfdl-esm4")
' 2>&1 | tail -5
```

Expected: ends with `[1] "Completed processing for mai ssp126"` and no errors. Runtime ~5–10 minutes. Output files land under `/workspace/.worktrees/fix-output-orientation/data/outputs/ssp126soc-adapt/{relative,lambda}/` per Task 0's `.Renviron`.

- [ ] **Step 2: Verify the fresh output has the expected orientation**

```bash
Rscript -e '
suppressPackageStartupMessages(library(ncdf4))
nc <- nc_open("data/outputs/ssp126soc-adapt/relative/n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2100.nc")
lat <- ncvar_get(nc, "lat")
cat("lat first 3:", head(lat, 3), "\n")
cat("lat last 3:", tail(lat, 3), "\n")
cat("lat ascending?", !any(diff(lat) < 0), "\n")
nc_close(nc)
' 2>&1 | tail -3
```

Expected:
```
lat first 3: -89.75 -89.25 -88.75
lat last 3: 88.75 89.25 89.75
lat ascending? TRUE
```

If the lat is still descending, the canonicalization branch in Task 1's aggregator isn't firing — stop and investigate before re-slicing baselines.

- [ ] **Step 3: Re-slice both baselines from the fresh outputs**

```bash
Rscript -e '
suppressPackageStartupMessages(library(ncdf4))
for (m in c("relative", "lambda")) {
  src <- sprintf("data/outputs/ssp126soc-adapt/%s/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2100.nc", m, m)
  dst <- sprintf("tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", m)
  in_nc <- nc_open(src)
  var_name <- names(in_nc$var)[1]
  lon <- ncvar_get(in_nc, "lon")
  lat <- ncvar_get(in_nc, "lat")
  time_full <- ncvar_get(in_nc, "time")
  time_units <- ncatt_get(in_nc, "time", "units")$value
  data <- ncvar_get(in_nc, var_name, start = c(1, 1, 1), count = c(-1, -1, 3))
  var_atts <- ncatt_get(in_nc, var_name)
  glb_atts <- ncatt_get(in_nc, 0)
  nc_close(in_nc)
  dim_lon <- ncdim_def("lon", "degrees_east", lon)
  dim_lat <- ncdim_def("lat", "degrees_north", lat)
  dim_time <- ncdim_def("time", time_units, time_full[1:3])
  ncv <- ncvar_def(name = var_name, units = var_atts$units,
                   dim = list(dim_lon, dim_lat, dim_time),
                   missval = var_atts$`_FillValue`, prec = "float",
                   longname = var_atts$long_name, compression = 9, verbose = FALSE)
  out_nc <- nc_create(dst, list(ncv), verbose = FALSE)
  ncvar_put(out_nc, ncv, data, start = c(1, 1, 1), count = c(-1, -1, 3))
  for (a in names(glb_atts)) ncatt_put(out_nc, 0, a, glb_atts[[a]])
  ncatt_put(out_nc, 0, "history", paste0(
    format(Sys.Date()),
    ": re-sliced first 3 time steps from ", basename(src),
    " after aggregate_to_halfdegree was changed to derive coords from input"))
  nc_close(out_nc)
  cat("wrote", dst, "(", file.info(dst)$size, "bytes)\n")
}
' 2>&1 | tail -3
```

Expected: two `wrote ...` lines, each ~230 KB.

- [ ] **Step 4: Sanity-check the new baselines**

```bash
Rscript -e '
suppressPackageStartupMessages(library(ncdf4))
for (m in c("relative", "lambda")) {
  f <- sprintf("tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", m)
  nc <- nc_open(f)
  lat <- ncvar_get(nc, "lat")
  cat(m, ": shape=", paste(nc$var[[1]]$varsize, collapse="x"),
      "lat[1]=", lat[1], "lat[last]=", lat[length(lat)], "\n")
  nc_close(nc)
}
' 2>&1 | tail -3
```

Expected:
```
relative : shape= 720x360x3 lat[1]= -89.75 lat[last]= 89.75
lambda : shape= 720x360x3 lat[1]= -89.75 lat[last]= 89.75
```

(Compared to before: `lat[1]= -89.75 lat[last]= 89.75` was already what the OLD baselines had — but the *data array* contents are now flipped along the lat axis.)

- [ ] **Step 5: Commit**

```bash
git add tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2017.nc \
        tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc
git commit -m "$(cat <<'EOF'
test: regenerate ssp126 mai baselines after orientation fix

Re-sliced from fresh ssp126 mai outputs produced with the fixed
aggregate_to_halfdegree. Data arrays are now indexed south->north
along the lat axis (matching the canonical ascending lat). Lat/lon
coord values are unchanged; only the per-pixel data values move.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Run the slow suite, regenerate PNG snapshots only if they regressed

**Expectation:** the PNG snapshots should remain byte-identical. The aggregator now does once (canonicalize: rev lat + flip data) what the five plot helpers each did locally. The final inputs to `fields::image.plot` (the same `lon`, `lat`, and `data` arrays) are identical. The rendered PNGs should be too.

**Files:**
- (Conditional) `tests/testthat-slow/_snaps/plot_diagnostics_regression/*.png` — only regenerate if the test reports byte differences.

- [ ] **Step 1: Run the slow suite**

```bash
cd /workspace/.worktrees/fix-output-orientation
Rscript -e 'testthat::test_dir("tests/testthat-slow")' 2>&1 | tail -10
```

Expected: 0 FAIL. The NetCDF comparison expectations now pass against the regenerated baselines from Task 2. The PNG snapshot expectations pass byte-identically against the existing committed snapshots.

- [ ] **Step 2: If a PNG snapshot regressed, investigate before accepting**

If any `expect_snapshot_file()` fails with a `.new.png` file written next to the existing baseline, do NOT immediately accept the new snapshot. The expectation was that the rendered pixels stay identical — a real difference means somewhere I missed a flip or accidentally introduced a new orientation issue.

Inspect via:
```bash
ls tests/testthat-slow/_snaps/plot_diagnostics_regression/*.new.png 2>/dev/null
```

Use `testthat::snapshot_review("plot_diagnostics_regression")` in an interactive R session to see side-by-side comparisons (or, if there's no interactive R, examine the `.new.png` next to the baseline directly).

If the differences look like a genuine orientation issue (e.g., one of the plots is now upside-down or shifted), stop and investigate the plot helpers — most likely an `image.plot` call site that was missed in Task 1.

If after investigation the differences are spurious (e.g., a single-pixel anti-aliasing artifact), accept via:
```bash
Rscript tools/accept_diagnostics_baseline.R
```

and commit the updated snapshot files:
```bash
git add tests/testthat-slow/_snaps/plot_diagnostics_regression/
git commit -m "test: accept regenerated PNG snapshots after orientation fix"
```

- [ ] **Step 3: Confirm 0 FAIL on the slow suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat-slow")' 2>&1 | tail -3
```

Expected: 0 FAIL across the whole slow suite (PNG snapshots + NetCDF baselines + the synthetic `test-main_full_runs.R` end-to-end runs).

No commit at end of Task 3 unless Step 2 produced one.

---

## Task 4: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the fast suite**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -3
```

Expected: 0 FAIL, ~212 PASS.

- [ ] **Step 2: Run the slow suite**

Already done in Task 3 Step 3; re-run to confirm a clean state if Task 3 produced snapshot updates.

```bash
Rscript -e 'testthat::test_dir("tests/testthat-slow")' 2>&1 | tail -3
```

Expected: 0 FAIL.

- [ ] **Step 3: Coverage spot-check**

```bash
Rscript tests/coverage.R 99 2>&1 | tail -5
```

Expected: still 100.00% (the orientation fix doesn't add/remove instrumented lines; existing tests cover the new canonicalize branch via the synthetic `aggregate_to_halfdegree` invocations).

If coverage drops below 99%, investigate the gap; the new canonicalize block introduces a conditional whose `TRUE` branch must be hit by some test against real-shape data (Task 3 Step 1's slow suite run does so via the snapshot test's `main()` invocation on production data).

No commit at end of Task 4.

---

## Task 5: Finish the branch

**Files:** none (git operation)

- [ ] **Step 1: Merge `fix-output-orientation` into `main` with `--no-ff`**

```bash
cd /workspace
git fetch
git checkout main
git merge --no-ff fix-output-orientation -m "Merge branch 'fix-output-orientation': derive aggregate_to_halfdegree coords from input files, fix upside-down NetCDFs"
```

- [ ] **Step 2: Remove the worktree and delete the branch**

```bash
git worktree remove .worktrees/fix-output-orientation
git branch -d fix-output-orientation
```

- [ ] **Step 3: Verify the slow suite still passes from `main`**

```bash
Rscript -e 'testthat::test_dir("tests/testthat-slow")' 2>&1 | tail -3
```

Expected: 0 FAIL (same result as Task 4 Step 2).

No push — `main` stays local-only ahead of `origin` unless explicitly requested.

---

## Open items the reviewer should flag during execution

1. **If Task 2 Step 2's verification shows lat already ascending in the fresh output** without the canonicalize branch firing: the input lat may have flipped convention, OR `colMeans(matrix(...))` is reshaping wrong. Confirm `head(lat_5min, 3)` is `[89.96, 89.88, 89.79]` (descending). If that holds, the matrix reshape is wrong — investigate before re-slicing baselines.
2. **If Task 3 Step 1's PNG snapshot test reports differences:** do NOT auto-accept. The expectation is byte-identity. A real difference means a plot helper site was missed in Task 1 or the aggregator canonicalization has a subtle bug. Investigate the diff first; the `.new.png` artifacts left next to the snapshot baselines should make the orientation issue visible at a glance.
3. **If Task 4 Step 3's coverage drops below 100%:** the new `if (any(diff(lat_halfdeg) < 0))` block in the aggregator has a conditional that must be exercised. Production-data slow tests hit the `TRUE` branch (descending input). The synthetic `test-main_full_runs.R` mocks `aggregate_to_halfdegree` to a pass-through and doesn't exercise either branch. If coverage is reporting the `FALSE` branch (ascending input) as uncovered, that's expected and acceptable — flag it but don't artificially construct a test just to cover that branch.
4. **CLI tool behavior:** `tools/render_diagnostics_png.R` still works unchanged. The harness from the previous merge (`a46aba6`) already redirects NetCDF outputs inside the harness's tempdir; this plan doesn't touch that path.
