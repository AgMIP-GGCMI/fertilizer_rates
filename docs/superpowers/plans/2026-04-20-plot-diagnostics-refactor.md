# Refactor `plot_diagnostics` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the 647-line `plot_diagnostics` function in `fertilizer_scaling_functions.R` (lines 540–1186) into a set of focused top-level functions in a new file `fertilizer_scaling_plot_diagnostics_functions.R`, leaving `plot_diagnostics` as a thin (~30–50 line) orchestrator. Output must be byte-identical.

**Architecture:** Strict refactor. Two closures (`plot_map`, `add_sample_markers`) are promoted to top-level functions and receive their previously-captured variables as explicit arguments. Plot blocks are grouped into 9 named section functions plus 2 helpers. A PNG-rendering verification harness (shadows `grDevices::pdf` with `grDevices::png`) produces byte-comparable output after every extraction commit.

**Tech Stack:** R (base, `grDevices`, `fields::image.plot`, cairo PNG backend). No new runtime dependencies.

**Reference documents:**
- Spec: `docs/superpowers/specs/2026-04-20-plot-diagnostics-refactor-design.md`
- User conventions (from auto-memory, apply throughout):
  - Commit at every step; split logically distinct changes
  - Subagent-driven writer → reviewer → commit cycle
  - One early approval gate (after Task 6), then proceed autonomously
  - Work on a worktree; merge back with `--no-ff` at the end

---

## File Structure

**New files:**
- `tools/render_diagnostics_png.R` — PNG verification harness (created in Task 2).
- `fertilizer_scaling_plot_diagnostics_functions.R` — new module containing the 11 extracted functions (created in Task 6).

**Modified files:**
- `fertilizer_scaling_functions.R` — source the new module; `plot_diagnostics` shrinks from ~647 lines to ~30–50 lines as its body is progressively extracted (Tasks 6–16).

**Untracked (under already-ignored `data/`):**
- `data/plot-refactor-baseline/` — baseline PNGs + manifest. Not committed.
- `data/plot-refactor-current/` — per-check output. Regenerated each extraction. Not committed.

---

## Reference Invocations

Both of these must produce byte-identical PNG manifests before and after every commit:

```bash
Rscript tools/render_diagnostics_png.R data/plot-refactor-<phase>/histsoc mai histsoc
Rscript tools/render_diagnostics_png.R data/plot-refactor-<phase>/ssp126  mai ssp126 image gfdl-esm4
```

where `<phase>` is `baseline` before any extraction and `current` after each extraction.

---

## Task 1: Create the worktree

**Files:**
- No files touched yet — just git state.

- [ ] **Step 1: Create worktree and branch**

```bash
git -C /workspace worktree add /home/node/worktrees/plot-diagnostics-refactor -b refactor/plot-diagnostics main
```

Expected: `Preparing worktree ... Branch 'refactor/plot-diagnostics' set up to track 'main'`. The directory `/home/node/worktrees/plot-diagnostics-refactor` is created. (It lives outside `/workspace` because the read-only parent of `/workspace` prevents creating sibling directories.)

- [ ] **Step 2: Switch to the worktree and confirm state**

```bash
cd /home/node/worktrees/plot-diagnostics-refactor && git status && git log --oneline -3
```

Expected: clean working tree; HEAD at the latest main commit (the spec commit).

- [ ] **Step 3: Copy the `.Renviron` file into the worktree if present on main**

```bash
[ -f /workspace/.Renviron ] && cp /workspace/.Renviron . || echo "no .Renviron on main, skip"
```

The `.Renviron` is gitignored; the worktree needs its own copy so path overrides work. If there's no `.Renviron` on main, the worktree uses defaults.

All subsequent tasks run inside `/home/node/worktrees/plot-diagnostics-refactor`.

---

## Task 2: Write the PNG verification harness

**Files:**
- Create: `tools/render_diagnostics_png.R`

- [ ] **Step 1: Create `tools/` directory**

```bash
mkdir -p tools
```

- [ ] **Step 2: Write the harness script**

Create `tools/render_diagnostics_png.R` with the following exact content:

```r
#!/usr/bin/env Rscript
# ============================================================================
# render_diagnostics_png.R
# ============================================================================
# Verification harness for the plot_diagnostics refactor.
#
# Shadows grDevices::pdf with a png() wrapper so that each diagnostic
# "page" becomes a byte-comparable PNG file. Used to confirm that
# refactoring plot_diagnostics does not change the rendered output.
#
# Usage:
#   Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]
#
# Examples:
#   Rscript tools/render_diagnostics_png.R data/plot-refactor-baseline/histsoc mai histsoc
#   Rscript tools/render_diagnostics_png.R data/plot-refactor-baseline/ssp126  mai ssp126 image gfdl-esm4
# ============================================================================

harness_args <- commandArgs(trailingOnly = TRUE)
if (length(harness_args) < 3) {
  stop("Usage: Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]")
}

png_output_dir <- harness_args[1]
scaling_args <- harness_args[-1]
dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

# Make fertilizer_scaling.R see the CLI args it expects (crop, scenario, ...)
commandArgs <- function(trailingOnly = FALSE) {
  if (trailingOnly) scaling_args else c("Rscript", "fertilizer_scaling.R", scaling_args)
}

# Shadow grDevices::pdf. plot_diagnostics calls `pdf(plot_file, width = 16, height = 14)`.
# Our shadow ignores `file`'s directory and writes cairo PNGs into png_output_dir
# using an %03d multi-page filename pattern, with inches converted to pixels at
# a fixed DPI so width/height are preserved.
.harness_png_dpi <- 100
pdf <- function(file, width = 7, height = 7, ...) {
  base <- sub("\\.pdf$", "", basename(file))
  pattern <- file.path(png_output_dir, paste0(base, "-%03d.png"))
  grDevices::png(
    filename = pattern,
    width = round(width * .harness_png_dpi),
    height = round(height * .harness_png_dpi),
    type = "cairo",
    res = .harness_png_dpi
  )
}

# Run the full pipeline. fertilizer_scaling.R sources
# fertilizer_scaling_functions.R, parses commandArgs(), and calls main(...).
source("fertilizer_scaling.R")
```

- [ ] **Step 3: Check the harness parses args without running (syntax check)**

```bash
Rscript -e 'parse(file = "tools/render_diagnostics_png.R")' && echo "syntax ok"
```

Expected: `syntax ok`.

- [ ] **Step 4: Commit**

```bash
git add tools/render_diagnostics_png.R
git commit -m "$(cat <<'EOF'
Add PNG verification harness for plot_diagnostics refactor.

Shadows grDevices::pdf() with a cairo-backed png() wrapper so that
each diagnostic "page" becomes a byte-comparable PNG. Used to confirm
the plot_diagnostics refactor does not change rendered output.
EOF
)"
```

---

## Task 3: Run the Step 0 sanity check

Prove the harness is deterministic before trusting it. The refactor has not started — we're running unchanged code twice and confirming the PNG manifests match.

**Files:** none modified.

- [ ] **Step 1: Run the harness twice for the histsoc scenario**

```bash
rm -rf data/plot-refactor-sanity
Rscript tools/render_diagnostics_png.R data/plot-refactor-sanity/run1 mai histsoc
Rscript tools/render_diagnostics_png.R data/plot-refactor-sanity/run2 mai histsoc
```

Expected: two directories with equivalent PNG files. Both runs complete without error.

- [ ] **Step 2: Compare manifests**

```bash
cd data/plot-refactor-sanity
(cd run1 && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) | sed 's|./run1/||' > run1.md5
(cd run2 && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) | sed 's|./run2/||' > run2.md5
diff run1.md5 run2.md5 && echo "DETERMINISTIC" || echo "NON-DETERMINISTIC"
cd -
```

Expected: `DETERMINISTIC`. Empty diff means the harness produces byte-identical PNGs across runs.

- [ ] **Step 3: Sanity-check for ssp126 as well**

