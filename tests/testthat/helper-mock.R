# Minimal mocking helper for a script-based R project.
#
# testthat's local_mocked_bindings() requires pkgload and only works inside
# loaded packages. This project sources fertilizer_scaling_functions.R via
# tests/testthat/setup.R, so its functions live in globalenv(). This helper
# temporarily rebinds names there and restores them on test exit.
#
# Usage (inside a test_that block):
#   local_mock(some_fn = function(...) { ...mock body... })
#
# Multiple names can be rebound in one call. On test exit, all originals
# are restored regardless of whether the test passed or errored.

local_mock <- function(..., .envir = parent.frame()) {
  bindings <- list(...)
  names_to_mock <- names(bindings)
  if (is.null(names_to_mock) || any(names_to_mock == "")) {
    stop("local_mock() requires named arguments (binding = function).")
  }
  originals <- lapply(names_to_mock, function(nm) get(nm, envir = globalenv()))
  names(originals) <- names_to_mock
  for (nm in names_to_mock) {
    assign(nm, bindings[[nm]], envir = globalenv())
  }
  withr::defer({
    for (nm in names_to_mock) {
      assign(nm, originals[[nm]], envir = globalenv())
    }
  }, envir = .envir)
  invisible(NULL)
}
