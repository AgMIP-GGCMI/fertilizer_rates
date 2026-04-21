---
title: Automated PNG regression tests for plot_diagnostics
date: 2026-04-21
status: draft
---

# Automated PNG regression tests for `plot_diagnostics`

## Goal

Promote the one-shot PNG verification harness used during the
`plot_diagnostics` refactor into a committed, automated regression test
that runs as part of the default `testthat` suite. Guarantee the
diagnostic plots produced for two reference scenarios stay
byte-identical to committed baselines, and provide a `fast` runner for
rapid iteration that skips the slow rendering work.

## Scope

- Integrate a PNG-regression test into the existing `testthat` test
  suite using `testthat::expect_snapshot_file()`.
- Commit baseline PNGs (18 files, ~3.6 MB) and the manifest produced by
  the existing harness.
- Split the runner into two entry points: `tests/testthat.R` (default,
  runs all tests) and `tests/testthat-fast.R` (skips the slow
  rendering tests).
- Make the environment reproducible enough to trust byte-identity by
  explicitly apt-installing `libcairo2` and `libpng16-16` in the
  devcontainer Dockerfile.
- Add a `## Testing` section to `README.md` documenting the runners,
  the snapshot-review workflow, the baseline-regeneration command, and
  the environment caveat.

## Non-goals

- No side-by-side diff composite image on test failure (tracked in
  Next Steps).
- No expansion of the test scope beyond the two reference scenarios
  already used by the harness. Extending to other crops / SSPs is a
  future enhancement.
- No CI configuration. The test is integrated into the local
  `testthat` suite; hooking it into a CI pipeline is out of scope for
  this change.
- No version-pinning of apt packages beyond whatever the pinned
  `rocker/r-ver:4.5.0` base image resolves to at build time.

## Architecture

### File layout

**New files:**

- `tools/diagnostics_png_harness.R` — pure function library. Defines
  `render_diagnostics_to_png(png_output_dir, crop, scenario, iam = NULL, gcm = NULL)`
  with no side effects when sourced. Houses the `pdf → png` shadowing
  logic currently inlined in `tools/render_diagnostics_png.R`.
- `tests/_runner_common.R` — shared `run_tests(fast_only)` helper.
- `tests/testthat-fast.R` — CLI entry point that skips the slow
  PNG-regression tests.
- `tests/testthat-slow/` — new test directory.
- `tests/testthat-slow/setup.R` — mirrors `tests/testthat/setup.R`;
  sources `fertilizer_scaling_functions.R`.
- `tests/testthat-slow/test-plot_diagnostics_regression.R` — the
  regression test. Renders both reference scenarios into temp dirs and
  calls `expect_snapshot_file()` on each produced PNG.
- `tests/testthat-slow/_snaps/plot_diagnostics_regression/` — 18
  committed baseline PNGs organized per testthat's snapshot convention.
  Created automatically on first successful run.
- `tools/accept_diagnostics_baseline.R` — thin wrapper around
  `testthat::snapshot_accept("plot_diagnostics_regression")` for
  convenient intentional baseline updates.

**Modified files:**

- `tools/render_diagnostics_png.R` — simplified to a thin CLI wrapper
  that sources `tools/diagnostics_png_harness.R` and calls
  `render_diagnostics_to_png()`. External behavior (CLI args, output
  structure) unchanged.
- `tests/testthat.R` — replaces the current body with a two-line
  bootstrap that sources `_runner_common.R` and calls
  `run_tests(fast_only = FALSE)`.
- `.devcontainer/Dockerfile` — extends the existing apt-install block
  with `libcairo2` and `libpng16-16`, matching the comment style used
  for the existing `ncdf4`/`fields`/`lintr` system deps.
- `README.md` — new `## Testing` section.

### Harness refactor

The existing `tools/render_diagnostics_png.R` runs its body at source
time, which makes it painful to reuse from a test. The refactor splits
the file:

**`tools/diagnostics_png_harness.R`** (new, function library):

