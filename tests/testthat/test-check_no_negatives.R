# Tests for check_no_negatives() in fertilizer_scaling_functions.R.

test_that("TRUE when all values are non-negative", {
  x <- array(c(0, 1, 2, 3), dim = c(2, 2, 1))
  expect_true(check_no_negatives(x))
})

test_that("TRUE when some values are NA and the rest are non-negative", {
  x <- array(c(NA_real_, 1, 2, 3), dim = c(2, 2, 1))
  expect_true(check_no_negatives(x))
})

test_that("FALSE when a single non-NA cell is negative", {
  x <- array(c(0, 1, -0.001, 3), dim = c(2, 2, 1))
  expect_false(check_no_negatives(x))
})

test_that("TRUE on an all-NA array", {
  x <- array(NA_real_, dim = c(2, 2, 2))
  expect_true(check_no_negatives(x))
})

test_that("accepts 2D matrices as well as 3D arrays", {
  expect_true(check_no_negatives(matrix(c(0, 1, 2, 3), nrow = 2)))
  expect_false(check_no_negatives(matrix(c(0, -1, 2, 3), nrow = 2)))
})
