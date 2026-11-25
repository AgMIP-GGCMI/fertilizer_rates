# ============================================================================
# Settings shared by the ISIMIP3b and ISIMIP4 scripts
# ============================================================================
# Sourced by fertilizer_scaling_settings.R (ISIMIP3b) and
# fertilizer_scaling_isimip4_settings.R (ISIMIP4). Side-effect-light:
# library() loads and assignments only.
# ============================================================================

library(ncdf4)
library(testthat)
library(fields)
library(abind)
library(MASS)

# GGCMI crops processed in both rounds
ggcmi_cropnames <- c("swh", "wwh", "mai", "ri1", "ri2", "soy", "mil", "sor", "pea", "sgb", "cas", "rap", "sun", "nut", "sgc")

# GGCMI crop -> crop name in the input file names (ISIMIP3b: Mueller et al.
# 5-arcmin files; ISIMIP4: NPKGRIDS and CROPGRIDS files)
ggcmi_crop_to_inputcrop <- list(
  swh = "wheat", wwh = "wheat", mai = "maize", ri1 = "rice", ri2 = "rice",
  soy = "soybean", mil = "millet", sor = "sorghum", pea = "pea",
  sgb = "sugarbeet", cas = "cassava", rap = "rapeseed", sun = "sunflower",
  nut = "groundnut", sgc = "sugarcane"
)

# GGCMI crop -> crop functional type of the ISIMIP N-fertilizer time series.
# Each round's settings build its variable names from these (ISIMIP3b
# "fertl_<cft>", ISIMIP4 "<cft>_fertl").
ggcmi_crop_to_cft <- list(
  swh = "c3ann", wwh = "c3ann", mai = "c4ann", ri1 = "c3ann", ri2 = "c3ann",
  soy = "c3nfx", mil = "c4ann", sor = "c4ann", pea = "c3nfx", sgb = "c3ann",
  cas = "c3per", rap = "c3ann", sun = "c3ann", nut = "c3nfx", sgc = "c4per"
)
