# Automated PNG Regression Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the one-shot PNG verification harness (`tools/render_diagnostics_png.R`) into the `testthat` suite as automated regression tests with committed baselines, split the test runner into full/fast modes, add cairo/png system libs to the devcontainer, and document testing in the README.

**Architecture:** The current harness script is refactored into a reusable function library (`tools/diagnostics_png_harness.R`) with a thin CLI wrapper. Slow rendering-based tests live in a new `tests/testthat-slow/` directory alongside the existing `tests/testthat/`. Both dirs are discovered by a shared `tests/_runner_common.R` helper; `tests/testthat.R` runs everything (default) and `tests/testthat-fast.R` runs only the fast dir. Baselines captured via `testthat::expect_snapshot_file()` land in testthat's `_snaps/` convention and are committed to git. Byte-identity depends on the devcontainer image; `libcairo2` and `libpng16-16` are pinned transitively by the `rocker/r-ver:4.5.0` base.

**Tech Stack:** R 4.5, `testthat` 3.x (`expect_snapshot_file`, `snapshot_accept`, `snapshot_review`), `withr` (in `renv.lock`), cairo-backed `grDevices::png`.

**Reference documents:**
- Spec: `docs/superpowers/specs/2026-04-21-automated-png-regression-tests-design.md`
- User conventions from auto-memory:
  - Work on branches, not main; non-trivial changes get a worktree.
  - Commit at every step; split logically distinct changes.
  - Subagent-driven writer → reviewer → commit cycle.
  - One early approval gate (after Task 1), then autonomous through merge.
  - `git merge --no-ff` to preserve feature-branch grouping.

---

## File Structure

**New files:**
- `tools/diagnostics_png_harness.R` — pure function library. Defines `render_diagnostics_to_png(png_output_dir, crop, scenario, iam, gcm)`.
- `tools/accept_diagnostics_baseline.R` — thin CLI wrapper around `testthat::snapshot_accept("plot_diagnostics_regression")`.
- `tests/_runner_common.R` — shared `run_tests(fast_only)` function plus `library(testthat)`.
- `tests/testthat-fast.R` — CLI entry point that skips slow tests.
- `tests/testthat-slow/setup.R` — sources `fertilizer_scaling_functions.R` (mirror of the existing fast setup).
- `tests/testthat-slow/test-plot_diagnostics_regression.R` — the new regression test.
- `tests/testthat-slow/_snaps/plot_diagnostics_regression/*.png` — 18 baseline PNG files (committed).

**Modified files:**
- `tools/render_diagnostics_png.R` — simplified to a thin CLI wrapper that sources the harness.
- `tests/testthat.R` — replaced with a two-line bootstrap + `run_tests(FALSE)`.
- `.devcontainer/Dockerfile` — extended apt-install block with `libcairo2` and `libpng16-16`.
- `README.md` — new `## Testing` section.

**Untracked (under already-ignored `data/`):**
- `data/plot-refactor-verify/` — scratch dir for the Task 1 determinism check. Discarded after use.

---

## Reference invocations

The two scenarios the snapshot tests cover (matching the spec):

- `mai histsoc` — historical path.
- `mai ssp126 image gfdl-esm4` — future path (IAM + GCM filename branch).

Each produces 9 PNGs when rendered through the harness (3 PDFs × 3 pages). Total baseline footprint: 18 PNGs, ~3.6 MB.

---

## Task 1: Worktree and harness refactor (checkpoint)

This is the only task that requires an approval checkpoint. It validates the harness factoring works before the rest of the plan builds on it.

**Files:**
- Create worktree at `/workspace/.worktrees/png-regression-tests`.
- Create: `tools/diagnostics_png_harness.R`
- Modify: `tools/render_diagnostics_png.R` (simplified)

- [ ] **Step 1.1: Create worktree and copy setup files**

```bash
git -C /workspace worktree add /workspace/.worktrees/png-regression-tests -b feature/png-regression-tests main
cp /workspace/.Renviron /workspace/.worktrees/png-regression-tests/
mkdir -p /workspace/.worktrees/png-regression-tests/data
ln -s /workspace/data/inputs /workspace/.worktrees/png-regression-tests/data/inputs
git -C /workspace/.worktrees/png-regression-tests status
```

