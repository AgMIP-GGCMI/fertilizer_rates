# Minimal mocking helper for a script-based R project.
#
# testthat's local_mocked_bindings() requires pkgload and only works inside
# loaded packages. This project sources fertilizer_scaling_functions.R via
# tests/testthat/setup.R, so its functions live in the same environment as
# the test files. This helper temporarily rebinds names there and restores
# them on test exit.
#
# Target env for rebinding: parent.env(environment()) — the helper's own
# lexical enclosing env, i.e. whichever env sourced this file. Under the
# normal testthat::test_dir() flow that's globalenv(); under
# covr::file_coverage() it's covr's instrumented env. This makes the helper
# work under both.
#
# Only rebinds names already present in that env (no walking up the search
# path). Callers who try to mock names not bound there get a clear error
# instead of silently shadowing a package function.
#
# Named to avoid collision with testthat::local_mock (defunct in testthat 3.2+).
#
# Usage (inside a test_that block):
#   local_mocked_globals(some_fn = function(...) { ...mock body... })
#
# Multiple names can be rebound in one call. On test exit, all originals
# are restored regardless of whether the test passed or errored.

local_mocked_globals <- function(..., .envir = parent.frame()) {
  bindings <- list(...)
  names_to_mock <- names(bindings)
  if (is.null(names_to_mock) || any(names_to_mock == "")) {
    stop("local_mocked_globals() requires named arguments (binding = function).")
  }
  # parent.env(environment()) is the lexical enclosing env of this function —
  # whichever env sourced this helper file. Under covr::file_coverage() that
  # env also contains the instrumented production functions, so it is exactly
  # the right target. Under testthat::test_dir() the helper is sourced into a
  # child of globalenv(), while setup.R's source() call (without local=TRUE)
  # puts the production functions directly into globalenv(). Walk up the parent
  # chain to find the first env that actually owns the first name we need to
  # mock; this resolves to the instrumented covr env under file_coverage and to
  # globalenv() under test_dir, making the helper work identically under both.
  target_env <- (function() {
    e <- parent.env(environment())
    first_nm <- names_to_mock[[1L]]
    while (!identical(e, emptyenv())) {
      if (exists(first_nm, envir = e, inherits = FALSE)) return(e)
      e <- parent.env(e)
    }
    stop(sprintf(
      "local_mocked_globals(): '%s' not found in any env on the search path.",
      first_nm))
  })()
  originals <- lapply(names_to_mock, function(nm) {
    if (!exists(nm, envir = target_env, inherits = FALSE)) {
      stop(sprintf(
        "local_mocked_globals(): '%s' is not bound in helper env; refusing to mock.", nm))
    }
    get(nm, envir = target_env, inherits = FALSE)
  })
  names(originals) <- names_to_mock
  for (nm in names_to_mock) {
    assign(nm, bindings[[nm]], envir = target_env)
  }
  withr::defer({
    for (nm in names_to_mock) {
      assign(nm, originals[[nm]], envir = target_env)
    }
  }, envir = .envir)
  invisible(NULL)
}