```bash
Rscript tools/render_diagnostics_png.R data/plot-refactor-sanity/run3 mai ssp126 image gfdl-esm4
Rscript tools/render_diagnostics_png.R data/plot-refactor-sanity/run4 mai ssp126 image gfdl-esm4
(cd data/plot-refactor-sanity/run3 && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) > data/plot-refactor-sanity/run3.md5
(cd data/plot-refactor-sanity/run4 && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) > data/plot-refactor-sanity/run4.md5
diff data/plot-refactor-sanity/run3.md5 data/plot-refactor-sanity/run4.md5 && echo "DETERMINISTIC" || echo "NON-DETERMINISTIC"
```

Expected: `DETERMINISTIC`.

- [ ] **Step 4: If either check reports NON-DETERMINISTIC, stop and escalate**

Before proceeding, investigate the source of nondeterminism. Likely culprits: random sampling without a seed, timestamp-dependent labels, hash-ordered iteration. If no fix is obvious, switch to the `trace()`-based fallback described in the spec's "Step 0 sanity check" section. Do not proceed to baseline capture until the sanity check passes.

- [ ] **Step 5: Clean up sanity directory**

```bash
rm -rf data/plot-refactor-sanity
```

No commit for this task — it produces no code changes. The sanity directory is under ignored `data/`.

---

## Task 4: Capture the baseline

**Files:** none modified. PNGs stashed under ignored `data/`.

- [ ] **Step 1: Clear any previous baseline**

```bash
rm -rf data/plot-refactor-baseline
```

- [ ] **Step 2: Render baseline PNGs for both scenarios**

```bash
Rscript tools/render_diagnostics_png.R data/plot-refactor-baseline/histsoc mai histsoc
Rscript tools/render_diagnostics_png.R data/plot-refactor-baseline/ssp126  mai ssp126 image gfdl-esm4
```

Expected: both commands complete without error; `data/plot-refactor-baseline/histsoc/` and `data/plot-refactor-baseline/ssp126/` each contain one or more PNG files.

- [ ] **Step 3: Record baseline manifest**

```bash
(cd data/plot-refactor-baseline && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) > data/plot-refactor-baseline/manifest.md5
wc -l data/plot-refactor-baseline/manifest.md5
```

Expected: manifest file written; line count matches the number of PNGs produced across both scenarios.

No commit — baseline lives under ignored `data/`.

---

## Per-extraction verification procedure

Tasks 6–16 each end with the same verification procedure. Repeat this procedure exactly at every extraction:

```bash
# 1. PNG manifest check
rm -rf data/plot-refactor-current
Rscript tools/render_diagnostics_png.R data/plot-refactor-current/histsoc mai histsoc
Rscript tools/render_diagnostics_png.R data/plot-refactor-current/ssp126  mai ssp126 image gfdl-esm4
(cd data/plot-refactor-current && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) > data/plot-refactor-current/manifest.md5
diff data/plot-refactor-baseline/manifest.md5 data/plot-refactor-current/manifest.md5 && echo "PNG MANIFEST MATCH" || echo "PNG MANIFEST MISMATCH"

# 2. Test suite
Rscript tests/testthat.R 2>&1 | tail -20
```

**Gate:** The reviewer does not approve the extraction commit until all of the following hold:
1. The `diff` is empty (`PNG MANIFEST MATCH` line prints).
2. `Rscript tests/testthat.R` reports the same pass/fail counts as Task 5's baseline.

If either check fails, the writer fixes or reverts the extraction before proceeding — no exceptions.

---

## Task 5: Run the test suite once to confirm the baseline is green

Sanity-check that the unmodified codebase also passes the existing unit tests, so any later failure is clearly attributable to the refactor.

**Files:** none modified.

- [ ] **Step 1: Run the test suite**

```bash
Rscript tests/testthat.R 2>&1 | tail -20
```

Expected: tests complete without failures. Note the reported counts for comparison later.

No commit.

---

## Task 6: Extract `build_sample_locations` and wire the new module **(checkpoint task)**

Create the new module, extract the sample-locations data frame as the first function, and confirm the PNG manifest still matches. This validates the file layout and sourcing plumbing before proceeding.

**Files:**
- Create: `fertilizer_scaling_plot_diagnostics_functions.R`
- Modify: `fertilizer_scaling_functions.R` (add `source()` directive; replace inline sample-locations data frame with a function call)

- [ ] **Step 1: Create the new module with `build_sample_locations`**

Create `fertilizer_scaling_plot_diagnostics_functions.R` with this exact content:

```r
# ============================================================================
# Plot-diagnostics helpers extracted from plot_diagnostics()
# ============================================================================
# Sourced by fertilizer_scaling_functions.R. All functions assume that
# plot_diagnostics (in fertilizer_scaling_functions.R) has already opened
# the appropriate graphics device and set up par().
# ============================================================================

# ----------------------------------------------------------------------------
# build_sample_locations
# ----------------------------------------------------------------------------
# Returns the 10-row data frame of sample lat/lon/description values used
# for time-series plots and map overlays in plot_diagnostics.
# ----------------------------------------------------------------------------
build_sample_locations <- function() {
  data.frame(
    lat = c(8.0, 9.5, 26.0, -30.0, 40.0, 42.0, 30.0, 34.0, -15.0, -23.0),
    lon = c(-2.0, 37.0, 87.0, -60.0, -5.0, -93.5, 75.0, 114.0, -48.0, -47.0),
    description = c(
      "W Africa (Ghana)", "E Africa (Ethiopia)", "E India (Bihar)",
      "S Brazil (RS)", "N Spain", "US Iowa", "NW India (Punjab)",
      "N China (Henan)", "C Brazil (Mato Grosso)", "SE Brazil (SP)"
    ),
    stringsAsFactors = FALSE
  )
}
```

- [ ] **Step 2: Source the new module from `fertilizer_scaling_functions.R`**

Add the following line at the very top of `fertilizer_scaling_functions.R` (before the first function definition, after the header comment block):

```r
source("fertilizer_scaling_plot_diagnostics_functions.R")
```

This line goes at the top level so sourcing from anywhere still picks it up.

- [ ] **Step 3: Replace the inline `sample_locations` definition in `plot_diagnostics`**

In `fertilizer_scaling_functions.R`, locate the block at lines 572–581:

```r
  sample_locations <- data.frame(
    lat = c(8.0, 9.5, 26.0, -30.0, 40.0, 42.0, 30.0, 34.0, -15.0, -23.0),
    lon = c(-2.0, 37.0, 87.0, -60.0, -5.0, -93.5, 75.0, 114.0, -48.0, -47.0),
    description = c(
      "W Africa (Ghana)", "E Africa (Ethiopia)", "E India (Bihar)",
      "S Brazil (RS)", "N Spain", "US Iowa", "NW India (Punjab)",
      "N China (Henan)", "C Brazil (Mato Grosso)", "SE Brazil (SP)"
    ),
    stringsAsFactors = FALSE
  )
```

Replace the entire block with:

```r
  sample_locations <- build_sample_locations()
```

- [ ] **Step 4: Run PNG verification (per the procedure above)**

Expected: `PNG MANIFEST MATCH`.

- [ ] **Step 5: Run the test suite**

```bash
Rscript tests/testthat.R 2>&1 | tail -20
```

Expected: same pass/fail counts as Task 5's run.

- [ ] **Step 6: Commit**

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "$(cat <<'EOF'
Extract build_sample_locations from plot_diagnostics.

First extraction in the plot_diagnostics refactor. Creates the new
fertilizer_scaling_plot_diagnostics_functions.R module, sources it
from fertilizer_scaling_functions.R, and replaces the inline
sample_locations data frame with a call to build_sample_locations().