Expected: `On branch feature/png-regression-tests`, nothing to commit, working tree clean. The `data/inputs` symlink and `.Renviron` are in the worktree (both under gitignored paths or gitignored by name).

- [ ] **Step 1.2: Create `tools/diagnostics_png_harness.R`**

Write `/workspace/.worktrees/png-regression-tests/tools/diagnostics_png_harness.R` with exactly this content:

```r
# ============================================================================
# diagnostics_png_harness.R
# ============================================================================
# Pure function library for the PNG verification harness. Defines
# render_diagnostics_to_png() without side effects at source time, so it
# can be sourced from both the tools/render_diagnostics_png.R CLI wrapper
# and from the testthat regression test.
#
# The function shadows grDevices::pdf with a cairo-backed png() so each
# diagnostic "page" becomes a byte-comparable PNG. Cairo + renv-pinned R +
# pinned Debian cairo/png packages make output byte-identical inside the
# devcontainer.
# ============================================================================

.HARNESS_PNG_DPI <- 100

render_diagnostics_to_png <- function(png_output_dir, crop, scenario,
                                      iam = NULL, gcm = NULL) {
  dir.create(png_output_dir, showWarnings = FALSE, recursive = TRUE)

  scaling_args <- c(crop, scenario, iam, gcm)

  # Shadow commandArgs and pdf in a local env, then source
  # fertilizer_scaling.R into that env so plot_diagnostics's pdf()
  # lookup resolves to the png-writing shadow via R's lexical scoping.
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

- [ ] **Step 1.3: Syntax-check the harness**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript -e 'parse(file = "tools/diagnostics_png_harness.R")' && echo "syntax ok"
```

Expected: `syntax ok`.

- [ ] **Step 1.4: Capture a pre-refactor baseline to verify byte-identity is preserved**

Before simplifying the CLI wrapper, render both scenarios using the CURRENT (pre-refactor) `tools/render_diagnostics_png.R` and save the manifest. This is the reference we'll compare against after the harness split.

```bash
cd /workspace/.worktrees/png-regression-tests
rm -rf data/plot-refactor-verify
Rscript tools/render_diagnostics_png.R data/plot-refactor-verify/pre/histsoc mai histsoc
Rscript tools/render_diagnostics_png.R data/plot-refactor-verify/pre/ssp126 mai ssp126 image gfdl-esm4
(cd data/plot-refactor-verify/pre && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) > data/plot-refactor-verify/pre.md5
wc -l data/plot-refactor-verify/pre.md5
```

Expected: `18 data/plot-refactor-verify/pre.md5` (9 histsoc + 9 ssp126).

- [ ] **Step 1.5: Commit the new harness file**

The harness file exists alongside the old CLI wrapper at this point. Both are valid; the CLI hasn't been updated yet. Commit the new file alone first.

```bash
cd /workspace/.worktrees/png-regression-tests
git add tools/diagnostics_png_harness.R
git commit -m "$(cat <<'EOF'
Add tools/diagnostics_png_harness.R.

Pure function library for the plot_diagnostics PNG verification
harness. Defines render_diagnostics_to_png() with no side effects on
source so it can be reused from both the CLI wrapper and the
forthcoming testthat regression test.
EOF
)"
```

- [ ] **Step 1.6: Simplify `tools/render_diagnostics_png.R` to a thin CLI wrapper**

Replace the contents of `/workspace/.worktrees/png-regression-tests/tools/render_diagnostics_png.R` with exactly:

```r
#!/usr/bin/env Rscript
# ============================================================================
# render_diagnostics_png.R
# ============================================================================
# CLI wrapper around render_diagnostics_to_png(). See
# tools/diagnostics_png_harness.R for the shadowing logic.
#
# Usage:
#   Rscript tools/render_diagnostics_png.R <png_output_dir> <crop> <scenario> [<iam>] [<gcm>]
# ============================================================================

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

- [ ] **Step 1.7: Verify the simplified wrapper produces byte-identical output**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tools/render_diagnostics_png.R data/plot-refactor-verify/post/histsoc mai histsoc
Rscript tools/render_diagnostics_png.R data/plot-refactor-verify/post/ssp126 mai ssp126 image gfdl-esm4
(cd data/plot-refactor-verify/post && find . -name '*.png' -print0 | sort -z | xargs -0 md5sum) > data/plot-refactor-verify/post.md5
diff data/plot-refactor-verify/pre.md5 data/plot-refactor-verify/post.md5 && echo "HARNESS REFACTOR BYTE-IDENTICAL" || echo "HARNESS REFACTOR MISMATCH"
```

Expected: `HARNESS REFACTOR BYTE-IDENTICAL`. If mismatch, the `local()` restructuring in `diagnostics_png_harness.R` perturbed the output; revert the wrapper change and fall back to a design that assigns `pdf` and `commandArgs` in the caller's global environment via `assign(..., envir = globalenv())` inside `render_diagnostics_to_png`.

- [ ] **Step 1.8: Run the existing test suite**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat.R 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`. The harness refactor doesn't touch any production code path, so tests must remain unchanged.

- [ ] **Step 1.9: Clean up verification dir**

```bash
cd /workspace/.worktrees/png-regression-tests
rm -rf data/plot-refactor-verify
git status
```

Expected: `tools/render_diagnostics_png.R` shows as modified (uncommitted). Nothing else changed. Verification dir was under `data/` (gitignored).

- [ ] **Step 1.10: Commit the simplified CLI wrapper**

```bash
cd /workspace/.worktrees/png-regression-tests
git add tools/render_diagnostics_png.R
git commit -m "$(cat <<'EOF'
Simplify tools/render_diagnostics_png.R to a thin CLI wrapper.

Delegates to render_diagnostics_to_png() from the harness library. No
change to external CLI behavior; verified byte-identical output
against the pre-split baseline for both reference scenarios.
EOF
)"
```

- [ ] **Step 1.11: CHECKPOINT — pause for user approval**

This is the only approval gate. Report to the user:
- Harness factored into `tools/diagnostics_png_harness.R` + thin CLI wrapper.
- Byte-identity preserved (independent pre-vs-post manifests matched).
- Test suite still 194/0.

Wait for explicit approval before proceeding to Task 2.

---

## Task 2: Runner split

**Files:**
- Create: `tests/_runner_common.R`
- Create: `tests/testthat-fast.R`
- Modify: `tests/testthat.R`

- [ ] **Step 2.1: Create `tests/_runner_common.R`**

Write `/workspace/.worktrees/png-regression-tests/tests/_runner_common.R` with exactly:

```r
# Shared runner logic for tests/testthat.R (full) and
# tests/testthat-fast.R (skips slow PNG-regression tests).

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

- [ ] **Step 2.2: Rewrite `tests/testthat.R`**

Replace the contents of `/workspace/.worktrees/png-regression-tests/tests/testthat.R` with exactly:

```r
source(sub("testthat(-fast)?\\.R$", "_runner_common.R", sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
run_tests(fast_only = FALSE)
```

- [ ] **Step 2.3: Create `tests/testthat-fast.R`**

Write `/workspace/.worktrees/png-regression-tests/tests/testthat-fast.R` with exactly:

```r
source(sub("testthat(-fast)?\\.R$", "_runner_common.R", sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))
run_tests(fast_only = TRUE)
```

- [ ] **Step 2.4: Verify both runners work**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat.R 2>&1 | tail -5
Rscript tests/testthat-fast.R 2>&1 | tail -5
```

Expected: both print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`. The `testthat-slow/` dir doesn't exist yet, but the `dir.exists()` guard in `run_tests` keeps the full runner from erroring on the missing path.

- [ ] **Step 2.5: Commit the runner split**

