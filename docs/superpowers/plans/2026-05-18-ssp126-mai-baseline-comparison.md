# ssp126 mai NetCDF Baseline + Comparison Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task ends with a writer-agent diff → reviewer-agent approval → commit cycle (per project CLAUDE.md).

**Goal:** Add the lambda-method counterpart to the existing relative-method 3-year baseline NetCDF in [tests/testthat-slow/baselines/](../../../tests/testthat-slow/baselines/), document the baselines directory with a README, and piggyback NetCDF baseline assertions onto the existing ssp126 PNG-snapshot test so the regression check runs without a second `main()` invocation.

**Architecture:** The lambda baseline is sliced from the same production output we used for the relative baseline, with identical metadata preservation. The existing PNG-snapshot test at [tests/testthat-slow/test-plot_diagnostics_regression.R](../../../tests/testthat-slow/test-plot_diagnostics_regression.R) already runs `main("mai", "ssp126", "image", "gfdl-esm4")` once per slow-suite run; we extend [tools/diagnostics_png_harness.R](../../../tools/diagnostics_png_harness.R) to also redirect `output_base_path` to a `nc-outputs/` subdir of the test's existing tempdir, then add NetCDF baseline assertions to the existing ssp126 `test_that` block. One `main()` run now covers both PNG byte-identity and NetCDF data-identity for that scenario. The README documents both baselines, how to regenerate, and what to do when the comparison fails.

**Tech Stack:**
- R 4.5 inside the devcontainer
- `ncdf4` for reading/writing NetCDF
- `testthat` edition 3 (matches the existing slow-suite snapshot test)
- `withr` for tempdir lifecycle

---

## File structure

**Created (baselines):**
- `tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc` — first 3 years (2015–2017) of the lambda-method ssp126 mai output, full 720×360 grid, all metadata preserved from the production source. Sibling to the already-committed `..._relative_annual_2015_2017.nc`.

**Created (docs):**
- `tests/testthat-slow/baselines/README.md` — explains the directory's purpose, what each file is, how to regenerate, what test consumes them.

**Modified (test infrastructure):**
- `tools/diagnostics_png_harness.R` — `render_diagnostics_to_png()` gains an additional shadow that redirects `output_base_path` to a `nc-outputs/` subdir of `png_output_dir`. Existing PDF-to-PNG shadow unchanged. Behavior change is fully contained inside `on.exit` restoration.
- `tests/testthat-slow/test-plot_diagnostics_regression.R` — the ssp126 `test_that` block gains NetCDF baseline assertions after `snapshot_all_pngs(tmp)`. The histsoc block is untouched (no histsoc baselines were requested). Block name is updated to reflect that it now asserts both PNG and NetCDF identity.

**No modifications** to `fertilizer_scaling_functions.R` or `fertilizer_scaling_settings.R`.

---

## Per-task writer/reviewer/commit cadence (applies to every task below)

Per project CLAUDE.md, every task ends with:

1. Writer subagent implements the step(s).
2. Reviewer subagent reviews the diff against this plan and project conventions (no comments unless WHY is non-obvious; no scope creep).
3. Commit only after reviewer approval. If issues are flagged, writer fixes and reviewer re-reviews.
4. Where a task has two logically distinct sub-changes, split them into separate commits per CLAUDE.md.

No mid-plan checkpoint — proceed straight through Tasks 0–5.

---

## Task 0: Worktree setup

**Files:**
- None (git + .Renviron operations)

- [ ] **Step 1: Create the worktree**

```bash
cd /workspace
git fetch
git worktree add .worktrees/baseline-comparison -b baseline-comparison main
```

All subsequent task commands run from `/workspace/.worktrees/baseline-comparison/`.

- [ ] **Step 2: Populate the worktree's `.Renviron` so Task 4's verification has data paths**

The worktree was checked out fresh from `main`, so `/workspace`'s gitignored `.Renviron` is not present. Without it, `base_path_5min`/`base_path_timeseries` would resolve to the PIK cluster defaults (`/p/projects/...`) which don't exist in this devcontainer. Write a worktree-local `.Renviron`:

```bash
cat > /workspace/.worktrees/baseline-comparison/.Renviron <<'EOF'
RENV_CONFIG_SANDBOX_ENABLED=FALSE
FERT_BASE_PATH_5MIN=/workspace/data/inputs/Napprate_gadm_subnational
FERT_BASE_PATH_TIMESERIES=/workspace/data/inputs/isimip_files
FERT_OUTPUT_BASE_PATH=/workspace/.worktrees/baseline-comparison/data/outputs
EOF
```

