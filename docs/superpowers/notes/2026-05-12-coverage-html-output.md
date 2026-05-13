# Coverage HTML output

**Date:** 2026-05-12
**Merge:** `a8a1f7c` (branch `docs/coverage-html`)

## Request

> Please update the README coverage test instructions to include producing the `coverage.html` file.

## What landed

Both `tests/coverage.R` and `tests/coverage_fast.R` now call `covr::report()` after computing coverage, writing per-line HTML reports (`coverage.html` and `coverage_fast.html`) alongside the existing console summary. Both `*html` files are gitignored under the project's pre-existing `*html` rule.

HTML generation is **opt-in**: each script wraps the `covr::report()` call in a `requireNamespace("DT", quietly = TRUE) && requireNamespace("htmltools", quietly = TRUE)` gate. When either package is missing, the HTML step is skipped with a one-line hint:

    HTML report skipped: install DT and htmltools to enable.

The README's Coverage section documents both the default behavior and the enabler one-liner:

    Rscript -e 'renv::install(c("DT", "htmltools"))'

## Why opt-in, not mandatory

`covr::report()` requires `DT` and `htmltools` as rendering deps. Adding them to `renv.lock` would mean ~19 transitive packages (rmarkdown, bslib, sass, htmlwidgets, crosstalk, fontawesome, jquerylib, promises, etc.).

I tried two `renv::snapshot()` approaches and neither produced a clean diff:

- **Default mode:** silently dropped legitimately-used packages (testthat, MASS, spam, etc.) because renv's call-graph detection misses `library()` calls in non-standard places like `fertilizer_scaling_settings.R`.
- **`type = "all", force = TRUE`:** kept everything but produced a 1700-line lockfile diff with version shuffles unrelated to DT/htmltools — the worktree's installed library appears to have drifted from the locked state, so a clean snapshot isn't trivial right now.

Graceful degradation in the scripts plus a documented install one-liner in the README was the right call. Anyone who wants HTML output runs the install once; subsequent script invocations detect the deps and emit HTML.

## Files touched

- `tests/coverage.R` — added the `requireNamespace()`-gated `covr::report()` call after the summary print.
- `tests/coverage_fast.R` — same pattern, writes `coverage_fast.html`.
- `README.md` — Coverage section expanded with a paragraph on HTML output and the optional install one-liner.

## Carry-forward for future work

- If asked to add HTML rendering to other covr scripts, mirror the same `requireNamespace()` gate.
- If asked to actually lock DT/htmltools into `renv.lock`, first investigate the worktree-vs-lockfile divergence (`renv::status()`); don't blindly snapshot.
- The existing `coverage.html` on disk dates from April 20 and predates the harness-coverage-fix work (it reports pre-fix numbers). It's stale until someone regenerates it.
