# Tests for aggregate_to_halfdegree() in fertilizer_scaling_functions.R.
#
# The function only accepts 4320 x 2160 (5 arcmin) input and writes into a
# hardcoded 720 x 360 (0.5 degree) output grid, so each test builds a full-size
# NA-filled base and stamps in just the blocks it needs to exercise.

make_input <- function() array(NA_real_, dim = c(4320, 2160))

test_that("returns a list with data, lon, lat components", {
  result <- aggregate_to_halfdegree(make_input(), NULL, NULL)
  expect_type(result, "list")
  expect_named(result, c("data", "lon", "lat"))
})

test_that("output data has dimensions 720 x 360", {
  result <- aggregate_to_halfdegree(make_input(), NULL, NULL)
  expect_equal(dim(result$data), c(720, 360))
})

test_that("output longitude spans -179.75 to 179.75 by 0.5 degrees", {
  result <- aggregate_to_halfdegree(make_input(), NULL, NULL)
  expect_length(result$lon, 720)
  expect_equal(result$lon[1], -179.75)
  expect_equal(result$lon[720], 179.75)
  expect_equal(diff(result$lon), rep(0.5, 719))
})

test_that("output latitude spans -89.75 to 89.75 by 0.5 degrees", {
  result <- aggregate_to_halfdegree(make_input(), NULL, NULL)
  expect_length(result$lat, 360)
  expect_equal(result$lat[1], -89.75)
  expect_equal(result$lat[360], 89.75)
  expect_equal(diff(result$lat), rep(0.5, 359))
})

test_that("uniform input produces a uniform output of the same value", {
  input <- array(3.5, dim = c(4320, 2160))
  result <- aggregate_to_halfdegree(input, NULL, NULL)
  expect_true(all(result$data == 3.5))
})

test_that("all-NA input produces all-NA output (no NaN leakage)", {
  result <- aggregate_to_halfdegree(make_input(), NULL, NULL)
  expect_true(all(is.na(result$data)))
  expect_false(any(is.nan(result$data)))
})

test_that("a single 6x6 block averages to the mean of its 36 cells", {
  input <- make_input()
  input[1:6, 1:6] <- matrix(1:36, nrow = 6)
  result <- aggregate_to_halfdegree(input, NULL, NULL)

  expect_equal(result$data[1, 1], mean(1:36))
  # Adjacent output cells should still be NA (no bleed).
  expect_true(is.na(result$data[2, 1]))
  expect_true(is.na(result$data[1, 2]))
})

test_that("NA values are ignored when a block is only partially NA", {
  input <- make_input()
  block <- matrix(NA_real_, nrow = 6, ncol = 6)
  # Varying non-NA values so the assertion only holds if NAs are masked AND
  # the surviving cells are averaged (not e.g. summed or first-picked).
  non_na_values <- c(10, 20, 30, 40, 50, 60)
  block[1:3, ] <- non_na_values
  input[1:6, 1:6] <- block
  result <- aggregate_to_halfdegree(input, NULL, NULL)
  expect_equal(result$data[1, 1], mean(rep(non_na_values, each = 3)))
})

test_that("neighboring output cells aggregate from independent input blocks", {
  input <- make_input()
  input[1:6, 1:6]   <- 2    # -> output [1, 1]
  input[7:12, 1:6]  <- 4    # -> output [2, 1]
  input[1:6, 7:12]  <- 6    # -> output [1, 2]
  input[7:12, 7:12] <- 8    # -> output [2, 2]
  result <- aggregate_to_halfdegree(input, NULL, NULL)

  expect_equal(result$data[1, 1], 2)
  expect_equal(result$data[2, 1], 4)
  expect_equal(result$data[1, 2], 6)
  expect_equal(result$data[2, 2], 8)
})

test_that("the last block maps correctly to output cell [720, 360]", {
  input <- make_input()
  input[4315:4320, 2155:2160] <- 7
  result <- aggregate_to_halfdegree(input, NULL, NULL)
  expect_equal(result$data[720, 360], 7)
})

test_that("lon and lat inputs are ignored (outputs are fixed to the 0.5deg grid)", {
  # Pass deliberately bogus coordinate vectors; the function should still
  # return the canonical 0.5deg lon/lat grid.
  result <- aggregate_to_halfdegree(make_input(), lon_5min = numeric(0), lat_5min = numeric(0))
  expect_equal(result$lon[1], -179.75)
  expect_equal(result$lat[1], -89.75)
})