```bash
cd /workspace/.worktrees/png-regression-tests
git add tests/_runner_common.R tests/testthat.R tests/testthat-fast.R
git commit -m "$(cat <<'EOF'
Split test runner into full (default) and fast modes.

tests/testthat.R runs the full suite including the forthcoming
testthat-slow/ directory; tests/testthat-fast.R skips it. Shared
logic lives in tests/_runner_common.R. Both runners use the same
bootstrap expression to locate the common file.
EOF
)"
```

---

## Task 3: Slow-test scaffolding

**Files:**
- Create: `tests/testthat-slow/setup.R`
- Create: `tests/testthat-slow/test-plot_diagnostics_regression.R`

- [ ] **Step 3.1: Create `tests/testthat-slow/setup.R`**

```bash
mkdir -p /workspace/.worktrees/png-regression-tests/tests/testthat-slow
```

Write `/workspace/.worktrees/png-regression-tests/tests/testthat-slow/setup.R` with exactly:

```r
source(
  testthat::test_path("..", "..", "fertilizer_scaling_functions.R"),
  chdir = TRUE
)
```

This mirrors `tests/testthat/setup.R` and makes `plot_diagnostics` and friends available inside the slow tests.

- [ ] **Step 3.2: Create the regression test file**

Write `/workspace/.worktrees/png-regression-tests/tests/testthat-slow/test-plot_diagnostics_regression.R` with exactly:

```r
# PNG regression tests for plot_diagnostics. Each test renders a
# reference scenario through the harness and snapshots every produced
# PNG. testthat compares byte-for-byte against committed baselines and
# writes a .new.png next to any mismatch for review.

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

- [ ] **Step 3.3: Verify `tests/testthat-fast.R` still passes (unchanged behavior)**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat-fast.R 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`. The fast runner ignores `testthat-slow/`.

- [ ] **Step 3.4: Commit the scaffolding**

Do NOT run the full suite yet — it would create snapshot files under `_snaps/` before we're ready to review them. Commit the test scaffolding first; Task 4 captures baselines as a separate commit.

```bash
cd /workspace/.worktrees/png-regression-tests
git add tests/testthat-slow/setup.R tests/testthat-slow/test-plot_diagnostics_regression.R
git commit -m "$(cat <<'EOF'
Add PNG-regression test scaffolding for plot_diagnostics.

Snapshot tests for two reference scenarios (mai histsoc and
mai ssp126 image gfdl-esm4) using testthat::expect_snapshot_file().
Baselines will be captured in the next commit.
EOF
)"
```

---

## Task 4: Capture and commit baselines

**Files:**
- Create (via testthat): 18 PNGs under `tests/testthat-slow/_snaps/plot_diagnostics_regression/`.

- [ ] **Step 4.1: Run the full suite for the first time**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat.R 2>&1 | tail -10
```

Expected: `testthat` reports the slow tests as PASSED (snapshot-on-first-run-is-baseline semantics) OR optionally as a failure with a "snapshot file did not exist, recording new baseline" message. The exact wording depends on the testthat version. Either way, the baseline files appear under `tests/testthat-slow/_snaps/plot_diagnostics_regression/`.

Check the new files:

```bash
cd /workspace/.worktrees/png-regression-tests
ls tests/testthat-slow/_snaps/plot_diagnostics_regression/ | wc -l
```

Expected: `18`.

- [ ] **Step 4.2: Spot-check one baseline PNG visually**

Pick one file and confirm it looks like a real diagnostic plot (not blank, not an error page). Command to list a few:

```bash
cd /workspace/.worktrees/png-regression-tests
ls -la tests/testthat-slow/_snaps/plot_diagnostics_regression/ | head
```

If possible, open one in an image viewer to confirm visually. If not (headless environment), check file sizes: all 18 should be > 20 KB (a blank cairo PNG at 100 DPI × 1600×1400 would be ~5 KB from headers alone; a real plot is ~100–300 KB).

```bash
cd /workspace/.worktrees/png-regression-tests
find tests/testthat-slow/_snaps/plot_diagnostics_regression/ -name '*.png' -size -20k
```

Expected: no matches (all files ≥ 20 KB).

- [ ] **Step 4.3: Re-run the full suite and confirm it's green**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat.R 2>&1 | tail -5
```