PNG manifest matches baseline.
EOF
)"
```

- [ ] **Step 7: CHECKPOINT — pause for user approval**

This is the spec's early-approval gate. Report to the user: the new module is in place, sourcing works, and the PNG-diff workflow has confirmed identical output. Wait for explicit approval before proceeding to Task 7.

---

## Task 7: Extract `add_sample_markers`

Promote the closure at lines 587–604 to a top-level function with an explicit signature.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (remove closure; update call sites in `plot_map`)

- [ ] **Step 1: Append `add_sample_markers` to the new module**

Append to `fertilizer_scaling_plot_diagnostics_functions.R`:

```r
# ----------------------------------------------------------------------------
# add_sample_markers
# ----------------------------------------------------------------------------
# Overlays numbered circle markers at each sample location on the currently
# active map. Caller is responsible for calling this only when a map is
# currently plotted.
#
# Args:
#   lon, lat: Grid-cell coordinate vectors for the map being overlaid.
#   sample_locations: Data frame from build_sample_locations().
# ----------------------------------------------------------------------------
add_sample_markers <- function(lon, lat, sample_locations) {
  for (k in 1:nrow(sample_locations)) {
    target_lon <- sample_locations$lon[k]
    target_lat <- sample_locations$lat[k]

    i <- which.min(abs(lon - target_lon))
    j <- which.min(abs(lat - target_lat))
    marker_lon <- lon[i]
    marker_lat <- lat[j]

    points(marker_lon, marker_lat, pch = 21, col = "black", bg = NA,
           cex = 1.5, lwd = 0.8)
    text(marker_lon, marker_lat, k, cex = 0.5, col = "black", font = 2)
  }
}
```

- [ ] **Step 2: Remove the closure from `plot_diagnostics`**

Delete lines 587–604 (the closure `add_sample_markers <- function() { ... }`) from `fertilizer_scaling_functions.R`. The outer `plot_map` closure still calls `add_sample_markers()` internally — leave that call as-is; we'll update it in Task 8 when `plot_map` itself is promoted. For now, the unqualified `add_sample_markers()` call inside `plot_map` resolves to the new top-level function via lexical scoping (globalenv via source), BUT it needs `lon`, `lat`, and `sample_locations` passed as arguments.

Because `plot_map` still closes over `lon`, `lat`, and `sample_locations` in this intermediate state, update its `add_sample_markers()` call site (inside `plot_map`, at the line that reads `add_sample_markers()`) to:

```r
add_sample_markers(lon, lat, sample_locations)
```

- [ ] **Step 3: Run PNG verification and tests**

Use the per-extraction verification procedure. Expected: `PNG MANIFEST MATCH`. Tests unchanged.

- [ ] **Step 4: Commit**

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract add_sample_markers from plot_diagnostics closure."
```

---

## Task 8: Extract `plot_map`

Promote the closure at lines 607–648 to a top-level function. This is the highest-risk extraction because `plot_map` previously captured `lon`, `lat`, and (indirectly) `sample_locations` from the enclosing scope.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (remove closure; update call sites throughout `plot_diagnostics`)

- [ ] **Step 1: Append `plot_map` to the new module**

Append to `fertilizer_scaling_plot_diagnostics_functions.R`:

```r
# ----------------------------------------------------------------------------
# plot_map
# ----------------------------------------------------------------------------
# Renders a single 2D map with symmetric or sequential color scaling.
# Optionally overlays sample-location markers.
#
# Args:
#   lon, lat: Grid-cell coordinate vectors.
#   data: [nlon x nlat] matrix to plot.
#   title: Plot title.
#   diverging: If TRUE, use a zero-centered diverging palette.
#   add_markers: If TRUE, overlay sample-location markers (requires
#     sample_locations to be non-NULL).
#   sample_locations: Data frame from build_sample_locations(). Required
#     when add_markers = TRUE.
# ----------------------------------------------------------------------------
plot_map <- function(lon, lat, data, title, diverging = FALSE,
                     add_markers = TRUE, sample_locations = NULL) {
  data_plot <- data[, c(length(lat):1)]

  valid_data <- data_plot[is.finite(data_plot) & abs(data_plot) < 1e+10]
  if (length(valid_data) > 0) {
    zlim <- range(valid_data, na.rm = TRUE)
    if (diverging) {
      max_abs <- max(abs(zlim), na.rm = TRUE)
      zlim <- c(-max_abs, max_abs)
    }
  } else {
    zlim <- c(0, 1)
  }

  if (diverging) {
    col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0",
                                    "#f7f7f7",
                                    "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)
  } else {
    col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0", "#fefebe",
                                    "#fddbc7", "#ef8a62", "#b2182b"))(100)
  }

  image.plot(lon, lat, data_plot,
             main = title,
             xlab = "Longitude", ylab = "Latitude",
             col = col_ramp,
             zlim = zlim,
             ylim = c(-65, 90))

  if (add_markers) {
    add_sample_markers(lon, lat, sample_locations)
  }
}
```

- [ ] **Step 2: Remove the `plot_map` closure from `plot_diagnostics`**

Delete the closure definition `plot_map <- function(lon, lat, data, title, diverging = FALSE, add_markers = TRUE) { ... }` (formerly at lines 607–648 of the original; search for its definition since intermediate extractions have shifted line numbers).

- [ ] **Step 3: Update every `plot_map(...)` call in `plot_diagnostics`**

Every existing `plot_map(lon, lat, ...)` call inside `plot_diagnostics` must be updated to pass `sample_locations` so the promoted function can reach it. There are five call sites. Replace each as follows:

```r
# Was:
plot_map(lon, lat, base_rate,
        paste(crop, "- Original Pattern (Year 2000) [Method:", method, "]"))
# Becomes:
plot_map(lon, lat, base_rate,
        paste(crop, "- Original Pattern (Year 2000) [Method:", method, "]"),
        sample_locations = sample_locations)

# Was:
plot_map(lon, lat, scaled_data[, , 1],
        paste(crop, "- Scaled Pattern (Year", start_year, ")"))
# Becomes:
plot_map(lon, lat, scaled_data[, , 1],
        paste(crop, "- Scaled Pattern (Year", start_year, ")"),
        sample_locations = sample_locations)

# Was:
plot_map(lon, lat, scaled_data[, , mid_idx],
        paste(crop, "- Scaled Pattern (Year", mid_year, ")"))
# Becomes:
plot_map(lon, lat, scaled_data[, , mid_idx],
        paste(crop, "- Scaled Pattern (Year", mid_year, ")"),
        sample_locations = sample_locations)

# Was:
plot_map(lon, lat, scaled_data[, , ntime],
        paste(crop, "- Scaled Pattern (Year", end_year, ")"))
# Becomes:
plot_map(lon, lat, scaled_data[, , ntime],
        paste(crop, "- Scaled Pattern (Year", end_year, ")"),
        sample_locations = sample_locations)

# Was:
plot_map(lon, lat, diff_map,
         paste(crop, "- Change (", end_year, "-", start_year, ")"),
         diverging = TRUE)
# Becomes:
plot_map(lon, lat, diff_map,
         paste(crop, "- Change (", end_year, "-", start_year, ")"),
         diverging = TRUE, sample_locations = sample_locations)
```

Confirm you caught all five with:

```bash
grep -n 'plot_map(' fertilizer_scaling_functions.R
```

All five matches should show `sample_locations = sample_locations`.

- [ ] **Step 4: Run PNG verification and tests**

Expected: `PNG MANIFEST MATCH`. If the manifest mismatches, the most likely cause is a missed call-site update — enumerate calls again and verify each passes `sample_locations`.

