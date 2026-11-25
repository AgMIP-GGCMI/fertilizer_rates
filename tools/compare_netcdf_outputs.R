#!/usr/bin/env Rscript
# ============================================================================
# compare_netcdf_outputs.R
# ============================================================================
# CLI wrapper around compare_netcdf_dirs() (tools/netcdf_compare.R). Prints one
# line per .nc file, `<STATUS> <path> <ref_bytes> -> <new_bytes> bytes <detail>`
# (sizes are informational), and exits with status 1 if any file is not OK or if
# no .nc files are found in either directory.
#
# Usage:
#   Rscript tools/compare_netcdf_outputs.R <ref_dir> <new_dir>
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("Usage: Rscript tools/compare_netcdf_outputs.R <ref_dir> <new_dir>")
}

file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
tools_dir <- if (length(file_arg) == 1) {
  dirname(sub("^--file=", "", file_arg))
} else {
  # Interactive source() fallback.
  "tools"
}
source(file.path(tools_dir, "netcdf_compare.R"))

res <- compare_netcdf_dirs(args[1], args[2])
for (i in seq_len(nrow(res))) {
  cat(sprintf("%s %s %s -> %s bytes %s\n", res$status[i], res$path[i],
              format(res$ref_bytes[i]), format(res$new_bytes[i]), res$detail[i]))
}
if (nrow(res) == 0) cat("No .nc files found in either directory\n")
quit(status = if (nrow(res) > 0 && all(res$status == "OK")) 0 else 1)