Expected (two summary lines — one per `test_dir` call):
- Fast: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`
- Slow: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 32 ]`

The slow suite adds 2 new `test_that` blocks (one per scenario); each `test_that` is one passing block regardless of how many `expect_snapshot_file` calls it contains. The 2 SKIPs are "empty test" entries from pipeline-internal `test_that()` blocks in `fertilizer_scaling_functions.R:492` (the lambda-method branch of "Trends are preserved" only calls `cat()`). They are harmless and pre-existing in the pipeline.

- [ ] **Step 4.4: Commit the baselines**

```bash
cd /workspace/.worktrees/png-regression-tests
git add tests/testthat-slow/_snaps
git status
```

Expected: 18 new `.png` files staged under `tests/testthat-slow/_snaps/plot_diagnostics_regression/`. Nothing else modified.

```bash
cd /workspace/.worktrees/png-regression-tests
git commit -m "$(cat <<'EOF'
Capture baseline PNG snapshots for plot_diagnostics regression tests.

18 files (9 per scenario × 2 scenarios) at 100 DPI cairo PNG,
approximately 3.6 MB total. Byte-identity is guaranteed inside this
repo's devcontainer; rebuilds that pick up newer cairo/libpng
versions may require fresh baselines via
tools/accept_diagnostics_baseline.R.
EOF
)"
```

- [ ] **Step 4.5: Final re-run confirms clean pass**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat.R 2>&1 | tail -5
```

Expected (two summary lines — one per `test_dir` call):
- Fast: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`
- Slow: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 32 ]`

The snapshot test now compares against committed baselines; clean pass means the harness is deterministic across runs. The 2 SKIPs are pre-existing "empty test" entries from pipeline-internal `test_that()` blocks in `fertilizer_scaling_functions.R:492` (the lambda-method branch of "Trends are preserved" only calls `cat()`) — harmless, unrelated to the new PNG suite.

---

## Task 5: Acceptance wrapper

**Files:**
- Create: `tools/accept_diagnostics_baseline.R`

- [ ] **Step 5.1: Create the acceptance wrapper**

Write `/workspace/.worktrees/png-regression-tests/tools/accept_diagnostics_baseline.R` with exactly:

```r
#!/usr/bin/env Rscript
# ============================================================================
# accept_diagnostics_baseline.R
# ============================================================================
# Accept the current plot_diagnostics_regression PNG snapshots as the new
# baseline. Run after intentionally changing diagnostic output. Expects
# to be run from the repo root.
# ============================================================================

script_path <- sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
setwd(file.path(repo_root, "tests"))

library(testthat)
testthat::snapshot_accept("plot_diagnostics_regression")
```

- [ ] **Step 5.2: Smoke-test the wrapper**

Run the wrapper against the clean baselines. Accepting already-accepted snapshots is a no-op.

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tools/accept_diagnostics_baseline.R
echo "exit=$?"
git status
```

Expected: `exit=0`, `git status` shows `nothing to commit, working tree clean`. No `.new.png` files, no modified baselines.

- [ ] **Step 5.3: Commit**

```bash
cd /workspace/.worktrees/png-regression-tests
git add tools/accept_diagnostics_baseline.R
git commit -m "$(cat <<'EOF'
Add tools/accept_diagnostics_baseline.R.

Thin CLI wrapper around testthat::snapshot_accept() for intentional
baseline updates. Run after deliberate changes to diagnostic output.
EOF
)"
```

---

## Task 6: Devcontainer system libs

**Files:**
- Modify: `.devcontainer/Dockerfile`

- [ ] **Step 6.1: Read the current Dockerfile apt block**

```bash
cd /workspace/.worktrees/png-regression-tests
grep -n "^\s*lib" .devcontainer/Dockerfile | head -15
```

Expected output (approximate line numbers):

```
31:    libnetcdf-dev \
32:    libhdf5-dev \
33:    libudunits2-dev \
34:    libuv1-dev \
35:    libxml2-dev \
36:    libssl-dev \
37:    libcurl4-openssl-dev \
```