```r
# Shadows grDevices::pdf with a cairo-backed png() so multi-page PDFs
# become byte-comparable PNGs. Designed to be sourced without side
# effects; callers invoke render_diagnostics_to_png() explicitly.

.HARNESS_PNG_DPI <- 100

render_diagnostics_to_png <- function(png_output_dir, crop, scenario,
                                      iam = NULL, gcm = NULL) {
  dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

  scaling_args <- c(crop, scenario, iam, gcm)

  local({
    commandArgs <- function(trailingOnly = FALSE) {
      if (trailingOnly) scaling_args else c("Rscript", "fertilizer_scaling.R", scaling_args)
    }
    pdf <- function(file, width = 7, height = 7, ...) {
      base <- sub("\\.pdf$", "", basename(file))
      pattern <- file.path(png_output_dir, paste0(base, "-%03d.png"))
      grDevices::png(filename = pattern,
                     width = round(width * .HARNESS_PNG_DPI),
                     height = round(height * .HARNESS_PNG_DPI),
                     type = "cairo",
                     res = .HARNESS_PNG_DPI)
    }
    source("fertilizer_scaling.R", local = FALSE)
  })
}
```

Notes on behavior preservation:

- The `local()` wrapper isolates the `commandArgs` and `pdf` shadow
  bindings so they don't leak into the caller's global environment.
  The current harness defines them at top-level; wrapping in `local()`
  is a small behavior change *for the harness* (not for
  `plot_diagnostics`) — the renders themselves remain byte-identical
  because R's lexical scoping still routes `plot_diagnostics`'s
  `pdf(...)` call through the shadow during the `source()` call.
- The eventual `source("fertilizer_scaling.R", local = FALSE)` loads
  and runs `main(...)` exactly as the current harness does.
- If byte-identity verification against the existing 18-file baseline
  fails after the `local()` restructuring, the fallback is to keep
  `pdf` and `commandArgs` assigned at globalenv level (matching today)
  via `assign(..., envir = globalenv())` inside the function.

**`tools/render_diagnostics_png.R`** (simplified CLI wrapper):

```r
#!/usr/bin/env Rscript
# Thin CLI wrapper around render_diagnostics_to_png(). See
# tools/diagnostics_png_harness.R for the shadowing logic.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]")
}

source("tools/diagnostics_png_harness.R")
render_diagnostics_to_png(
  png_output_dir = args[1],
  crop = args[2],
  scenario = args[3],
  iam = if (length(args) >= 4) args[4] else NULL,
  gcm = if (length(args) >= 5) args[5] else NULL
)
```

### Test structure

**`tests/testthat-slow/setup.R`** mirrors `tests/testthat/setup.R`:

```r
source(
  testthat::test_path("..", "..", "fertilizer_scaling_functions.R"),
  chdir = TRUE
)
```

**`tests/testthat-slow/test-plot_diagnostics_regression.R`:**

```r
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

**Reference scenarios:**

- `mai histsoc` — exercises the historical path (`1850–2014` filename
  branch, `spatial_data_5min` present).
- `mai ssp126 image gfdl-esm4` — exercises the future path (IAM + GCM
  filename branch).

Each scenario produces 9 PNGs (3 PDFs × 3 pages each). Total snapshot
footprint: 18 files, approximately 3.6 MB committed to git under
`tests/testthat-slow/_snaps/plot_diagnostics_regression/`.

### Runner scripts

**`tests/_runner_common.R`:**

```r
library(testthat)

