# ============================================================================
# Fertilizer Scaling Script
# ============================================================================
# 
# Purpose:
#   Scale gridded fertilizer application rates from year 2000 baseline
#   to time series data (1850-2100) using two alternative scaling methods.
#
# Input:
#   - Spatial patterns: 5 arcmin resolution fertilizer rates for year 2000
#   - Time series: 0.5 degree resolution temporal trends by crop functional groups
#
# Output:
#   - Scaled fertilizer rates at 0.5 degree resolution for multiple scenarios
#   - Separate outputs for each scaling method (relative and lambda)
#
# Scaling Methods:
#   1. Relative Change (default):
#      scaled[t] = base_rate * (timeseries[t] / timeseries[2000])
#      Preserves spatial patterns while applying temporal trends as multiplicative factors
#
#   2. Lambda (precipitation-style adapted for fertilizer):
#      scaled[t] = F_ref * [1 + (fert_diff / F_ref_base) * (F_ref_base / F_ts_base)^lambda]
#      where:
#        - F_ref = base_rate (spatial baseline at year 2000)
#        - F_ref_base = base_rate (same, at base year 2000)
#        - F_ts_base = timeseries at base year 2000
#        - fert_diff = timeseries[t] - timeseries[base_year] (difference relative to base year)
#        - lambda = sqrt(F_ts_base / F_ref_base) if F_ts_base < F_ref_base, else 1
#      Uses per-cell differences from base year with lambda correction to dampen amplification when
#      timeseries baseline is lower than spatial baseline
#
#   Method behavior (important for interpreting maps):
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
#   4. For each method (relative and lambda):
#      a. Apply scaling to spatial pattern
#      b. Create diagnostic plots with outlier analysis
#      c. Write output NetCDF files with method identifier
#   5. Run validation tests
#
# Author: Generated for AgMIP-GGCMI
# Date: 2026-01-15
# ============================================================================

# for production, run bash loop over crops and scenarios
# for crop in swh wwh mai ri1 ri2 soy mil sor pea sgb cas rap sun nut sgc; do
#   # Historical scenario
#   Rscript fertilizer_scaling.R "$crop" histsoc
#   
#   # Future scenarios: all combinations of SSP, IAM, GCM
#   for ssp in ssp126 ssp370 ssp585; do
#     for iam in image magpie; do
#       for gcm in gfdl-esm4 ipsl-cm6a-lr mpi-esm1-2-hr mri-esm2-0 ukesm1-0-ll; do
#         Rscript fertilizer_scaling.R "$crop" "$ssp" "$iam" "$gcm"
#       done
#     done
#   done
# done

# =============================================================================

# for comparing the 2014 vs. 2015 years after scaling for each scenario, run: 
# for crop in swh wwh mai ri1 ri2 soy mil sor pea sgb cas rap sun nut sgc; do
#   Rscript compare_histsoc_future.R "$crop"
# done

# ============================================================================

# load libraries
library(ncdf4)
library(testthat)
library(fields)
library(abind)
library(MASS)

# settings

# input paths
base_path_5min <- "/p/projects/ikiimp/5min_input/toolbox_paper_application/fertilizer_paper/tmp/work_5min"
base_path_timeseries <- "/p/projects/isimip/isimip/ISIMIP3b/InputData/socioeconomic/n-fertilizer"
output_base_path <- "/p/projects/macmit/data/GGCMI/AgMIP.input/phase3/n-fertilizer/group_iii"

# crop definitions
cropnames <- c("swh", "wwh", "mai", "ri1", "ri2", "soy", "mil", "sor", "pea", "sgb", "cas", "rap", "sun", "nut", "sgc")

# mapping from GGCMI crops to input file base names
crop_to_inputfile <- list(
  swh = "wheat",
  wwh = "wheat",
  mai = "maize",
  ri1 = "rice",
  ri2 = "rice",
  soy = "soybean",
  mil = "millet",
  sor = "sorghum",
  pea = "pea",
  sgb = "sugarbeet",
  cas = "cassava",
  rap = "rapeseed",
  sun = "sunflower",
  nut = "groundnut",
  sgc = "sugarcane"
)

# mapping from crops to functional groups in time series data
crop_to_funcgroup <- list(
  swh = "fertl_c3ann",
  wwh = "fertl_c3ann",
  mai = "fertl_c4ann",
  ri1 = "fertl_c3ann",
  ri2 = "fertl_c3ann",
  soy = "fertl_c3nfx",
  mil = "fertl_c4ann",
  sor = "fertl_c4ann",
  pea = "fertl_c3nfx",
  sgb = "fertl_c3ann",
  cas = "fertl_c3per",
  rap = "fertl_c3ann",
  sun = "fertl_c3ann",
  nut = "fertl_c3nfx",
  sgc = "fertl_c4per"
)

# scenario definitions
scenarios <- c("histsoc")
ssps <- c("ssp126", "ssp370", "ssp585")
iams <- c("image", "magpie")
gcms <- c("gfdl-esm4", "ipsl-cm6a-lr", "mpi-esm1-2-hr", "mri-esm2-0", "ukesm1-0-ll")

# reference year for relative scaling
base_year <- 2000

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
# EXECUTION AND TESTING
# ============================================================================
# 
# QUICK START (single crop, test scenarios):
#   Rscript fertilizer_scaling.R mai histsoc
#   Rscript fertilizer_scaling.R mai ssp585 image gfdl-esm4
#
# PRODUCTION MODE (all crops, all scenarios):
#   1. For all 15 crops individually:
#      for crop in swh wwh mai ri1 ri2 soy mil sor pea sgb cas rap sun nut sgc; do
#        Rscript fertilizer_scaling.R $crop
#      done
#
#   2. For cross-scenario (2014 vs 2015) comparisons, use compare_histsoc_future.R
#
# OUTPUT:
#   - Scaled NetCDF files: output_base_path/{relative,lambda}/{crop}_{scenario}.nc
#   - Diagnostic plots: output_base_path/diagnostics/{crop}_{scenario}_*.pdf
#   - Cross-scenario plots: output_base_path/cross_scenario/{crop}_{ssp}_{iam}_{gcm}_*.pdf
#
# COMMAND-LINE ARGUMENTS:
#   arg1: crop name (required, e.g., mai)
#   arg2: scenario (required: histsoc or an SSP)
#
# ============================================================================

print(paste("Completed processing for", crop))