`.Renviron` is gitignored, so this file stays local to the worktree.

- [ ] **Step 3: Sanity-check the worktree fast suite still passes**

```bash
cd /workspace/.worktrees/baseline-comparison
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -5
```

Expected: 0 FAIL. (Confirming the fresh worktree inherits a green test suite before changing anything.)

No commit at the end of Task 0 — `.Renviron` is gitignored and worktree creation itself is not a commit.

---

## Task 1: Generate and commit the lambda baseline NetCDF

**Files:**
- Create: `tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc`

**Approach:** Mirror the slicing logic used for the existing relative baseline (commit `6a89d6b` on `main` — `git show 6a89d6b` for reference). Read the production lambda output at `data/outputs/ssp126soc-adapt/lambda/...`, slice the first 3 time steps, write a new NetCDF preserving all variable/dim metadata and adding a `history` global attribute that records the slice operation.

- [ ] **Step 1: Generate the lambda baseline file**

Run from the worktree root:

```bash
Rscript -e '
suppressPackageStartupMessages(library(ncdf4))
src <- "/workspace/data/outputs/ssp126soc-adapt/lambda/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2100.nc"
dst <- "tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc"
in_nc <- nc_open(src)
on.exit(nc_close(in_nc), add = TRUE)
var_name <- names(in_nc$var)[1]
lon <- ncvar_get(in_nc, "lon")
lat <- ncvar_get(in_nc, "lat")
time_full <- ncvar_get(in_nc, "time")
time_units <- ncatt_get(in_nc, "time", "units")$value
data <- ncvar_get(in_nc, var_name, start = c(1, 1, 1), count = c(-1, -1, 3))
var_atts <- ncatt_get(in_nc, var_name)
glb_atts <- ncatt_get(in_nc, 0)
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
  ": sliced first 3 time steps from ", basename(src),
  " for use as a regression baseline"))
nc_close(out_nc)
info <- file.info(dst)
cat("wrote", dst, "(", info$size, "bytes)\n")
'
```

Expected: a single `wrote ...` line with the new file path and a byte count near 240 KB (similar size to the relative baseline).

- [ ] **Step 2: Sanity-check the file's structure matches the relative baseline**

```bash
Rscript -e '
suppressPackageStartupMessages(library(ncdf4))
for (m in c("relative", "lambda")) {
  f <- sprintf("tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", m)
  nc <- nc_open(f)
  v <- names(nc$var)[1]
  cat(m, ": shape=", paste(nc$var[[v]]$varsize, collapse="x"),
      "scaling_method=", ncatt_get(nc, 0, "scaling_method")$value, "\n")
  nc_close(nc)
}
'
```

Expected output (two lines):
```
relative : shape= 720x360x3 scaling_method= relative
lambda : shape= 720x360x3 scaling_method= lambda
```

- [ ] **Step 3: Commit**

```bash
git add tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc
git commit -m "$(cat <<'EOF'
test: add ssp126 mai lambda-method 3-year baseline NetCDF

The first 3 years (2015-2017) of the lambda-method ssp126 output for
mai, paired with the existing relative-method baseline. Same slicing
procedure: 720x360x3 grid sliced from the full 2015-2100 production
output, all metadata preserved, history attribute records the slice.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: README for the baselines directory

**Files:**
- Create: `tests/testthat-slow/baselines/README.md`

- [ ] **Step 1: Write the README**

Write to `tests/testthat-slow/baselines/README.md` with this exact content:

```markdown
# NetCDF regression baselines

Reference NetCDF outputs that the ssp126 block of `tests/testthat-slow/test-plot_diagnostics_regression.R` compares against on every run, to catch unintended drift in the script's numeric output.

## Contents

| File | Scenario | Crop | IAM | GCM | Method | Years |
| --- | --- | --- | --- | --- | --- | --- |
| `n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2017.nc` | ssp126 | mai | image | gfdl-esm4 | relative | 2015–2017 |
| `n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc`   | ssp126 | mai | image | gfdl-esm4 | lambda   | 2015–2017 |