- [ ] **Step 5: Commit**

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_map from plot_diagnostics closure."
```

---

## Task 9: Extract `plot_aggregation_comparison`

Move the optional 4-panel aggregation-comparison page (lines 651–723 of the original).

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function to the new module**

Append to `fertilizer_scaling_plot_diagnostics_functions.R`:

```r
# ----------------------------------------------------------------------------
# plot_aggregation_comparison
# ----------------------------------------------------------------------------
# Renders a 4-panel aggregation-comparison page: original 5-arcmin data,
# aggregated 0.5-degree data, and their respective distribution histograms.
# Sets par(mfrow = c(2, 2)) on entry and resets to par(mfrow = c(4, 3),
# mar = c(4, 4, 3, 6)) on exit — caller relies on this reset.
# ----------------------------------------------------------------------------
plot_aggregation_comparison <- function(base_rate, spatial_data_5min, lon, lat,
                                        lon_5min, lat_5min, crop) {
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 6))

  valid_5min <- spatial_data_5min[is.finite(spatial_data_5min) & abs(spatial_data_5min) < 1e+10]
  if (length(valid_5min) > 0) {
    zlim_5min <- quantile(valid_5min, c(0.02, 0.98), na.rm = TRUE)
  } else {
    zlim_5min <- c(0, 1)
  }

  col_ramp <- colorRampPalette(c("#2166ac", "#67a9cf", "#d1e5f0", "#fefebe",
                                  "#fddbc7", "#ef8a62", "#b2182b"))(100)

  lat_5min_plot <- rev(lat_5min)
  data_5min_plot <- spatial_data_5min[, ncol(spatial_data_5min):1]
  image.plot(lon_5min, lat_5min_plot, data_5min_plot,
             main = paste(crop, "- Original 5-arcmin Data (full resolution)"),
             xlab = "Longitude", ylab = "Latitude",
             col = col_ramp,
             zlim = zlim_5min,
             ylim = c(-65, 90))

  data_halfdeg_plot <- base_rate[, c(length(lat):1)]
  valid_halfdeg <- data_halfdeg_plot[is.finite(data_halfdeg_plot) & abs(data_halfdeg_plot) < 1e+10]
  if (length(valid_halfdeg) > 0) {
    zlim_halfdeg <- quantile(valid_halfdeg, c(0.02, 0.98), na.rm = TRUE)
  } else {
    zlim_halfdeg <- c(0, 1)
  }

  image.plot(lon, lat, data_halfdeg_plot,
             main = paste(crop, "- Aggregated 0.5-degree Data"),
             xlab = "Longitude", ylab = "Latitude",
             col = col_ramp,
             zlim = zlim_halfdeg,
             ylim = c(-65, 90))

  if (length(valid_5min) > 0) {
    hist(valid_5min, breaks = 50, main = "5-arcmin Data Distribution",
         xlab = "N Rate (kg/ha)", col = "steelblue", border = "steelblue")
    legend("topright",
           legend = c(paste("N =", format(length(valid_5min), big.mark = ",")),
                      paste("mean =", sprintf("%.2f", mean(valid_5min, na.rm = TRUE))),
                      paste("median =", sprintf("%.2f", median(valid_5min, na.rm = TRUE))),
                      paste("max =", sprintf("%.2f", max(valid_5min, na.rm = TRUE)))),
           bty = "n", cex = 0.85)
  } else {
    plot.new(); text(0.5, 0.5, "No valid 5-arcmin data")
  }

  if (length(valid_halfdeg) > 0) {
    hist(valid_halfdeg, breaks = 50, main = "0.5-degree Aggregated Data Distribution",
         xlab = "N Rate (kg/ha)", col = "coral", border = "coral")
    legend("topright",
           legend = c(paste("N =", format(length(valid_halfdeg), big.mark = ",")),
                      paste("mean =", sprintf("%.2f", mean(valid_halfdeg, na.rm = TRUE))),
                      paste("median =", sprintf("%.2f", median(valid_halfdeg, na.rm = TRUE))),
                      paste("max =", sprintf("%.2f", max(valid_halfdeg, na.rm = TRUE)))),
           bty = "n", cex = 0.85)
  } else {
    plot.new(); text(0.5, 0.5, "No valid 0.5-degree data")
  }

  par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))
}
```

- [ ] **Step 2: Replace the block in `plot_diagnostics`**

Locate the block that starts with

```r
  # AGGREGATION COMPARISON: Show 5-minute vs 0.5-degree if data provided
  if (!is.null(spatial_data_5min) && !is.null(lon_5min) && !is.null(lat_5min)) {
```

and ends with

```r
    # Reset layout for remaining diagnostic plots
    par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))
  }
```

(originally lines 650–723). Replace the entire block with:

```r
  if (!is.null(spatial_data_5min) && !is.null(lon_5min) && !is.null(lat_5min)) {
    plot_aggregation_comparison(base_rate, spatial_data_5min, lon, lat,
                                lon_5min, lat_5min, crop)
  }
```

- [ ] **Step 3: Run PNG verification and tests**

Expected: `PNG MANIFEST MATCH`.

- [ ] **Step 4: Commit**

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_aggregation_comparison from plot_diagnostics."
```

---

## Task 10: Extract `plot_pattern_maps`

Move Plots 1–5 (original pattern + scaled first/middle/last + last-first difference map), originally lines 725–748.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

Append to `fertilizer_scaling_plot_diagnostics_functions.R`:

```r
# ----------------------------------------------------------------------------
# plot_pattern_maps
# ----------------------------------------------------------------------------
# Renders the five map panels: original pattern (year 2000), scaled first /
# middle / last, and the last-first difference map (diverging palette).
# ----------------------------------------------------------------------------
plot_pattern_maps <- function(base_rate, scaled_data, lon, lat, sample_locations,
                              start_year, end_year, mid_idx, crop, method) {
  ntime <- dim(scaled_data)[3]
  mid_year <- start_year + mid_idx - 1

  plot_map(lon, lat, base_rate,
           paste(crop, "- Original Pattern (Year 2000) [Method:", method, "]"),
           sample_locations = sample_locations)

  plot_map(lon, lat, scaled_data[, , 1],
           paste(crop, "- Scaled Pattern (Year", start_year, ")"),
           sample_locations = sample_locations)

  plot_map(lon, lat, scaled_data[, , mid_idx],
           paste(crop, "- Scaled Pattern (Year", mid_year, ")"),
           sample_locations = sample_locations)

  plot_map(lon, lat, scaled_data[, , ntime],
           paste(crop, "- Scaled Pattern (Year", end_year, ")"),
           sample_locations = sample_locations)

  first_year_data <- scaled_data[, , 1]
  last_year_data <- scaled_data[, , ntime]
  diff_map <- last_year_data - first_year_data

  plot_map(lon, lat, diff_map,
           paste(crop, "- Change (", end_year, "-", start_year, ")"),
           diverging = TRUE, sample_locations = sample_locations)
}
```

- [ ] **Step 2: Replace Plots 1–5 in `plot_diagnostics`**

Locate the block from the comment `plot_map(lon, lat, base_rate, paste(crop, "- Original Pattern ...` through the last `plot_map(lon, lat, diff_map, ..., diverging = TRUE, ...)` call — originally lines 725–748, now slightly shifted.

Replace the entire block with:

```r
  plot_pattern_maps(base_rate, scaled_data, lon, lat, sample_locations,
                    start_year, end_year, mid_idx, crop, method)
```

- [ ] **Step 3: Run PNG verification and tests**

Expected: `PNG MANIFEST MATCH`.