- [ ] **Step 6.2: Extend the apt block with cairo and png libs**

Edit `/workspace/.worktrees/png-regression-tests/.devcontainer/Dockerfile`. Find the block starting at line 11 (`RUN apt-get update && apt-get install -y --no-install-recommends \`). The block currently ends with:

```
    libcurl4-openssl-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
```

Insert two lines before `&& apt-get clean` so the block ends with:

```
    libcurl4-openssl-dev \
    libcairo2 \
    libpng16-16 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
```

Also update the comment on lines 9–10 (`# System tooling (Anthropic's reference set) + system libs for R packages / # used by this repo (ncdf4, fields, lintr).`) to read `# used by this repo (ncdf4, fields, lintr, and cairo/png rendering for / # PNG regression tests).`.

- [ ] **Step 6.3: Verify the Dockerfile diff**

```bash
cd /workspace/.worktrees/png-regression-tests
git diff .devcontainer/Dockerfile
```

Expected: two added `libcairo2 \` and `libpng16-16 \` lines, plus the comment extension. Nothing else touched.

- [ ] **Step 6.4: Commit**

```bash
cd /workspace/.worktrees/png-regression-tests
git add .devcontainer/Dockerfile
git commit -m "$(cat <<'EOF'
Pin cairo/png system libs in devcontainer for PNG regression tests.

The rocker/r-ver:4.5.0 base image already provides usable cairo/png
libraries, but making the dependency explicit documents intent and
lets a future rebuild pick up the same Debian packages reliably.
EOF
)"
```

Do NOT rebuild the devcontainer as part of this step — the currently-running container already has whatever cairo/png the rocker base provides, and the Task 4 baselines were captured against those versions. Rebuilding now could invalidate the baselines.

---

## Task 7: README Testing section

**Files:**
- Modify: `README.md`

- [ ] **Step 7.1: Locate the insertion point**

```bash
cd /workspace/.worktrees/png-regression-tests
grep -n "^##" README.md
```

Look for the line starting with `## First-run inside the container`. The new `## Testing` section goes after the end of that section (and before any section that follows, e.g., a License or related links section if present).

- [ ] **Step 7.2: Append the Testing section**

Open `/workspace/.worktrees/png-regression-tests/README.md`. After the end of the `## First-run inside the container` section, insert:

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

Preserve one blank line between the previous section's last line and the new `## Testing` heading; preserve one blank line between the new section's last line and whatever follows.

- [ ] **Step 7.3: Verify the README renders sensibly**

```bash
cd /workspace/.worktrees/png-regression-tests
grep -n "^##" README.md
```

Expected: the list now shows `## Testing` between `## First-run inside the container` and whatever was next. If nothing came after, `## Testing` is the last `##` heading.

- [ ] **Step 7.4: Commit**

```bash
cd /workspace/.worktrees/png-regression-tests
git add README.md
git commit -m "$(cat <<'EOF'
Add Testing section to README.

Documents the fast / full test-runner split, the snapshot-review and
baseline-acceptance workflow, and the environment caveat for
byte-identical PNG output.
EOF
)"
```

---

## Task 8: Final review and merge

**Files:** no new changes; just verification and merge.

- [ ] **Step 8.1: Final end-to-end sanity check**

```bash
cd /workspace/.worktrees/png-regression-tests
Rscript tests/testthat.R 2>&1 | tail -5
Rscript tests/testthat-fast.R 2>&1 | tail -5
```

Expected:
- Full (`tests/testthat.R` emits two summary lines — one per `test_dir` call):
  - Fast: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`
  - Slow: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 32 ]`