Each file is a 720 × 360 × 3 (lon × lat × time) slice of the full 2015–2100 production output. All variable and dimension attributes (`units`, `_FillValue`, `long_name`, `scaling_method`, `base_year`, etc.) are preserved verbatim from the source. A `history` global attribute records the slicing operation.

## Generating / updating

The baselines are sliced from the full production outputs at `data/outputs/ssp126soc-adapt/<method>/n-fertilizer_mai_image_gfdl-esm4_ssp126_<method>_annual_2015_2100.nc`. To regenerate after an intentional change to the script's output:

1. Run `Rscript fertilizer_scaling.R` (or just the `main("mai", "ssp126", "image", "gfdl-esm4")` invocation) to produce fresh outputs under `data/outputs/`.
2. Re-slice both methods with the snippet below (run from the repo root):

   ```r
   library(ncdf4)
   for (m in c("relative", "lambda")) {
     src <- sprintf("data/outputs/ssp126soc-adapt/%s/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2100.nc", m, m)
     dst <- sprintf("tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", m)
     in_nc <- nc_open(src); on.exit(nc_close(in_nc), add = TRUE)
     var_name <- names(in_nc$var)[1]
     lon <- ncvar_get(in_nc, "lon")
     lat <- ncvar_get(in_nc, "lat")
     time_full <- ncvar_get(in_nc, "time")
     time_units <- ncatt_get(in_nc, "time", "units")$value
     data <- ncvar_get(in_nc, var_name, start = c(1, 1, 1), count = c(-1, -1, 3))
     var_atts <- ncatt_get(in_nc, var_name)
     glb_atts <- ncatt_get(in_nc, 0)
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
       ": sliced first 3 time steps from ", basename(src),
       " for use as a regression baseline"))
     nc_close(out_nc)
   }
   ```

3. Commit both baselines together with a message explaining what changed in the script.

## When the comparison test fails

A failure means the script's first-3-year output drifted from the committed baseline. Decide whether the change is intentional:

- **Intentional** (e.g. you changed the scaling formula): regenerate the baselines (see above) and commit alongside the script change.
- **Unintentional**: bisect to find the regression. The PNG snapshot tests in `_snaps/plot_diagnostics_regression/` likely also flag the change and can help localize it.
```

- [ ] **Step 2: Verify the README renders / is readable**

```bash
head -30 tests/testthat-slow/baselines/README.md
```

Expected: shows the title, intro, and the file table. Nothing weird in the markdown.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat-slow/baselines/README.md
git commit -m "$(cat <<'EOF'
docs: README for tests/testthat-slow/baselines/

Explains what the directory holds, how the baselines were sliced, how
to regenerate them when the script's output legitimately changes, and
what to do when the comparison test fails.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Piggyback NetCDF assertions on the existing ssp126 PNG-snapshot test

This task has **two logically distinct commits** per CLAUDE.md "split logical changes":

- **Step 3a**: extend the PNG harness to redirect `output_base_path` (test infrastructure).
- **Step 3b**: extend the existing ssp126 `test_that` block to assert NetCDF baselines (the actual new test logic).

### Step 3a: Harness redirects `output_base_path`

**Files:**
- Modify: `tools/diagnostics_png_harness.R`

**Why:** Today the harness shadows `pdf()` to capture PNGs in `png_output_dir`, but `main()`'s NetCDF outputs still land at `output_base_path/<scenario>/<method>/...` — wherever `.Renviron` points, which under the existing PNG test ends up polluting `/workspace/data/outputs/`. To assert NetCDF baselines from the same test invocation, the harness needs to also redirect the NetCDF outputs into the test's tempdir. As a bonus, this contains the harness's filesystem footprint inside `png_output_dir`.

- [ ] **Step 1: Update `render_diagnostics_to_png` in `tools/diagnostics_png_harness.R`**

The current function body is:

```r
render_diagnostics_to_png <- function(png_output_dir, crop, scenario,
                                      iam = NULL, gcm = NULL) {
  dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

  # ... existing on.exit + pdf shadow block ...

  main(crop, scenario, iam = iam, gcm = gcm)
}
```

Add a second on.exit-restored shadow that rebinds `output_base_path` in globalenv, after the existing PDF shadow block and before `main()`:

```r
  # Redirect NetCDF outputs into a `nc-outputs/` subdir of png_output_dir so
  # the harness's filesystem footprint is contained. Tests that need to
  # compare against baseline NetCDFs read from this location.
  orig_output_base_path <- output_base_path
  nc_dir <- file.path(png_output_dir, "nc-outputs")
  dir.create(nc_dir, showWarnings = FALSE, recursive = TRUE)
  assign("output_base_path", nc_dir, envir = globalenv())
  on.exit({
    assign("output_base_path", orig_output_base_path, envir = globalenv())
  }, add = TRUE)
