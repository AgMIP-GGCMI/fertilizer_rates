# Tests for the grid helpers in fertilizer_scaling_functions.R:
# block_columns(), block_centres(), lat_to_ascending(), stop_unless_ascending().

test_that("block_columns puts each factor x factor block in one column", {
  x <- matrix(1:8, nrow = 4)
  out <- block_columns(x, 2)
  expect_equal(dim(out), c(4L, 2L))
  expect_equal(colSums(out), c(1 + 2 + 5 + 6, 3 + 4 + 7 + 8))
})

test_that("block_centres averages each run of factor coordinates", {
  expect_equal(block_centres(c(0.125, 0.375, 0.625, 0.875), 2), c(0.25, 0.75))
})

test_that("lat_to_ascending leaves ascending input untouched", {
  x <- matrix(1:6, nrow = 2)
  res <- lat_to_ascending(x, c(1, 2, 3), "lbl")
  expect_identical(res$data, x)
  expect_identical(res$lat, c(1, 2, 3))
})

test_that("lat_to_ascending flips a 2-D matrix and reverses lat", {
  x <- matrix(1:6, nrow = 2)
  res <- lat_to_ascending(x, c(3, 2, 1), "lbl")
  expect_equal(res$lat, c(1, 2, 3))
  expect_equal(res$data[1, 1], x[1, 3])
  expect_equal(res$data[2, 3], x[2, 1])
})

test_that("lat_to_ascending flips a 3-D array along dimension 2", {
  x <- array(1:24, dim = c(2, 3, 4))
  res <- lat_to_ascending(x, c(3, 2, 1), "lbl")
  expect_equal(dim(res$data), c(2L, 3L, 4L))
  expect_equal(res$data[1, 1, 2], x[1, 3, 2])
  expect_equal(res$data[2, 3, 4], x[2, 1, 4])
})

test_that("lat_to_ascending errors on non-monotonic lat", {
  expect_error(lat_to_ascending(matrix(1:6, nrow = 2), c(1, 3, 2), "lbl"),
               "lbl: lat is not strictly ascending after canonicalization")
})

test_that("stop_unless_ascending errors unless strictly ascending", {
  expect_error(stop_unless_ascending(c(1, 3, 2), "lon"), "lon is not strictly ascending")
  expect_error(stop_unless_ascending(c(1, 1, 2), "lon"), "lon is not strictly ascending")
  expect_identical(stop_unless_ascending(c(1, 2, 3), "lon"), c(1, 2, 3))
})

test_that("block_columns lays out each block's cells in column-major order", {
  out <- block_columns(matrix(1:16, 4, 4), 2)
  expect_equal(out, cbind(c(1, 2, 5, 6), c(3, 4, 7, 8), c(9, 10, 13, 14), c(11, 12, 15, 16)),
               ignore_attr = TRUE)
})

test_that("block_columns block means match a naive double loop on a non-square grid", {
  set.seed(1)
  nx <- 4; ny <- 6; f <- 2
  x <- matrix(rnorm(nx * ny), nx, ny)
  expected <- matrix(NA_real_, nx / f, ny / f)
  for (i in seq_len(nx / f)) for (j in seq_len(ny / f)) {
    expected[i, j] <- mean(x[(i - 1) * f + 1:f, (j - 1) * f + 1:f])
  }
  expect_equal(matrix(colMeans(block_columns(x, f)), nx / f, ny / f), expected)
})

test_that("lat_to_ascending accepts a single-element lat", {
  res <- lat_to_ascending(matrix(1:2, nrow = 2), 5, "lbl")
  expect_identical(res$lat, 5)
  expect_equal(dim(res$data), c(2L, 1L))
})

test_that("lat_to_ascending keeps a 3-D array with ny == 1", {
  x <- array(1:6, dim = c(2, 1, 3))
  res <- lat_to_ascending(x, 5, "lbl")
  expect_identical(res$data, x)
})