- Fast-only (`tests/testthat-fast.R`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`

The 2 SKIPs in the slow suite are pre-existing "empty test" entries from pipeline-internal `test_that()` blocks in `fertilizer_scaling_functions.R:492` (the lambda-method branch of "Trends are preserved" only calls `cat()`). They are harmless and unrelated to the new PNG regression suite.

- [ ] **Step 8.2: Review branch commits**

```bash
cd /workspace/.worktrees/png-regression-tests
git log --oneline main..HEAD
```

Expected: roughly 8 commits, one per Task (some Tasks like Task 1 split into two commits per the step-level instructions). Specifically:
- Add tools/diagnostics_png_harness.R.
- Simplify tools/render_diagnostics_png.R to a thin CLI wrapper.
- Split test runner into full (default) and fast modes.
- Add PNG-regression test scaffolding for plot_diagnostics.
- Capture baseline PNG snapshots for plot_diagnostics regression tests.
- Add tools/accept_diagnostics_baseline.R.
- Pin cairo/png system libs in devcontainer for PNG regression tests.
- Add Testing section to README.

- [ ] **Step 8.3: Switch to main and merge with --no-ff**

```bash
cd /workspace
git checkout main
git status
```

Expected: clean, on `main`.

```bash
git merge --no-ff feature/png-regression-tests -m "$(cat <<'EOF'
Merge branch 'feature/png-regression-tests'.

Promotes the plot_diagnostics PNG verification harness from one-shot
tool to committed testthat-integrated regression suite. Splits the
test runner into full (default) and fast modes, commits 18 baseline
PNG snapshots, pins cairo/png system libraries in the devcontainer,
and documents the testing workflow in the README.

Test suite: 194 → 196 (two new test_that blocks for the scenarios).
EOF
)"
```

- [ ] **Step 8.4: Verify the merge graph**

```bash
git log --oneline --graph -15
```

Expected: the feature branch's commits appear as a merged side branch, topped by the merge commit.

- [ ] **Step 8.5: Clean up worktree and branch**

```bash
git worktree remove /workspace/.worktrees/png-regression-tests
git branch -d feature/png-regression-tests
git worktree list
git branch -a
```

Expected: only `/workspace [main]` in `git worktree list`; `feature/png-regression-tests` no longer in `git branch`.

- [ ] **Step 8.6: Post-merge sanity check on main**

```bash
cd /workspace
Rscript tests/testthat.R 2>&1 | tail -5
```

Expected (two summary lines — one per `test_dir` call):
- Fast: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 194 ]`
- Slow: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 32 ]`

The merged code works on main from a fresh invocation. The 2 SKIPs are pre-existing "empty test" entries from pipeline-internal `test_that()` blocks in `fertilizer_scaling_functions.R:492` — harmless and unrelated to the new PNG suite.

---

## Spec-coverage sanity check

| Spec requirement | Task(s) |
|---|---|
| Harness split into function library + CLI wrapper | Task 1 |
| `tools/diagnostics_png_harness.R` with `render_diagnostics_to_png()` | Task 1 |
| Simplified `tools/render_diagnostics_png.R` | Task 1 |
| `tests/_runner_common.R` with `dir.exists()` guard | Task 2 |
| `tests/testthat.R` runs all tests | Task 2 |
| `tests/testthat-fast.R` skips slow tests | Task 2 |
| `tests/testthat-slow/setup.R` | Task 3 |
| `tests/testthat-slow/test-plot_diagnostics_regression.R` | Task 3 |
| Two reference scenarios: `mai histsoc` and `mai ssp126 image gfdl-esm4` | Tasks 3, 4 |
| 18 committed baseline PNGs under `_snaps/plot_diagnostics_regression/` | Task 4 |
| `tools/accept_diagnostics_baseline.R` | Task 5 |
| `.devcontainer/Dockerfile` extended with `libcairo2` + `libpng16-16` | Task 6 |
| Comment on apt block updated to mention cairo/png | Task 6 |
| README `## Testing` section with runner docs, snapshot-review flow, environment caveat | Task 7 |
| Worktree-based work + `git merge --no-ff` + cleanup | Tasks 1, 8 |
| Single approval checkpoint after harness refactor | Task 1 Step 1.11 |
| Subagent-driven writer → reviewer → commit cadence | subagent-driven-development skill wraps each task |
| Commits split per logical change (append-harness vs. simplify-wrapper; scaffolding vs. baselines) | Tasks 1, 3/4 |
| No visual diff composite, no broader scenarios, no CI integration | Spec non-goals — no task |