```

The two `on.exit({...}, add = TRUE)` calls (the existing pdf-cleanup and the new output_base_path restore) both register cleanups that run on function exit in LIFO order. The pdf cleanup and output_base_path restore are independent, so order doesn't matter.

Also update the function header comment block to mention the new behavior. Find the existing header comment (lines 1–17 of the file), and append a sentence to the description of what the function does, e.g.:

```
# The function also redirects output_base_path into <png_output_dir>/nc-outputs
# for the duration of the call, so all of main()'s filesystem outputs are
# contained inside png_output_dir.
```

- [ ] **Step 2: Run the existing PNG snapshot tests to confirm they still pass**

```bash
Rscript -e 'testthat::test_file("tests/testthat-slow/test-plot_diagnostics_regression.R")' 2>&1 | tail -10
```

Expected: same result as before the change — both the histsoc and ssp126 PNG snapshot tests either PASS (production data present, byte-identical PNGs) or run without error with the existing snapshot baselines unchanged. Whatever the existing state was on `main`, the change must not regress it.

If the worktree's data points at production inputs (Task 0 Step 2), the tests should PASS. If not, they'll fall back to whatever the existing behavior was — typically "empty test" on `skip_if_not` or similar. Either way, no FAIL.

- [ ] **Step 3: Commit**

```bash
git add tools/diagnostics_png_harness.R
git commit -m "$(cat <<'EOF'
test: harness redirects main()'s NetCDF outputs into png_output_dir

render_diagnostics_to_png now also shadows output_base_path, sending
main()'s NetCDF (and intermediate PDF) writes into a nc-outputs/ subdir
of png_output_dir for the duration of the call. Lets the existing PNG
snapshot test assert on the NetCDF outputs of the same main() run
without a second invocation, and contains the harness's filesystem
footprint inside the test's tempdir.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Step 3b: Extend the ssp126 `test_that` block with NetCDF baseline assertions

**Files:**
- Modify: `tests/testthat-slow/test-plot_diagnostics_regression.R`

- [ ] **Step 1: Update the test file**

Open `tests/testthat-slow/test-plot_diagnostics_regression.R`. Currently the file looks like:

```r
testthat::local_edition(3)

source(
  testthat::test_path("..", "..", "tools", "diagnostics_png_harness.R"),
  chdir = TRUE
)

render_scenario <- function(crop, scenario, iam = NULL, gcm = NULL) {
  tmp <- tempfile(paste0("diagnostics-", scenario, "-"))
  dir.create(tmp, recursive = TRUE)
  withr::with_dir(
    testthat::test_path("..", ".."),
    render_diagnostics_to_png(tmp, crop, scenario, iam, gcm)
  )
  tmp
}

snapshot_all_pngs <- function(tmp_dir) {
  for (png in sort(list.files(tmp_dir, pattern = "\\.png$"))) {
    expect_snapshot_file(file.path(tmp_dir, png), name = png)
  }
}

test_that("plot_diagnostics output is byte-identical for mai histsoc", {
  tmp <- render_scenario("mai", "histsoc")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
})

test_that("plot_diagnostics output is byte-identical for mai ssp126 image gfdl-esm4", {
  tmp <- render_scenario("mai", "ssp126", "image", "gfdl-esm4")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
})
```

Add two new top-level helpers (after `snapshot_all_pngs`) and replace the second `test_that` block's name and body. The resulting file should be:

```r
testthat::local_edition(3)

source(
  testthat::test_path("..", "..", "tools", "diagnostics_png_harness.R"),
  chdir = TRUE
)

baseline_dir <- testthat::test_path("baselines")

render_scenario <- function(crop, scenario, iam = NULL, gcm = NULL) {
  tmp <- tempfile(paste0("diagnostics-", scenario, "-"))
  dir.create(tmp, recursive = TRUE)
  withr::with_dir(
    testthat::test_path("..", ".."),
    render_diagnostics_to_png(tmp, crop, scenario, iam, gcm)
  )
  tmp
}

snapshot_all_pngs <- function(tmp_dir) {
  for (png in sort(list.files(tmp_dir, pattern = "\\.png$"))) {
    expect_snapshot_file(file.path(tmp_dir, png), name = png)
  }
}

read_first_3_years <- function(path, var_name) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  list(
    data = ncdf4::ncvar_get(nc, var_name,
                            start = c(1, 1, 1), count = c(-1, -1, 3)),
    lon  = ncdf4::ncvar_get(nc, "lon"),
    lat  = ncdf4::ncvar_get(nc, "lat"),
    time = ncdf4::ncvar_get(nc, "time")[1:3]
  )
}

expect_ssp126_mai_baselines <- function(tmp) {
  for (method in c("relative", "lambda")) {
    produced_path <- file.path(
      tmp, "nc-outputs", "ssp126soc-adapt", method,
      sprintf("n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2100.nc", method)
    )
    baseline_path <- file.path(
      baseline_dir,
      sprintf("n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", method)
    )
    expect_true(file.exists(produced_path),
                label = sprintf("main() produced %s output", method))
    obs <- read_first_3_years(produced_path, "fertl_mai")
    exp <- read_first_3_years(baseline_path, "fertl_mai")
    expect_equal(obs$data, exp$data, tolerance = 0,
                 label = sprintf("first 3 years of %s data", method))
    expect_equal(obs$lon,  exp$lon,  tolerance = 0,
                 label = sprintf("%s lon coords", method))
    expect_equal(obs$lat,  exp$lat,  tolerance = 0,
                 label = sprintf("%s lat coords", method))
    expect_equal(obs$time, exp$time, tolerance = 0,
                 label = sprintf("%s time coords (first 3)", method))
  }
}

test_that("plot_diagnostics output is byte-identical for mai histsoc", {
  tmp <- render_scenario("mai", "histsoc")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
})

test_that("plot_diagnostics + NetCDF outputs match baselines for mai ssp126 image gfdl-esm4", {
  tmp <- render_scenario("mai", "ssp126", "image", "gfdl-esm4")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  snapshot_all_pngs(tmp)
  expect_ssp126_mai_baselines(tmp)
})
```

Three changes against the original file:
1. New `baseline_dir` top-level binding.
2. Two new helpers (`read_first_3_years`, `expect_ssp126_mai_baselines`).
3. The second `test_that` block's title is updated and gains an `expect_ssp126_mai_baselines(tmp)` call after `snapshot_all_pngs(tmp)`. The histsoc block is unchanged.

**Why `tolerance = 0`:** The script is deterministic and writes outputs at `prec = "float"`. Two runs against the same input data in the same devcontainer should produce bit-identical floats. The PNG byte-identity assertions in the same file rely on the same property. If `tolerance = 0` flags spurious diffs in practice, flag that to the maintainer rather than silently relaxing — see the open-items section.

- [ ] **Step 2: Run the slow test file and confirm both blocks pass**

```bash
Rscript -e 'testthat::test_file("tests/testthat-slow/test-plot_diagnostics_regression.R")' 2>&1 | tail -15
```

Expected:
- histsoc block: PASS (PNG snapshot, unchanged behavior).
- ssp126 block: PASS, now with NetCDF assertions on top of the PNG snapshot. Each method contributes 5 expectations (1 file-exists + 4 data/lon/lat/time equality checks), so the block runs 10 NetCDF expectations + however many PNG snapshot expectations were there before.

Runtime: roughly 5–10 minutes — dominated by the two production `main()` runs (one for histsoc, one for ssp126), neither of which is added by this change. The new NetCDF assertions add a few seconds of comparison overhead at most.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat-slow/test-plot_diagnostics_regression.R
git commit -m "$(cat <<'EOF'
test: assert ssp126 mai NetCDF baselines from the existing PNG test

Extends the ssp126 test_that block in test-plot_diagnostics_regression.R
to assert the first 3 years of both produced NetCDFs (relative + lambda)
match the committed baselines in tests/testthat-slow/baselines/. Reuses
the existing main() invocation — no second slow run.

The histsoc block is unchanged (no histsoc baselines were requested).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Full-suite verification

**Files:** none (verification step; commit only if something needs adjustment)

- [ ] **Step 1: Run the full fast suite to confirm no regressions**

