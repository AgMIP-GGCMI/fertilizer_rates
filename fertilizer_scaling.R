# ============================================================================
# Fertilizer Scaling Script
# ============================================================================
# 
# Purpose:
#   Scale gridded fertilizer application rates from year 2000 baseline
#   to time series data (1850-2100). Production uses the lambda method; a
#   relative-change method is also implemented. Which methods run is set by
#   scaling_methods in fertilizer_scaling_settings.R (production: lambda only).
#
# Input:
#   - Spatial patterns: 5 arcmin resolution fertilizer rates for year 2000
#   - Time series: 0.5 degree resolution temporal trends by crop functional groups
#
# Output:
#   - Scaled fertilizer rates at 0.5 degree resolution for multiple scenarios
#   - A separate output tree for each enabled scaling method (lambda/, relative/)
#
# Scaling Methods:
#   1. Lambda (precipitation-style adapted for fertilizer; used in production):
#      scaled[t] = F_ref * [1 + (fert_diff / F_ref_base) * (F_ref_base / F_ts_base)^lambda]
#      where:
#        - F_ref = base_rate (spatial baseline at year 2000)
#        - F_ref_base = base_rate (same, at base year 2000)
#        - F_ts_base = timeseries at base year 2000
#        - fert_diff = timeseries[t] - timeseries[base_year] (difference relative to base year)
#        - lambda = sqrt(F_ts_base / F_ref_base) if F_ts_base < F_ref_base, else 1
#      Uses per-cell differences from base year with lambda correction to dampen amplification when
#      timeseries baseline is lower than spatial baseline. With lambda = 1 this equals method 2.
#      Additional rules (see scale_with_timeseries):
#        - results are clamped to 0..500 kg ha-1 yr-1
#        - cells with base_rate == 0 take the raw timeseries
#        - cells with base_rate > 0 but F_ts_base < 1 use a delayed anchor:
#          base_rate * timeseries[t] / timeseries[y*], with y* the first year
#          of the run's series where timeseries >= 1 (raw timeseries if none)
#
#   2. Relative Change (optional; not run in production):
#      scaled[t] = base_rate * (timeseries[t] / timeseries[2000])
#      Preserves spatial patterns while applying temporal trends as multiplicative factors
#
#   Method behavior when both are enabled (important for interpreting comparison maps):
#      The lambda method can produce higher or lower values than the relative method depending on:
#      - The ratio base_rate / timeseries[base] (spatial vs timeseries baseline)
#      - The magnitude of changes and lambda exponent value
#      When timeseries baselines are much lower than spatial baselines, the amplification term
#      (base_rate / ts_base)^lambda can be large, causing lambda-scaled to exceed relative-scaled even
#      for increases. Conversely, for decreases or when amplification is weak, lambda may be lower.
#      Console diagnostics report overlap frequencies, helping identify regions and seasons where
#      each method dominates.
#
# Workflow:
#   1. Load spatial pattern at 5 arcmin (year 2000 baseline)
#   2. Aggregate to 0.5 degree resolution
#   3. Load time series data for corresponding functional group
#   4. For each method in scaling_methods (production: lambda only):
#      a. Apply scaling to spatial pattern
#      b. Create diagnostic plots with outlier analysis
#      c. Write output NetCDF files with method identifier
#   5. Run validation tests
#
# Author: Generated for AgMIP-GGCMI
# Date: 2026-01-15
# ============================================================================

# Usage and production runs: see the EXECUTION block at the end of this file
# and the "Usage" section of README.md.

# Libraries, paths, crop mappings, scenario lists, base_year — see file.
source("fertilizer_scaling_settings.R")

# ============================================================================
# Load function definitions (extracted to a separate file to keep this script
# executable top-level-only).
# ============================================================================
source("fertilizer_scaling_functions.R")


# Get command line arguments
args <- commandArgs(trailingOnly = TRUE)

# For testing with source(): set default if no args provided
if (length(args) == 0) {
  # Default to maize for interactive testing
  args <- c("mai")
  print("No command line arguments provided. Using default: mai")
}

# Validate and parse CLI arguments for production usage
if (length(args) < 2) {
  stop("Usage: Rscript fertilizer_scaling.R <crop> <scenario> [iam] [gcm]\n",
       "Example (historical): Rscript fertilizer_scaling.R mai histsoc\n",
       "Example (future):     Rscript fertilizer_scaling.R mai ssp585 image gfdl-esm4")
}

crop <- args[1]
scenario <- args[2]
iam <- if (length(args) >= 3) args[3] else NULL
gcm <- if (length(args) >= 4) args[4] else NULL

# Check crop
if (!(crop %in% cropnames)) {
  stop(paste("Invalid crop name:", crop, "- must be one of:", paste(cropnames, collapse = ", ")))
}

# Execute single requested job
main(crop, scenario, iam, gcm)

# ============================================================================
# EXECUTION
# ============================================================================
#
# Run from the repo root, one crop and scenario per invocation:
#   Rscript fertilizer_scaling.R <crop> <scenario> [iam] [gcm]
#   Rscript fertilizer_scaling.R mai histsoc
#   Rscript fertilizer_scaling.R mai ssp585 image gfdl-esm4
# (iam and gcm are required for future scenarios.)
#
# Production (all crops x all scenarios, PIK cluster):
#   sbatch submit_fertilizer_scaling_full.jcf
#
# Argument values, output paths, and file names: see the "Usage" section of
# README.md.
#
# ============================================================================

print(paste("Completed processing for", crop))
