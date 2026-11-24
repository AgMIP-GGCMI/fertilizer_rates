# NetCDF regression baselines

Reference NetCDF outputs that the ssp126 block of `tests/testthat-slow/test-plot_diagnostics_regression.R` compares against on every run, to catch unintended drift in the script's numeric output.

## Contents

| File | Scenario | Crop | IAM | GCM | Method | Years |
| --- | --- | --- | --- | --- | --- | --- |
| `n-fertilizer_mai_image_gfdl-esm4_ssp126_relative_annual_2015_2017.nc` | ssp126 | mai | image | gfdl-esm4 | relative | 2015–2017 |
| `n-fertilizer_mai_image_gfdl-esm4_ssp126_lambda_annual_2015_2017.nc`   | ssp126 | mai | image | gfdl-esm4 | lambda   | 2015–2017 |

Each file is a 720 × 360 × 3 (lon × lat × time) slice of the full 2015–2100 production output. All variable and dimension attributes (`units`, `_FillValue`, `long_name`, `scaling_method`, `base_year`, etc.) are preserved verbatim from the source. A `history` global attribute records the slicing operation.

## Generating / updating

The baselines are sliced from the full production outputs at `data/outputs/ssp126soc-adapt/<method>/n-fertilizer_mai_image_gfdl-esm4_ssp126_<method>_annual_2015_2100.nc`. To regenerate after an intentional change to the script's output:

1. Produce fresh outputs by running, from the repo root:

   ```bash
   Rscript fertilizer_scaling.R mai ssp126 image gfdl-esm4
   ```

   Or, in an R session started in the repo root, run `source("fertilizer_scaling_settings.R")`, then `source("fertilizer_scaling_functions.R")`, then `main("mai", "ssp126", "image", "gfdl-esm4")`.

   Either way, the outputs land under `data/outputs/` when `FERT_OUTPUT_BASE_PATH` points there, as in the `.Renviron` described in [Input data and paths](../../../DEVELOPMENT.md#input-data-and-paths). If the variable is unset, they go to the PIK production path.
2. Re-slice both methods with the snippet below (run from the repo root):

   ```r
   library(ncdf4)
   for (m in c("relative", "lambda")) {
     src <- sprintf("data/outputs/ssp126soc-adapt/%s/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2100.nc", m, m)
     dst <- sprintf("tests/testthat-slow/baselines/n-fertilizer_mai_image_gfdl-esm4_ssp126_%s_annual_2015_2017.nc", m)
     in_nc <- nc_open(src); on.exit(nc_close(in_nc), add = TRUE)
     var_name <- names(in_nc$var)[1]
     lon <- ncvar_get(in_nc, "lon")
     lat <- ncvar_get(in_nc, "lat")
     time_full <- ncvar_get(in_nc, "time")
     time_units <- ncatt_get(in_nc, "time", "units")$value
     data <- ncvar_get(in_nc, var_name, start = c(1, 1, 1), count = c(-1, -1, 3))
     var_atts <- ncatt_get(in_nc, var_name)
     glb_atts <- ncatt_get(in_nc, 0)
     dim_lon <- ncdim_def("lon", "degrees_east", lon)
     dim_lat <- ncdim_def("lat", "degrees_north", lat)
     dim_time <- ncdim_def("time", time_units, time_full[1:3])
     ncv <- ncvar_def(name = var_name, units = var_atts$units,
                      dim = list(dim_lon, dim_lat, dim_time),
                      missval = var_atts$`_FillValue`, prec = "float",
                      longname = var_atts$long_name, compression = 9, verbose = FALSE)
     out_nc <- nc_create(dst, list(ncv), verbose = FALSE)
     ncvar_put(out_nc, ncv, data, start = c(1, 1, 1), count = c(-1, -1, 3))
     for (a in names(glb_atts)) ncatt_put(out_nc, 0, a, glb_atts[[a]])
     ncatt_put(out_nc, 0, "history", paste0(
       format(Sys.Date()),
       ": sliced first 3 time steps from ", basename(src),
       " for use as a regression baseline"))
     nc_close(out_nc)
   }
   ```

3. Commit both baselines together with a message explaining what changed in the script.

## When the comparison test fails

A failure means the script's first-3-year output drifted from the committed baseline. Decide whether the change is intentional:

- **Intentional** (e.g. you changed the scaling formula): regenerate the baselines (see above) and commit alongside the script change.
- **Unintentional**: bisect to find the regression. The PNG snapshot tests in `_snaps/plot_diagnostics_regression/` likely also flag the change and can help localize it.
