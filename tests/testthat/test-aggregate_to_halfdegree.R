# Tests for aggregate_to_halfdegree() in fertilizer_scaling_functions.R.
#
# The function only accepts 4320 x 2160 (5 arcmin) input and writes into a
# hardcoded 720 x 360 (0.5 degree) output grid, so each test builds a full-size
# NA-filled base and stamps in just the blocks it needs to exercise.

make_input <- function() array(NA_real_, dim = c(4320, 2160))

# Realistic 5-arcmin coordinate vectors.
# make_lon_asc() / make_lat_asc() produce south->north / west->east ordering.
# make_lat_desc() produces north->south ordering (Mueller production files).
make_lon_asc  <- function() seq(-179.958333, 179.958333, length.out = 4320)
make_lat_asc  <- function() seq(-89.958333,   89.958333, length.out = 2160)
make_lat_desc <- function() rev(make_lat_asc())

test_that("returns a list with data, lon, lat components", {
  result <- aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_asc())
  expect_type(result, "list")
  expect_named(result, c("data", "lon", "lat"))
})

test_that("output data has dimensions 720 x 360", {
  result <- aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_asc())
  expect_equal(dim(result$data), c(720, 360))
})

test_that("output longitude spans -179.75 to 179.75 by 0.5 degrees", {
  result <- aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_asc())
  expect_length(result$lon, 720)
  expect_equal(result$lon[1], -179.75, tolerance = 1e-4)
  expect_equal(result$lon[720], 179.75, tolerance = 1e-4)
  expect_equal(diff(result$lon), rep(0.5, 719), tolerance = 1e-4)
})

test_that("output latitude spans -89.75 to 89.75 by 0.5 degrees (ascending input)", {
  result <- aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_asc())
  expect_length(result$lat, 360)
  expect_equal(result$lat[1], -89.75, tolerance = 1e-4)
  expect_equal(result$lat[360], 89.75, tolerance = 1e-4)
  expect_equal(diff(result$lat), rep(0.5, 359), tolerance = 1e-4)
})

test_that("output latitude is canonicalized to ascending when input is descending", {
  result <- aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_desc())
  expect_true(all(diff(result$lat) > 0))
  expect_equal(result$lat[1], -89.75, tolerance = 1e-4)
  expect_equal(result$lat[360], 89.75, tolerance = 1e-4)
})

test_that("non-monotonic input lat fails with a clear error", {
  # Build a lat axis whose 6-cell block means are neither monotonically
  # ascending nor monotonically descending, so rev() can't canonicalize it
  # and the new defensive check fires. Reversing every other 12-cell block
  # (two output cells' worth) of an otherwise-ascending axis does the trick.
  lat_bad <- make_lat_asc()
  for (i in seq(1, length(lat_bad) - 12, by = 24)) {
    lat_bad[i:(i + 11)] <- rev(lat_bad[i:(i + 11)])
  }
  expect_error(
    aggregate_to_halfdegree(make_input(), make_lon_asc(), lat_bad),
    "not strictly ascending after canonicalization"
  )
})

test_that("non-monotonic input lon fails with a clear error", {
  # Same construction as the lat case, applied to lon. lon has no
  # canonicalization branch, so the input goes straight through colMeans
  # to the strict-ascending check.
  lon_bad <- make_lon_asc()
  for (i in seq(1, length(lon_bad) - 12, by = 24)) {
    lon_bad[i:(i + 11)] <- rev(lon_bad[i:(i + 11)])
  }
  expect_error(
    aggregate_to_halfdegree(make_input(), lon_bad, make_lat_asc()),
    "lon_halfdeg is not strictly ascending"
  )
})

test_that("uniform input produces a uniform output of the same value", {
  input <- array(3.5, dim = c(4320, 2160))
  result <- aggregate_to_halfdegree(input, make_lon_asc(), make_lat_asc())
  expect_true(all(result$data == 3.5))
})

test_that("all-NA input produces all-NA output (no NaN leakage)", {
  result <- aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_asc())
  expect_true(all(is.na(result$data)))
  expect_false(any(is.nan(result$data)))
})

test_that("a single 6x6 block averages to the mean of its 36 cells", {
  input <- make_input()
  input[1:6, 1:6] <- matrix(1:36, nrow = 6)
  result <- aggregate_to_halfdegree(input, make_lon_asc(), make_lat_asc())

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
  result <- aggregate_to_halfdegree(input, make_lon_asc(), make_lat_asc())
  expect_equal(result$data[1, 1], mean(non_na_values))
})

test_that("neighboring output cells aggregate from independent input blocks", {
  input <- make_input()
  input[1:6, 1:6]   <- 2    # -> output [1, 1]
  input[7:12, 1:6]  <- 4    # -> output [2, 1]
  input[1:6, 7:12]  <- 6    # -> output [1, 2]
  input[7:12, 7:12] <- 8    # -> output [2, 2]
  result <- aggregate_to_halfdegree(input, make_lon_asc(), make_lat_asc())

  expect_equal(result$data[1, 1], 2)
  expect_equal(result$data[2, 1], 4)
  expect_equal(result$data[1, 2], 6)
  expect_equal(result$data[2, 2], 8)
})

test_that("the last block maps correctly to output cell [720, 360]", {
  input <- make_input()
  input[4315:4320, 2155:2160] <- 7
  result <- aggregate_to_halfdegree(input, make_lon_asc(), make_lat_asc())
  expect_equal(result$data[720, 360], 7)
})

test_that("output coords are derived from input coords, not hardcoded", {
  # Shift all coords by a small offset; output coords should shift accordingly.
  lon_shifted <- make_lon_asc() + 0.01
  lat_shifted <- make_lat_asc() + 0.01
  result <- aggregate_to_halfdegree(make_input(), lon_shifted, lat_shifted)
  expect_equal(result$lon[1], -179.75 + 0.01, tolerance = 1e-4)
  expect_equal(result$lat[1], -89.75 + 0.01, tolerance = 1e-4)
})

test_that("transposed input fails with a clear error", {
  expect_error(
    aggregate_to_halfdegree(array(NA_real_, dim = c(2160, 4320)), make_lon_asc(), make_lat_asc()),
    "data_5min must be 4320 x 2160"
  )
})

test_that("wrong-length input fails with a clear error", {
  expect_error(
    aggregate_to_halfdegree(array(NA_real_, dim = c(4314, 2160)), make_lon_asc(), make_lat_asc()),
    "data_5min must be 4320 x 2160"
  )
})

test_that("wrong-length coordinate vectors fail with a clear error", {
  expect_error(
    aggregate_to_halfdegree(make_input(), make_lon_asc()[-1], make_lat_asc()),
    "lon_5min"
  )
  expect_error(
    aggregate_to_halfdegree(make_input(), make_lon_asc(), make_lat_asc()[-1]),
    "lat_5min"
  )
})
