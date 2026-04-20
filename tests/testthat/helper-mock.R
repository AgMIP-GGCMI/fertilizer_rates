# Minimal mocking helper for a script-based R project.
#
# testthat's local_mocked_bindings() requires pkgload and only works inside
# loaded packages. This project sources fertilizer_scaling_functions.R via
# tests/testthat/setup.R, so its functions live in the same environment as
# the test files. This helper temporarily rebinds names there and restores
# them on test exit.
#
# Target env for rebinding: start at parent.env(environment()) — the helper's
# own lexical enclosing env — and walk up the parent chain until we find an
# env that actually owns the name the caller wants to mock. The walk is done
# PER NAME, so a single call may rebind different names in different envs.
# This makes the helper work under both test flows:
#   * testthat::test_dir() sources helpers into a child of globalenv(), while
#     setup.R's source() call puts production functions into globalenv()
#     itself. The walk therefore advances one step to globalenv().
#   * covr::file_coverage() sources helpers and the instrumented production
#     functions into the same child env. The walk stops immediately.
#
# Names not bound anywhere on the walk produce a clear error instead of
# silently shadowing a package function on the search path.
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

  start_env <- parent.env(environment())
  find_env <- function(nm) {
    e <- start_env
    while (!identical(e, emptyenv())) {
      if (exists(nm, envir = e, inherits = FALSE)) return(e)
      e <- parent.env(e)
    }
    stop(sprintf(
      "local_mocked_globals(): '%s' not bound in helper's enclosing env or any parent.",
      nm))
  }

  targets <- lapply(names_to_mock, find_env)
  originals <- Map(function(nm, env) get(nm, envir = env, inherits = FALSE),
                   names_to_mock, targets)

  Map(function(nm, env) assign(nm, bindings[[nm]], envir = env),
      names_to_mock, targets)

  withr::defer({
    Map(function(nm, env, orig) assign(nm, orig, envir = env),
        names_to_mock, targets, originals)
  }, envir = .envir)

  invisible(NULL)
}