- [ ] **Step 4: Commit**

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_pattern_maps from plot_diagnostics."
```

---

## Task 11: Extract `plot_base_year_scatter`

Move Plot 6 (base-year scatter), originally lines 750–780.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

Append to `fertilizer_scaling_plot_diagnostics_functions.R`:

```r
# ----------------------------------------------------------------------------
# plot_base_year_scatter
# ----------------------------------------------------------------------------
# Renders a scatter plot of scaled vs original values at the base year,
# with 1:1 reference line and correlation / RMSE / bias legend.
# ----------------------------------------------------------------------------
plot_base_year_scatter <- function(base_rate, scaled_data, base_idx, base_year, crop) {
  ntime <- dim(scaled_data)[3]
  if (base_idx >= 1 && base_idx <= ntime) {
    scaled_base <- scaled_data[, , base_idx]
    valid <- is.finite(base_rate) & is.finite(scaled_base)
    if (any(valid)) {
      x <- base_rate[valid]
      y <- scaled_base[valid]
      plot(x, y, pch = 16, cex = 0.4,
           xlab = "Original (Year 2000)", ylab = "Scaled (Year 2000)",
           main = paste(crop, "- Scatter Year", base_year))
      abline(0, 1, col = "red", lwd = 2)
      if (length(x) > 1 && sd(x) > 0 && sd(y) > 0) {
        cor_val <- cor(x, y)
      } else {
        cor_val <- NA_real_
      }
      rmse <- sqrt(mean((y - x)^2))
      bias <- mean(y - x)
      legend("topleft",
             legend = c(paste("N =", length(x)),
                        sprintf("cor = %.3f", cor_val),
                        sprintf("RMSE = %.2f", rmse),
                        sprintf("Bias = %.2f", bias)),
             bty = "n")
    } else {
      plot.new(); text(0.5, 0.5, "No valid data for base-year scatter")
    }
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }
}
```

- [ ] **Step 2: Replace the Plot 6 block**

Locate the block starting with `# Plot 6: Base year scatter` and ending before `# Plot 7:`. Replace with:

```r
  plot_base_year_scatter(base_rate, scaled_data, base_idx, base_year, crop)
```

- [ ] **Step 3: Run PNG verification and tests; commit**

Expected: `PNG MANIFEST MATCH`.

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_base_year_scatter from plot_diagnostics."
```

---

## Task 12: Extract `plot_relative_change_hist`

Move Plot 7 (relative-change histogram), originally lines 782–804. Note: the existing code assigns `valid_rel_count` as a side effect — preserve that exact assignment so `plot_diagnostics` retains the variable even though it's never read after the split.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

The existing `valid_rel_count` variable is assigned but never used downstream. To stay strictly behavior-preserving, the extracted function returns it and the call site assigns it — mirroring the status quo.

```r
# ----------------------------------------------------------------------------
# plot_relative_change_hist
# ----------------------------------------------------------------------------
# Renders a histogram of per-cell relative change (last year / base year),
# with quantile legend. Returns the count of valid relative-change cells
# (preserved from the original code where it was assigned but unused).
# ----------------------------------------------------------------------------
plot_relative_change_hist <- function(scaled_data, base_idx, base_year, end_year, crop) {
  ntime <- dim(scaled_data)[3]
  valid_rel_count <- 0
  if (base_idx >= 1 && base_idx <= ntime) {
    scaled_base <- scaled_data[, , base_idx]
    scaled_last <- scaled_data[, , ntime]
    valid_rel <- is.finite(scaled_base) & is.finite(scaled_last) & scaled_base > 0
    if (any(valid_rel)) {
      rel_change <- scaled_last[valid_rel] / scaled_base[valid_rel]
      valid_rel_count <- length(rel_change)
      hist(rel_change, breaks = 40, main = paste(crop, "- Rel. Change", end_year, "vs", base_year),
           xlab = "Relative change (last/base)", col = "grey")
      stats <- quantile(rel_change, probs = c(0.05, 0.5, 0.95))
      abline(v = 1, col = "red", lwd = 2, lty = 2)
      legend("topright",
             legend = c(sprintf("N = %d", length(rel_change)),
                        sprintf("mean = %.2f", mean(rel_change)),
                        sprintf("p05/50/95 = %.2f / %.2f / %.2f", stats[1], stats[2], stats[3])),
             bty = "n")
    } else {
      plot.new(); text(0.5, 0.5, "No valid relative changes")
    }
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }
  invisible(valid_rel_count)
}
```

- [ ] **Step 2: Replace the Plot 7 block**

Locate the block starting with `# Plot 7: Relative change distribution` and ending before `# Plot 8:`. Replace with:

```r
  valid_rel_count <- plot_relative_change_hist(scaled_data, base_idx, base_year, end_year, crop)
```

- [ ] **Step 3: Run PNG verification and tests; commit**

Expected: `PNG MANIFEST MATCH`.

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_relative_change_hist from plot_diagnostics."
```

---

## Task 13: Extract `plot_spatial_ts_ratio`

Move Plot 8 (spatial-base vs TS-base ratio map), originally lines 806–856. Preserve the `print("Base/TS mismatch: ...")` console side effect exactly.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

```r
# ----------------------------------------------------------------------------
# plot_spatial_ts_ratio
# ----------------------------------------------------------------------------
# Renders a ratio map of spatial-base vs timeseries-base at the base year,
# with ratios capped to [0.2, 5] for visualization. Prints a console
# diagnostic line reporting cells that differ by more than 50%.
#
# The sample_locations arg matches the signature convention used by other
# map-producing section functions (parity with plot_pattern_maps, etc.).
# It is accepted but not overlaid on this particular map — the current
# code does not draw markers on the ratio map, and preserving output
# byte-for-byte means not adding any.
# ----------------------------------------------------------------------------
plot_spatial_ts_ratio <- function(base_rate, timeseries, base_idx, lon, lat,
                                  sample_locations, crop) {
  ntime <- dim(timeseries)[3]
  if (base_idx >= 1 && base_idx <= ntime) {
    ts_base <- timeseries[, , base_idx]

    valid_ratio <- is.finite(base_rate) & is.finite(ts_base) & base_rate > 0.1 & ts_base > 0.1

    if (any(valid_ratio)) {
      ratio_map <- array(NA, dim = dim(base_rate))
      ratio_map[valid_ratio] <- base_rate[valid_ratio] / ts_base[valid_ratio]

      ratio_capped <- ratio_map
      ratio_capped[ratio_capped > 5] <- 5
      ratio_capped[ratio_capped < 0.2] <- 0.2

      data_plot <- ratio_capped[, c(length(lat):1)]
      valid_data <- data_plot[is.finite(data_plot)]

      if (length(valid_data) > 0) {
        zlim <- c(0.2, 5)

        col_ramp <- colorRampPalette(c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0",
                                        "#f7f7f7",
                                        "#fddbc7", "#f4a582", "#d6604d", "#b2182b"))(100)

        image.plot(lon, lat, data_plot,
                   main = paste(crop, "- Spatial/TS Ratio (Year 2000)"),
                   xlab = "Longitude", ylab = "Latitude",
                   col = col_ramp,
                   zlim = zlim,
                   ylim = c(-65, 90))

        n_mismatch <- sum(abs(ratio_map - 1) > 0.5, na.rm = TRUE)
        n_total <- sum(valid_ratio)
        pct_mismatch <- 100 * n_mismatch / n_total
        print(paste("Base/TS mismatch: ", n_mismatch, " cells (",
                    round(pct_mismatch, 1), "%) differ by >50%", sep = ""))
      } else {
        plot.new(); text(0.5, 0.5, "No valid ratio data")
      }
    } else {
      plot.new(); text(0.5, 0.5, "No valid ratio data")
    }
  } else {
    plot.new(); text(0.5, 0.5, "Base year outside range")
  }
}
```

- [ ] **Step 2: Replace the Plot 8 block**

Locate the block starting with `# Plot 8: Extreme values diagnostic` and ending before `# Plot 9:`. Replace with:

```r
  plot_spatial_ts_ratio(base_rate, timeseries, base_idx, lon, lat, sample_locations, crop)
```

- [ ] **Step 3: Run PNG verification and tests; commit**

Expected: `PNG MANIFEST MATCH`. The `print` output ordering is preserved because the call site is in the same position as before.

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_spatial_ts_ratio from plot_diagnostics."
```

---

## Task 14: Extract `plot_sample_timeseries`

Move Plot 9 (time series at sample locations), originally lines 858–984, including the coordinate-system comment block at lines 863–896 and the `j_ts = length(lat) - j + 1` flip logic.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

Append to `fertilizer_scaling_plot_diagnostics_functions.R`. Function body is the original code from the comment `# Plot 9: Time series for predefined sample locations` through the closing brace of the `if (length(sample_cells) > 0) { ... } else { ... }` outer block. Signature:

```r
# ----------------------------------------------------------------------------
# plot_sample_timeseries
# ----------------------------------------------------------------------------
# Renders one line plot showing original vs scaled time series at each
# sample location. Coordinate-system-flip logic preserved verbatim from the
# original plot_diagnostics body because the flip reflects real index-order
# differences between the aggregated and ISIMIP3b arrays.
# ----------------------------------------------------------------------------
plot_sample_timeseries <- function(base_rate, scaled_data, timeseries, lon, lat,
                                   start_year, end_year, sample_locations, crop) {
  # ===== SAMPLE LOCATION TIME SERIES EXTRACTION =====
  #
  # IMPORTANT: Coordinate System Mismatch Between Datasets
  #
  # This script works with two different coordinate systems:
  #
  # 1. Aggregated data (base_rate, scaled_data):
  #    - Created by aggregating from 5 arcmin to 0.5 degree resolution
  #    - Latitude ordering: South -> North (-89.75 to 89.75)
  #    - Index j increases as latitude increases
  #
  # 2. Time series data (timeseries array):
  #    - From ISIMIP3b original files
  #    - Latitude ordering: North -> South (89.75 to -89.75)
  #    - Index j decreases as latitude increases
  #
  # VISUAL MAPPING:
  #    plot_map() function displays data with: data[, length(lat):1]
  #    This flips the lat dimension for display, so map position j_display = length(lat) - j_original
  #    The add_sample_markers() function correctly uses geographic coordinates (lon, lat)
  #    which display at the correct position on the map.
  #
  # TIME SERIES EXTRACTION:
  #    To extract time series data at a location that shows correctly on the map:
  #    j_ts = length(lat) - j + 1
  #    Then access: timeseries[i, j_ts, t] to get correct data
  #    Similarly: scaled_data[i, j_ts, t] (also uses timeseries indexing internally)
  #
  # EXAMPLE:
  #    If a location matches to j=199 in the South->North (aggregated) system,
  #    and length(lat)=360:
  #      j_ts = 360 - 199 + 1 = 162
  #      This correctly maps to the same geographic location in the North->South (ISIMIP) system

  sample_cells <- list()
  nlon <- length(lon)
  nlat <- length(lat)

  for (k in 1:nrow(sample_locations)) {
    target_lat <- sample_locations$lat[k]
    target_lon <- sample_locations$lon[k]

    i <- which.min(abs(lon - target_lon))
    j <- which.min(abs(lat - target_lat))

    actual_lon <- lon[i]
    actual_lat <- lat[j]

    # CRITICAL COORDINATE SYSTEM HANDLING:
    # - base_rate and scaled_data use lat from aggregation (South->North: -89.75 to 89.75)
    # - timeseries uses original ISIMIP lat ordering (North->South: 89.75 to -89.75)
    # - plot_map() flips lat for display: data[, length(lat):1]
    # - To extract time series at correct map location, flip j index: j_ts = length(lat) - j + 1
    j_ts <- length(lat) - j + 1

    sample_cells[[k]] <- list(
      i = i, j = j,
      j_ts = j_ts,
      actual_lon = actual_lon,
      actual_lat = actual_lat,
      description = sample_locations$description[k],
      base_rate_val = base_rate[i, j],
      ts_scaled = scaled_data[i, j_ts, ],
      ts_original = timeseries[i, j_ts, ]
    )
  }

  years <- start_year:end_year

  if (length(sample_cells) > 0) {
    all_values <- c()
    for (x in sample_cells) {
      ts_scaled <- x$ts_scaled[is.finite(x$ts_scaled)]
      ts_orig <- x$ts_original[is.finite(x$ts_original)]
      all_values <- c(all_values, ts_scaled, ts_orig)
    }

    if (length(all_values) > 0) {
      y_range <- range(all_values, na.rm = TRUE)
    } else {
      y_range <- c(0, 1)
    }

    if (all(is.finite(y_range))) {
      plot(years, scaled_data[1, 1, ], type = "n",
           ylim = y_range,
           main = paste(crop, "- Time Series at Sample Locations"),
           xlab = "Year", ylab = "N Fertilizer Rate (kg/ha)")

      colors <- rainbow(length(sample_cells))
      for (k in seq_along(sample_cells)) {
        cell <- sample_cells[[k]]
        lines(years, cell$ts_scaled, col = colors[k], lwd = 1)
        lines(years, cell$ts_original, col = colors[k], lwd = 0.8, lty = 2)
      }
      legend_labels <- sapply(seq_along(sample_cells), function(k) {
        cell <- sample_cells[[k]]
        sprintf("%s (%.1f\u00b0, %.1f\u00b0)", cell$description, cell$actual_lat, cell$actual_lon)
      })
      legend("topleft", legend = legend_labels,
             col = colors, lwd = 2, lty = 1, cex = 0.65, bg = "white")
    } else {
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "No valid time series data available", axes = FALSE)
      text(1, 1, "No cells with sufficient data found", cex = 1.2)
    }
  } else {
    plot(1, 1, type = "n", xlab = "", ylab = "", main = "No sample locations found", axes = FALSE)
    text(1, 1, "No cells with fertilizer application > 0.1 kg/ha", cex = 1.2)
  }
}
```

**IMPORTANT — degree symbol:** the original file contains a literal `°` character in the `sprintf` format string (line 971). When moving to the new file, preserve the literal character exactly as-is (not the `\u00b0` escape shown above) so the byte-for-byte output is identical. The escape above is shown only to avoid encoding hazards in this plan document. Verify by reading line 971 of the original `fertilizer_scaling_functions.R` and copying the exact bytes into the new function.

- [ ] **Step 2: Replace the Plot 9 block**

Locate the block starting with `# Plot 9: Time series for predefined sample locations` through the closing brace before `# Plot 10:`. Replace with:

```r
  plot_sample_timeseries(base_rate, scaled_data, timeseries, lon, lat,
                         start_year, end_year, sample_locations, crop)
```

- [ ] **Step 3: Run PNG verification and tests; commit**

