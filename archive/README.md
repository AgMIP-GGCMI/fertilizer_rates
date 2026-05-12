# archive/

Soft-deleted code: scripts and functions that are no longer part of the
active codebase but are preserved here as a discoverable record (rather
than relying on `git log --all --full-history` to find them).

**Nothing in this folder is sourced by active code or exercised by
tests.** Files here may be stale relative to current conventions and
should not be revived without first re-validating them against the
current `fertilizer_scaling_functions.R` API.

Contents:

- `run_diagnostics_external.R` — vestigial; embeds a drifted copy of
  `plot_diagnostics`.
- `compare_histsoc_future.R` — vestigial; cross-scenario comparison
  script with its own drifted plotting logic.
- `compare_2014_2015.R` — function previously defined in
  `fertilizer_scaling_functions.R` but never called from anywhere.