run_tests <- function(fast_only = FALSE) {
  tests_dir <- dirname(normalizePath(sub("^--file=", "",
    grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
  testthat::test_dir(file.path(tests_dir, "testthat"))
  slow_dir <- file.path(tests_dir, "testthat-slow")
  if (!fast_only && dir.exists(slow_dir)) {
    testthat::test_dir(slow_dir)
  }
}
```

The `dir.exists(slow_dir)` guard keeps `run_tests` resilient when the
slow-tests directory is missing (e.g., between Step 2 and Step 3 of
the execution plan, or in a hypothetical future state where slow tests
are removed).

**`tests/testthat.R`** (full suite — default):

```r
source(sub("testthat(-fast)?\\.R$", "_runner_common.R", sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
run_tests(fast_only = FALSE)
```

**`tests/testthat-fast.R`** (fast tests only):

```r
source(sub("testthat(-fast)?\\.R$", "_runner_common.R", sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
run_tests(fast_only = TRUE)
```

The `sub(...)` regex `testthat(-fast)?\\.R$` rewrites either runner's
own filename to `_runner_common.R`. The bootstrap line is verbatim
identical in both runners.

### Baseline acceptance

**`tools/accept_diagnostics_baseline.R`:**

```r
#!/usr/bin/env Rscript
# Accept the current plot_diagnostics_regression PNG snapshots as the
# new baseline. Only run after intentionally changing diagnostic output.

setwd(file.path(dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1]))), "..", "tests"))
library(testthat)
testthat::snapshot_accept("plot_diagnostics_regression")
```

### Environment reproducibility

**Dockerfile change.** Add `libcairo2` and `libpng16-16` to the
existing apt-install block at `.devcontainer/Dockerfile:11–38`:

```diff
     libnetcdf-dev \
     libhdf5-dev \
     libudunits2-dev \
     libuv1-dev \
     libxml2-dev \
     libssl-dev \
     libcurl4-openssl-dev \
+    libcairo2 \
+    libpng16-16 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
```

The comment two lines above the block already reads "System tooling
(Anthropic's reference set) + system libs for R packages used by this
repo (ncdf4, fields, lintr)." We extend it: `"... (ncdf4, fields,
lintr, and cairo/png rendering for the PNG regression tests)"`.

**Reproducibility caveats** (documented in README):

- Byte-identity is guaranteed only inside this repo's devcontainer.
- Rebuilding the devcontainer image may pick up newer transitive
  versions of `libcairo2` / `libpng16-16` from Debian's archive; if
  that ever produces different-but-valid PNGs, regenerate the baseline
  via `tools/accept_diagnostics_baseline.R`.
- The R package layer is pinned by `renv.lock`.
- The base OS + R layer is pinned by `rocker/r-ver:4.5.0`.

### README changes

New section added after the existing `## First-run inside the
container` section:

```markdown
## Testing

Run the full test suite (unit tests + PNG regression tests):

    Rscript tests/testthat.R

The PNG regression tests render diagnostic plots for two reference
scenarios (`mai histsoc` and `mai ssp126 image gfdl-esm4`) and compare
them byte-for-byte against committed baseline PNGs. Each scenario
takes ~30–40 seconds, so the full suite takes a few minutes.

To skip the slow tests during rapid iteration:

    Rscript tests/testthat-fast.R

### When a PNG snapshot fails

testthat writes the mismatched render to
`tests/testthat-slow/_snaps/plot_diagnostics_regression/<name>.new.png`
alongside the baseline. To review in R:

    > testthat::snapshot_review("plot_diagnostics_regression")

If the change is intentional, accept the new baseline:

    Rscript tools/accept_diagnostics_baseline.R

Then commit the updated snapshot files alongside the code change that
produced them.

### Environment caveat

Byte-identical PNG output is guaranteed only inside this repo's
devcontainer (`rocker/r-ver:4.5.0` base image + pinned apt cairo/png
libs + `renv`-locked R packages). Runs outside the container may
produce legitimate pixel differences and will need fresh baselines
captured in the devcontainer environment.
```

## Risks and determinism notes

- **Harness `local()` restructuring.** Moving `pdf` / `commandArgs`
  shadows from global env into a `local()` block is a small behavior
  change *for the harness*. Byte-identity against the existing
  18-snapshot baseline must be verified before committing baselines;
  if the restructuring fails, fall back to globalenv shadows.
- **Snapshot file names.** `expect_snapshot_file(path, name = png)`
  uses `png` (basename) as the committed snapshot name. Current PNG
  basenames include scenario-encoded paths like
  `n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2100_diagnostics-003.png`
  — long but stable. No collisions between the two scenarios because
  basenames differ.
- **`withr::with_dir` dependency.** `withr` is in `renv.lock` already
  (testthat depends on it transitively). If it isn't, we drop in a
  one-line equivalent using `setwd(...); on.exit(setwd(old))`.
- **Snapshot baselines as binary files in git.** Adds ~3.6 MB one-time
  to the repo. Binary diffs show as "binary files differ" in git log;
  acceptable cost for the ability to visually review regressions.
- **Test-suite wall clock.** Full `Rscript tests/testthat.R` grows
  from ~2 seconds to ~2 minutes. The fast runner exists exactly for
  iteration loops that can't afford that.

## Execution plan

Work happens on a dedicated git worktree, merged back to main with
`git merge --no-ff` per the project's convention.

Every numbered step is at least one commit; logically distinct changes
within a step are split into separate commits. Each step uses an
explicit subagent-driven writer → reviewer → commit cycle.

### Step 1: Worktree and harness refactor

1. Create worktree.
2. Create `tools/diagnostics_png_harness.R` with the
   `render_diagnostics_to_png()` function.
3. Simplify `tools/render_diagnostics_png.R` to source the harness
   and delegate.
4. Verify the existing refactor-era baseline (18 PNGs) still renders
   byte-identically. Because the existing baseline was generated with
   the pre-refactor harness, this confirms the `local()` restructuring
   doesn't change output.
5. Writer → reviewer → commit (two commits: add the harness file, then
   simplify the CLI wrapper).

**Checkpoint: pause for user approval before proceeding.** Validates
the harness factoring works.

### Step 2: Runner split

1. Create `tests/_runner_common.R`.
2. Rewrite `tests/testthat.R` to source the common file and call
   `run_tests(fast_only = FALSE)`.
3. Create `tests/testthat-fast.R` with `fast_only = TRUE`.
4. Verify `Rscript tests/testthat.R` and `Rscript tests/testthat-fast.R`
   both run (still 194 existing passes for each — the slow dir doesn't
   exist yet, but the `dir.exists()` guard in `run_tests` keeps the
   full-suite runner from erroring on the missing path).
5. Writer → reviewer → commit.

### Step 3: Slow-test scaffolding

1. Create `tests/testthat-slow/` with `setup.R`.
2. Create `tests/testthat-slow/test-plot_diagnostics_regression.R`
   following the design above.
3. Writer → reviewer → commit.

### Step 4: Capture and commit baselines

1. Run `Rscript tests/testthat.R` for the first time. The snapshot
   test records fresh baselines under
   `tests/testthat-slow/_snaps/plot_diagnostics_regression/` and
   passes (testthat's first-run-is-baseline behavior).
2. Inspect the committed PNGs visually (they should match the plots
   produced by the reference commands).
3. `git add` the `_snaps/` directory and commit.
4. Re-run the suite to confirm subsequent runs pass against the now-
   committed baselines.
5. Writer → reviewer → commit.

### Step 5: Acceptance wrapper

1. Create `tools/accept_diagnostics_baseline.R`.
2. Smoke-test by running the wrapper once against the now-clean
   baselines; confirm it exits 0 without modifying any files
   (accepting already-accepted snapshots is a no-op).
3. Writer → reviewer → commit.

### Step 6: Devcontainer system libs

1. Edit `.devcontainer/Dockerfile` to add `libcairo2` and
   `libpng16-16` to the existing apt-install block.
2. Update the preceding comment to list cairo/png alongside the other
   deps.
3. Do not rebuild the devcontainer as part of this step — the current
   running container already has whatever cairo/png the rocker base
   provides; the change documents intent for future rebuilds.
4. Writer → reviewer → commit.

### Step 7: README Testing section

1. Add the `## Testing` section to README.md after the existing
   first-run section.
2. Writer → reviewer → commit.

### Step 8: Final review and merge

1. Re-run the full suite one final time; confirm `PASS 194 +
   snapshot-count`.
2. Reviewer confirms spec alignment.
3. Merge to main with `git merge --no-ff`.
4. Remove worktree and delete merged branch.

## Next steps (out of scope)

- **Side-by-side diff composite image.** On snapshot failure, generate
  an auto-composited `old | new | diff-mask` PNG per failing page so
  regressions can be eyeballed at a glance without opening two files.
  Requires an image-diff helper (R `magick` package or Python
  Pillow); defer until the basic snapshot flow is in use and we know
  how often it actually fires.
- **Broader scenario coverage.** Extend the snapshot matrix to more
  crops / SSPs / IAM / GCM combinations. The infrastructure this spec
  adds is linear in scenario count; once stable, adding more is a
  mechanical edit to the test file plus a one-time baseline capture.
- **CI integration.** Run `Rscript tests/testthat.R` on pull requests
  via a hosted runner that builds the devcontainer image. Out of
  scope here; the local test is the prerequisite.
- **Deterministic image-diff tooling in the devcontainer.**
  Pre-install `magick` / `imagemagick` / `poppler-utils` to enable
  richer failure diagnostics. Not needed for the basic `.new.png`
  flow.

## File-by-file summary

| File | Change |
|---|---|
| `tools/diagnostics_png_harness.R` | Create (function library). |
| `tools/render_diagnostics_png.R` | Simplify to thin CLI wrapper. |
| `tools/accept_diagnostics_baseline.R` | Create (acceptance wrapper). |
| `tests/_runner_common.R` | Create (shared `run_tests`). |
| `tests/testthat.R` | Replace body with 2-line bootstrap + `run_tests(FALSE)`. |
| `tests/testthat-fast.R` | Create (2-line bootstrap + `run_tests(TRUE)`). |
| `tests/testthat-slow/setup.R` | Create (mirrors fast setup). |
| `tests/testthat-slow/test-plot_diagnostics_regression.R` | Create (the test). |
| `tests/testthat-slow/_snaps/plot_diagnostics_regression/*.png` | 18 baseline PNGs committed. |
| `.devcontainer/Dockerfile` | Add `libcairo2` + `libpng16-16` to apt install. |
| `README.md` | Add `## Testing` section. |
