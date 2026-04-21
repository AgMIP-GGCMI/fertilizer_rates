# ============================================================================
# Plot-diagnostics helpers extracted from plot_diagnostics()
# ============================================================================
# Sourced by fertilizer_scaling_functions.R. All functions assume that
# plot_diagnostics (in fertilizer_scaling_functions.R) has already opened
# the appropriate graphics device and set up par().
# ============================================================================

# ----------------------------------------------------------------------------
# build_sample_locations
# ----------------------------------------------------------------------------
# Returns the 10-row data frame of sample lat/lon/description values used
# for time-series plots and map overlays in plot_diagnostics.
# ----------------------------------------------------------------------------
build_sample_locations <- function() {
  data.frame(
    lat = c(8.0, 9.5, 26.0, -30.0, 40.0, 42.0, 30.0, 34.0, -15.0, -23.0),
    lon = c(-2.0, 37.0, 87.0, -60.0, -5.0, -93.5, 75.0, 114.0, -48.0, -47.0),
    description = c(
      "W Africa (Ghana)", "E Africa (Ethiopia)", "E India (Bihar)",
      "S Brazil (RS)", "N Spain", "US Iowa", "NW India (Punjab)",
      "N China (Henan)", "C Brazil (Mato Grosso)", "SE Brazil (SP)"
    ),
    stringsAsFactors = FALSE
  )
}

# ----------------------------------------------------------------------------
# add_sample_markers
# ----------------------------------------------------------------------------
# Overlays numbered circle markers at each sample location on the currently
# active map. Caller is responsible for calling this only when a map is
# currently plotted.
#
# Args:
#   lon, lat: Grid-cell coordinate vectors for the map being overlaid.
#   sample_locations: Data frame from build_sample_locations().
# ----------------------------------------------------------------------------
add_sample_markers <- function(lon, lat, sample_locations) {
  for (k in 1:nrow(sample_locations)) {
    target_lon <- sample_locations$lon[k]
    target_lat <- sample_locations$lat[k]

    i <- which.min(abs(lon - target_lon))
    j <- which.min(abs(lat - target_lat))
    marker_lon <- lon[i]
    marker_lat <- lat[j]

    points(marker_lon, marker_lat, pch = 21, col = "black", bg = NA,
           cex = 1.5, lwd = 0.8)
    text(marker_lon, marker_lat, k, cex = 0.5, col = "black", font = 2)
  }
}
