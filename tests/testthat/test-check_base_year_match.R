# Tests for check_base_year_match() in fertilizer_scaling_functions.R.

test_that("returns a list with n_valid and correlation", {
  base_rate   <- matrix(c(10, 20, 30, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- base_rate
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_named(out, c("n_valid", "correlation"))
})

test_that("perfect match yields correlation very near 1 and n_valid = n cells", {
  base_rate   <- matrix(c(10, 20, 30, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- base_rate
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 4)
  expect_equal(out$correlation, 1, tolerance = 1e-12)
})

test_that("NA in base_rate excludes those cells from n_valid", {
  base_rate   <- matrix(c(10, NA, 30, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- matrix(c(10, 20, 30, 40), nrow = 2)
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 3)
})

test_that("NA in scaled base-year slice excludes those cells from n_valid", {
  base_rate   <- matrix(c(10, 20, 30, 40), nrow = 2)
  scaled_slice <- matrix(c(10, 20, NA, 40), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- scaled_slice
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 3)
})

test_that("when n_valid == 0, correlation is NA (no crash)", {
  base_rate   <- matrix(NA_real_, nrow = 2, ncol = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 0)
  expect_true(is.na(out$correlation))
})

test_that("correlation matches hand-computed value on partial overlap", {
  # Cells (1,1)=(10,10), (2,1)=(20,20), others NA in base_rate
  base_rate <- matrix(c(10, 20, NA, NA), nrow = 2)
  scaled_data <- array(0, dim = c(2, 2, 3))
  scaled_data[, , 2] <- matrix(c(10, 20, 100, 200), nrow = 2)
  out <- check_base_year_match(scaled_data, base_rate, base_idx = 2)
  expect_equal(out$n_valid, 2)
  # With only 2 matched points both identical, correlation is exactly 1
  expect_equal(out$correlation, 1, tolerance = 1e-12)
})
