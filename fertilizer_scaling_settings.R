# ============================================================================
# Shared Settings for fertilizer_scaling_isimip3b.R
# ============================================================================
# Sourced by fertilizer_scaling_isimip3b.R, by the testthat setup.R files, and by
# tools/render_diagnostics_png.R. Sources the settings shared with ISIMIP4
# (fertilizer_scaling_common_settings.R, which loads the libraries; paths are
# relative to the repo root, which every caller already runs from or chdirs to)
# and defines the top-level constants and path env-var defaults used by main()
# and helpers.
#
# Kept side-effect-light: it sources the shared settings file and otherwise does
# assignments only. No I/O beyond that source; the only function calls are
# Sys.getenv() and the lapply() that builds crop_to_funcgroup.
# ============================================================================

source("fertilizer_scaling_common_settings.R")

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
cropnames <- ggcmi_cropnames

# mapping from GGCMI crops to input file base names
crop_to_inputfile <- ggcmi_crop_to_inputcrop

# mapping from crops to functional groups in time series data
crop_to_funcgroup <- lapply(ggcmi_crop_to_cft, function(cft) paste0("fertl_", cft))

# scenario definitions
scenarios <- c("histsoc")
ssps <- c("ssp126", "ssp370", "ssp585")
iams <- c("image", "magpie")
gcms <- c("gfdl-esm4", "ipsl-cm6a-lr", "mpi-esm1-2-hr", "mri-esm2-0", "ukesm1-0-ll")

# scaling methods to run (edit here for manual control)
scaling_methods <- c("lambda")  #c("relative", "lambda")


# reference year for scaling (both methods)
base_year <- 2000