Expected: `PNG MANIFEST MATCH`. If the manifest mismatches, the most likely cause is corruption of the `°` character — re-copy from the original.

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_sample_timeseries from plot_diagnostics."
```

---

## Task 15: Extract `plot_distribution_histograms`

Move Plots 10–12 (three overlay histograms), originally lines 986–1051.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

```r
# ----------------------------------------------------------------------------
# plot_distribution_histograms
# ----------------------------------------------------------------------------
# Renders three overlay histograms: spatial-base vs scaled-last,
# timeseries-base vs timeseries-last, and per-cell change deltas.
# ----------------------------------------------------------------------------
plot_distribution_histograms <- function(base_rate, scaled_data, timeseries,
                                         base_idx, base_year, end_year, crop) {
  ntime <- dim(scaled_data)[3]

  base_vals <- base_rate[is.finite(base_rate) & base_rate > 0]
  scaled_last_vals <- scaled_data[, , ntime][is.finite(scaled_data[, , ntime]) & scaled_data[, , ntime] > 0]

  if (length(base_vals) > 0 && length(scaled_last_vals) > 0) {
    x_range <- range(c(base_vals, scaled_last_vals), na.rm = TRUE)
    breaks_seq <- seq(x_range[1], x_range[2], length.out = 30)

    hist(base_vals, breaks = breaks_seq, col = rgb(0, 0, 1, 0.5),
         main = paste("Spatial Base vs Scaled"),
         xlab = "N Rate (kg/ha)", ylab = "Frequency",
         xlim = x_range)
    hist(scaled_last_vals, breaks = breaks_seq, col = rgb(1, 0, 0, 0.5), add = TRUE)

    legend("topright",
           legend = c(paste("Base", base_year), paste("Scaled", end_year)),
           fill = c(rgb(0, 0, 1, 0.5), rgb(1, 0, 0, 0.5)),
           cex = 0.8, bty = "n")
  } else {
    plot.new(); text(0.5, 0.5, "No data")
  }

  ts_base_vals <- timeseries[, , base_idx][is.finite(timeseries[, , base_idx]) & timeseries[, , base_idx] > 0]
  ts_last_vals <- timeseries[, , ntime][is.finite(timeseries[, , ntime]) & timeseries[, , ntime] > 0]

  if (length(ts_base_vals) > 0 && length(ts_last_vals) > 0) {
    x_range <- range(c(ts_base_vals, ts_last_vals), na.rm = TRUE)
    breaks_seq <- seq(x_range[1], x_range[2], length.out = 30)

    hist(ts_base_vals, breaks = breaks_seq, col = rgb(0, 0.6, 0, 0.5),
         main = paste("Original TS"),
         xlab = "N Rate (kg/ha)", ylab = "Frequency",
         xlim = x_range)
    hist(ts_last_vals, breaks = breaks_seq, col = rgb(1, 0.5, 0, 0.5), add = TRUE)

    legend("topright",
           legend = c(paste("TS", base_year), paste("TS", end_year)),
           fill = c(rgb(0, 0.6, 0, 0.5), rgb(1, 0.5, 0, 0.5)),
           cex = 0.8, bty = "n")
  } else {
    plot.new(); text(0.5, 0.5, "No data")
  }

  change_scaled <- (scaled_data[, , ntime] - base_rate)[is.finite(scaled_data[, , ntime] - base_rate)]
  change_ts <- (timeseries[, , ntime] - timeseries[, , base_idx])[is.finite(timeseries[, , ntime] - timeseries[, , base_idx])]

  if (length(change_scaled) > 0 && length(change_ts) > 0) {
    x_range <- range(c(change_scaled, change_ts), na.rm = TRUE)
    breaks_seq <- seq(x_range[1], x_range[2], length.out = 30)

    hist(change_scaled, breaks = breaks_seq, col = rgb(0.5, 0, 0.5, 0.5),
         main = paste("Changes:", end_year, "-", base_year),
         xlab = "Change in N Rate (kg/ha)", ylab = "Frequency",
         xlim = x_range)
    hist(change_ts, breaks = breaks_seq, col = rgb(0.7, 0.7, 0, 0.5), add = TRUE)
    abline(v = 0, col = "black", lwd = 2, lty = 2)

    legend("topright",
           legend = c("Scaled change", "TS change"),
           fill = c(rgb(0.5, 0, 0.5, 0.5), rgb(0.7, 0.7, 0, 0.5)),
           cex = 0.8, bty = "n")
  } else {
    plot.new(); text(0.5, 0.5, "No data")
  }
}
```

- [ ] **Step 2: Replace the Plots 10–12 block**

Locate the block from `# Plot 10: Histogram - Spatial base vs Scaled last` through the end of Plot 12 (before `# ---- Page 2 for additional diagnostics ----`). Replace with:

```r
  plot_distribution_histograms(base_rate, scaled_data, timeseries, base_idx,
                               base_year, end_year, crop)
```

- [ ] **Step 3: Run PNG verification and tests; commit**

Expected: `PNG MANIFEST MATCH`.

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_distribution_histograms from plot_diagnostics."
```

---

## Task 16: Extract `plot_outlier_scatter`

Move Plots 13–14 (scaling-factor-vs-final-value log scatter + outliers-only scatter), originally lines 1053–1181. Preserve the `cat(...)` console output exactly.

**Files:**
- Modify: `fertilizer_scaling_plot_diagnostics_functions.R` (append function)
- Modify: `fertilizer_scaling_functions.R` (replace block with a call)

- [ ] **Step 1: Append the function**

```r
# ----------------------------------------------------------------------------
# plot_outlier_scatter
# ----------------------------------------------------------------------------
# Renders two scatter plots on a new PDF page: scaling factor vs final
# value with log-scale y-axis, and an outliers-only detail scatter with
# coloring by base-rate quartile. Prints analysis stats to the console.
# ----------------------------------------------------------------------------
plot_outlier_scatter <- function(base_rate, scaled_data, timeseries,
                                 base_idx, base_year, end_year) {
  ntime <- dim(scaled_data)[3]

  scaling_factors <- (timeseries[, , ntime] / timeseries[, , base_idx])
  final_values <- scaled_data[, , ntime]

  sf_flat <- as.vector(scaling_factors)
  fv_flat <- as.vector(final_values)
  valid_mask <- is.finite(sf_flat) & is.finite(fv_flat) &
                sf_flat > 0 & sf_flat < Inf & fv_flat > 0

  sf_valid <- sf_flat[valid_mask]
  fv_valid <- fv_flat[valid_mask]

  if (length(sf_valid) > 100) {
    outlier_threshold <- 1000
    is_outlier <- fv_valid > outlier_threshold

    point_colors <- ifelse(is_outlier, rgb(1, 0, 0, 0.7), rgb(0, 0, 1, 0.2))

    plot(sf_valid, fv_valid,
         pch = 16, cex = 0.4, col = point_colors,
         log = "y",
         main = paste("Scaling Factor vs Final Value - Log Scale (", end_year, ")", sep = ""),
         xlab = paste("Scaling Factor (", end_year, "/", base_year, ")", sep = ""),
         ylab = paste("Final Scaled Value (kg/ha, ", end_year, ") [LOG SCALE]", sep = ""))

    abline(v = 1, col = "gray50", lwd = 2, lty = 2)
    abline(h = outlier_threshold, col = "red", lwd = 2, lty = 2)

    n_outliers <- sum(is_outlier)
    pct_outliers <- 100 * n_outliers / length(fv_valid)
    median_sf_normal <- median(sf_valid[!is_outlier], na.rm = TRUE)
    median_sf_outlier <- if(n_outliers > 0) median(sf_valid[is_outlier], na.rm = TRUE) else NA

    legend("bottomright",
           legend = c(
             paste("Normal (n=", format(sum(!is_outlier), big.mark = ","), ")", sep = ""),
             paste("Outliers >", outlier_threshold, " (n=", format(n_outliers, big.mark = ","), ")", sep = ""),
             paste("Med SF normal:", sprintf("%.2f", median_sf_normal)),
             if(!is.na(median_sf_outlier)) paste("Med SF outliers:", sprintf("%.2f", median_sf_outlier)) else NULL
           ),
           col = c(rgb(0, 0, 1, 0.6), rgb(1, 0, 0, 0.7), NA, NA),
           pch = c(16, 16, NA, NA),
           cex = 0.7, bty = "n")

    cat("\n=== Scaling Factor vs Outlier Analysis ===\n")
    cat(sprintf("Total cells: %s\n", format(length(fv_valid), big.mark = ",")))
    cat(sprintf("Outliers (>%d kg/ha): %s (%.1f%%)\n",
                outlier_threshold, format(n_outliers, big.mark = ","), pct_outliers))
    cat(sprintf("Median scaling factor (normal): %.2f\n", median_sf_normal))
    if (n_outliers > 0) {
      cat(sprintf("Median scaling factor (outliers): %.2f\n", median_sf_outlier))
      cat(sprintf("Range of outlier values: %.0f - %.0f kg/ha\n",
                  min(fv_valid[is_outlier], na.rm = TRUE),
                  max(fv_valid[is_outlier], na.rm = TRUE)))
      cat(sprintf("Range of outlier scaling factors: %.2f - %.2f\n",
                  min(sf_valid[is_outlier], na.rm = TRUE),
                  max(sf_valid[is_outlier], na.rm = TRUE)))
    }

  } else {
    plot.new()
    text(0.5, 0.5, "Insufficient data for scatter plot")
  }

  if (length(sf_valid) > 100 && sum(is_outlier) > 0) {
    sf_outliers <- sf_valid[is_outlier]
    fv_outliers <- fv_valid[is_outlier]

    base_flat <- as.vector(base_rate)
    base_valid <- base_flat[valid_mask]
    base_outliers <- base_valid[is_outlier]

    base_quartiles <- quantile(base_outliers, probs = c(0.25, 0.5, 0.75), na.rm = TRUE)
    outlier_colors <- ifelse(base_outliers < base_quartiles[1], rgb(1, 0.8, 0, 0.6),
                       ifelse(base_outliers < base_quartiles[2], rgb(1, 0.5, 0, 0.6),
                       ifelse(base_outliers < base_quartiles[3], rgb(1, 0.2, 0, 0.6),
                              rgb(0.8, 0, 0, 0.6))))

    plot(sf_outliers, fv_outliers,
         pch = 16, cex = 0.8, col = outlier_colors,
         main = paste("OUTLIERS ONLY: Scaling Factor vs Final Value (", end_year, ")", sep = ""),
         xlab = paste("Scaling Factor (", end_year, "/", base_year, ")", sep = ""),
         ylab = paste("Final Scaled Value (kg/ha, ", end_year, ")", sep = ""))

    abline(v = 1, col = "gray50", lwd = 2, lty = 2)

    cor_outliers <- cor(sf_outliers, fv_outliers, use = "complete.obs")

    legend("topright",
           legend = c(
             paste("n =", format(length(sf_outliers), big.mark = ",")),
             paste("Correlation:", sprintf("%.3f", cor_outliers)),
             "",
             "Base rate (2000) quartiles:",
             paste("Q1:", sprintf("%.0f", base_quartiles[1])),
             paste("Q2:", sprintf("%.0f", base_quartiles[2])),
             paste("Q3:", sprintf("%.0f", base_quartiles[3]))
           ),
           col = c(NA, NA, NA, NA,
                   rgb(1, 0.8, 0, 0.6), rgb(1, 0.5, 0, 0.6),
                   rgb(1, 0.2, 0, 0.6)),
           pch = c(NA, NA, NA, NA, 16, 16, 16),
           cex = 0.7, bty = "n")

    cat(sprintf("\n=== Outlier Detail Analysis ===\n"))
    cat(sprintf("Correlation (SF vs final value) for outliers: %.3f\n", cor_outliers))
    cat(sprintf("Base rate range for outliers: %.0f - %.0f kg/ha\n",
                min(base_outliers, na.rm = TRUE),
                max(base_outliers, na.rm = TRUE)))

  } else if (length(sf_valid) > 100) {
    plot.new()
    text(0.5, 0.5, "No outliers to display")
  }
}
```

- [ ] **Step 2: Replace the Plots 13–14 block**

Locate the block from `# ---- Page 2 for additional diagnostics ----` through the end of Plot 14 (before the final `dev.off()`). Replace with:

```r
  plot_outlier_scatter(base_rate, scaled_data, timeseries, base_idx, base_year, end_year)
```

- [ ] **Step 3: Run PNG verification and tests; commit**

Expected: `PNG MANIFEST MATCH`.

```bash
git add fertilizer_scaling_plot_diagnostics_functions.R fertilizer_scaling_functions.R
git commit -m "Extract plot_outlier_scatter from plot_diagnostics."
```

---

## Task 17: Final review of `plot_diagnostics`

At this point `plot_diagnostics` should be a short orchestrator. Read it with fresh eyes, confirm it matches the spec's "What stays" list, and verify the line count.

**Files:**
- Read-only: `fertilizer_scaling_functions.R`

- [ ] **Step 1: Measure `plot_diagnostics` length**

```bash
awk '/^plot_diagnostics <- function/{flag=1} flag{print; if (/^\}$/){flag=0; exit}}' fertilizer_scaling_functions.R | wc -l
```

Expected: between 30 and 50 lines (inclusive of function signature and closing brace).

- [ ] **Step 2: Diff check that `plot_diagnostics` contains only the "what stays" elements**

Visually inspect the function body. It should contain (in order):

1. Output-path construction (`plot_file <- paste0(...)` branch on `scenario == "histsoc"` vs future).
2. `pdf(plot_file, width = 16, height = 14)`.
3. Computation of `ntime`, `mid_idx`, `base_idx`.
4. `sample_locations <- build_sample_locations()`.
5. Initial `par(mfrow = c(4, 3), mar = c(4, 4, 3, 6))`.
6. Conditional call to `plot_aggregation_comparison`.
7. Sequential calls to the nine plot-section functions.
8. `dev.off()`.

If any extraction has left residual code that belongs in one of the section functions, move it now as a small follow-up commit — but only if it's truly leftover. Do not restructure otherwise.

- [ ] **Step 3: Final PNG verification and tests**

Run the verification procedure one last time. Expected: `PNG MANIFEST MATCH`.

```bash
Rscript tests/testthat.R 2>&1 | tail -20
```

Expected: same pass/fail counts as Task 5's run.

- [ ] **Step 4: If leftover code was moved, commit; otherwise no-op**

```bash
git status
```

If clean, proceed. If there are changes:

```bash
git add -u
git commit -m "Move residual plot_diagnostics code into extracted functions."
```

---

## Task 18: Merge back to main with `--no-ff`

**Files:** no files modified — this is a git merge.

- [ ] **Step 1: Switch out of the worktree to main**

```bash
cd /workspace
git checkout main
git status
```

Expected: clean, on main.

- [ ] **Step 2: Merge the refactor branch with `--no-ff`**

```bash
git merge --no-ff refactor/plot-diagnostics -m "$(cat <<'EOF'
Merge branch 'refactor/plot-diagnostics'.

Refactor plot_diagnostics from a 647-line function with two nested
closures into a thin ~30-50 line orchestrator that delegates to 11
named top-level functions in fertilizer_scaling_plot_diagnostics_functions.R.

Output is byte-identical: PNG manifest generated via the verification
harness in tools/render_diagnostics_png.R matched the baseline at
every extraction commit.
EOF
)"
```

Expected: merge commit created, feature-branch grouping preserved in the graph.

- [ ] **Step 3: Verify the merge commit graph**

```bash
git log --oneline --graph -20
```

Expected: the feature-branch commits appear as a diverged branch merged back into main with a merge commit at the tip.

- [ ] **Step 4: Remove the worktree and delete the merged branch**

```bash
git worktree remove /home/node/worktrees/plot-diagnostics-refactor
git branch -d refactor/plot-diagnostics
```

Expected: worktree cleaned up, branch deleted (since all commits are reachable from main via the merge).

---

## Spec-coverage sanity check

Each spec requirement mapped to a task:

| Spec requirement | Task(s) |
|---|---|
| Create `fertilizer_scaling_plot_diagnostics_functions.R` | Task 6 |
| Source new module from `fertilizer_scaling_functions.R` | Task 6 |
| `build_sample_locations` | Task 6 |
| `add_sample_markers` | Task 7 |
| `plot_map` | Task 8 |
| `plot_aggregation_comparison` | Task 9 |
| `plot_pattern_maps` | Task 10 |
| `plot_base_year_scatter` | Task 11 |
| `plot_relative_change_hist` | Task 12 |
| `plot_spatial_ts_ratio` | Task 13 |
| `plot_sample_timeseries` | Task 14 |
| `plot_distribution_histograms` | Task 15 |
| `plot_outlier_scatter` | Task 16 |
| Slim `plot_diagnostics` (~30–50 lines) | Task 17 |
| Worktree-based work | Task 1, Task 18 |
| `--no-ff` merge | Task 18 |
| PNG-shadowing verification harness | Task 2 |
| Step 0 determinism sanity check | Task 3 |
| Baseline capture under `data/plot-refactor-baseline/` | Task 4 |
| Per-extraction PNG manifest check | Tasks 6–16 |
| Early approval gate | Task 6 Step 7 |
| Subagent-driven writer → reviewer → commit | subagent-driven-development skill wraps every extraction task |
| Commit-per-step, split logically distinct changes | each Task's commit step |
| No touching `run_diagnostics_external.R` / `compare_histsoc_future.R` | scope — no task modifies them |
