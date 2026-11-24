# ============================================================================
# Shared Settings for fertilizer_scaling.R
# ============================================================================
# Sourced by fertilizer_scaling.R, by the testthat setup.R files, and by
# tools/render_diagnostics_png.R. Loads required libraries and defines the
# top-level constants and path env-var defaults used by main() and helpers.
#
# Kept side-effect-light: only library() loads and assignments. No I/O, no
# function calls beyond Sys.getenv().
# ============================================================================

# load libraries
library(ncdf4)
library(testthat)
library(fields)
library(abind)
library(MASS)

# input/output paths (override via .Renviron, which is in .gitignore)
base_path_5min <- Sys.getenv(
  "FERT_BASE_PATH_5MIN",
  "/p/projects/ikiimp/5min_input/toolbox_paper_application/fertilizer_paper/tmp/work_5min"
)
base_path_timeseries <- Sys.getenv(
  "FERT_BASE_PATH_TIMESERIES",
  "/p/projects/isimip/isimip/ISIMIP3b/InputData/socioeconomic/n-fertilizer"
)
output_base_path <- Sys.getenv(
  "FERT_OUTPUT_BASE_PATH",
  "/p/projects/macmit/data/GGCMI/AgMIP.input/phase3/n-fertilizer/group_iii"
)

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

# scaling methods to run (edit here for manual control)
scaling_methods <- c("lambda")  #c("relative", "lambda")


# reference year for scaling (both methods)
base_year <- 2000