```bash
Rscript -e 'testthat::test_dir("tests/testthat")' 2>&1 | tail -5
```

Expected: 0 FAIL across all fast tests (~210 PASS, matching the post-coverage-to-100 baseline).

- [ ] **Step 2: Run the full slow suite end-to-end**

```bash
Rscript -e 'testthat::test_dir("tests/testthat-slow")' 2>&1 | tail -10
```

Expected: 0 FAIL across the slow suite. With the harness redirect from Step 3a and the new NetCDF assertions from Step 3b, the ssp126 block now reports both PNG and NetCDF expectations. Total slow-suite `main()` invocations is unchanged from before this plan.

- [ ] **Step 3: If anything fails, fix it.** Likely failure modes:
  - `expect_equal(..., tolerance = 0)` flags differences against the freshly-sliced lambda baseline — see open item #1.
  - PNG snapshots flag differences — this would mean the harness redirect somehow changed PDF generation. The redirect only touches `output_base_path` (not anything `pdf()` consumes), so this would be surprising. Investigate before patching.
  - File paths don't resolve — re-check that `tmp/nc-outputs/ssp126soc-adapt/<method>/` matches what `main()` writes for ssp126.

Make fixes, re-run, commit each fix as its own commit (per CLAUDE.md "split logical changes"). If no fixes were needed, no commit at the end of Task 4.

---

## Task 5: Finish the branch

**Files:** none (git operation)

- [ ] **Step 1: Merge `baseline-comparison` into `main` with `--no-ff`**

```bash
cd /workspace
git fetch
git checkout main
git merge --no-ff baseline-comparison -m "Merge branch 'baseline-comparison': lambda baseline, README, ssp126 NetCDF baseline assertions piggybacked on the PNG snapshot test"
```

(Per CLAUDE.md "No fast-forward merges".) Confirm the merge commit appears in `git log --oneline --graph -6` with the side-branch commits grouped under it.

- [ ] **Step 2: Remove the worktree and delete the branch**

```bash
cd /workspace
git worktree remove .worktrees/baseline-comparison
git branch -d baseline-comparison
```

- [ ] **Step 3: Verify the regression test still passes from `main`**

```bash
cd /workspace
Rscript -e 'testthat::test_file("tests/testthat-slow/test-plot_diagnostics_regression.R")' 2>&1 | tail -10
```

Expected: same result as Task 4 Step 2's ssp126 block run — both `test_that` blocks PASS, ssp126 now reports both PNG and NetCDF expectations.

No push — `main` stays local-only ahead of `origin` unless explicitly requested.

---

## Open items the reviewer should flag during execution

1. **If `tolerance = 0` flags spurious differences** between freshly-produced and baseline data in Step 3b's run (e.g., 1e-15 float drift): stop and report rather than silently swap to default tolerance. The user explicitly chose strict equality on the same logic the PNG byte-identity tests rely on; if it's actually broken, that's a separate decision they should make.
2. **If the lambda source NetCDF in `data/outputs/ssp126soc-adapt/lambda/` was regenerated after the relative baseline was committed** (commit `6a89d6b` on `main`, dated 2026-05-17): the rel and lambda baselines would be inconsistent (different "vintage" of input data). Check `ls -la data/outputs/ssp126soc-adapt/{relative,lambda}/n-fertilizer_mai_image_gfdl-esm4_ssp126_*_annual_2015_2100.nc` and confirm timestamps are close together. If not, regenerate both baselines from a single fresh `main()` run.
3. **If the existing PNG snapshot expectations regress** after Step 3a's harness change: the redirect should not affect PDF generation. If somehow it does, revert to a more conservative approach (e.g., scope the redirect to a separate function variant or a flag argument) — but investigate root cause first.
4. **If `main()` errors out at Task 4 Step 2 with "Input file does not exist"**: the worktree `.Renviron` from Task 0 is missing or has the wrong paths. Fix that, don't change the test.
5. **CLI behavior change:** `tools/render_diagnostics_png.R` invokes the harness too. After this plan, CLI users get NetCDFs in `<png_output_dir>/nc-outputs/` rather than in `data/outputs/...`. The CLI's stated purpose is producing diagnostic PNGs, so the side-effect relocation is harmless to its primary use case, but if a downstream consumer relies on the old behavior, surface that and consider gating the redirect behind a flag.
