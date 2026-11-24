# christoph_fert_scripts

R scripts that prepare gridded nitrogen-fertilizer application rates for the agriculture sector of the [Inter-Sectoral Impacts Model Intercomparison Project (ISIMIP)](https://www.isimip.org/), targeting the ISIMIP3b round.

## What this does

`fertilizer_scaling.R` produces per-crop, half-degree (0.5°), annual N-fertilizer application-rate NetCDF files covering 1850–2100 for the 15 ISIMIP3b / GGCMI crops (`swh`, `wwh`, `mai`, `ri1`, `ri2`, `soy`, `mil`, `sor`, `pea`, `sgb`, `cas`, `rap`, `sun`, `nut`, `sgc`). It combines two inputs per crop:

- a **spatial baseline** at 5 arc-minute resolution from Mueller et al. (year-2000 sub-national application rates), aggregated up to 0.5°, and
- a **temporal time series** at 0.5° from ISIMIP3b's socioeconomic inputs, indexed by crop functional group (`fertl_c3ann`, `fertl_c4ann`, `fertl_c3nfx`, `fertl_c3per`, `fertl_c4per`).

Two scaling methods are run for every (crop, scenario) and produce parallel `relative/` and `lambda/` output trees:

1. **Relative change (default):** `scaled[t] = base_rate × (timeseries[t] / timeseries[2000])`. Preserves the spatial pattern and applies the temporal trend as a multiplicative factor.
2. **Lambda:** per-cell difference from the base year, with a `√(F_ts_base / F_ref_base)` exponent that dampens amplification when the timeseries baseline is much lower than the spatial baseline.

Scenarios cover historical (`histsoc`, 1850–2014) and futures (each SSP × IAM × GCM combination, 2015–2100). The production sweep over all 15 crops × 3 SSPs × 2 IAMs × 5 GCMs is invoked as a bash loop — see the commented-out template at the top of `fertilizer_scaling.R`. Each run also emits per-method diagnostic PDFs and a `compare_relative_lambda` cross-method summary PDF.

## Usage

### Requirements

R with the packages `ncdf4`, `fields`, `abind`, `MASS`, and `testthat` (developed with R 4.5).

The repo's `.Rprofile` activates renv, which hides your usual R library whenever R starts in the repo root. So install the versions pinned in `renv.lock` once, from the repo root:

```bash
Rscript -e 'renv::restore()'
```

Alternatively, use the devcontainer described in [DEVELOPMENT.md](DEVELOPMENT.md), which provides the packages (current CRAN versions rather than the `renv.lock` pins), or set `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` to skip renv and use your own library, as the SLURM job script does.

### Input and output locations

By default the script reads its inputs from, and writes its outputs to, fixed paths on the PIK cluster. To run anywhere else, point it at local copies through a `.Renviron` file — see [Input data and paths](DEVELOPMENT.md#input-data-and-paths).

### Running one job

Run from the repo root. Each invocation processes one crop for one scenario:

```bash
Rscript fertilizer_scaling.R <crop> <scenario> [iam] [gcm]

# Historical, 1850–2014
Rscript fertilizer_scaling.R mai histsoc

# Future, 2015–2100 (iam and gcm are required)
Rscript fertilizer_scaling.R mai ssp585 image gfdl-esm4
```

| Argument | Values |
| --- | --- |
| `crop` | `swh`, `wwh`, `mai`, `ri1`, `ri2`, `soy`, `mil`, `sor`, `pea`, `sgb`, `cas`, `rap`, `sun`, `nut`, `sgc` |
| `scenario` | `histsoc`, `ssp126`, `ssp370`, `ssp585` |
| `iam` | `image`, `magpie` |
| `gcm` | `gfdl-esm4`, `ipsl-cm6a-lr`, `mpi-esm1-2-hr`, `mri-esm2-0`, `ukesm1-0-ll` |

Only the argument count and `crop` are checked up front. A mistyped scenario, IAM, or GCM prints `Time series file does not exist: <path>`, writes nothing, and still exits with status 0, so a SLURM task with a typo looks successful. Check the output for `does not exist` lines (see [Missing inputs](DEVELOPMENT.md#missing-inputs)).

Which scaling methods run is set by `scaling_methods` in [fertilizer_scaling_settings.R](fertilizer_scaling_settings.R). It currently lists only `"lambda"`, so only `lambda/` outputs are written; set it to `c("relative", "lambda")` to also get `relative/` outputs and the relative-vs-lambda comparison PDF.

### Outputs

Outputs go under `<output>`, the value of `FERT_OUTPUT_BASE_PATH` (by default the PIK production directory). Each enabled method writes a NetCDF with one data variable, `fertl_<crop>` (kg ha⁻¹ yr⁻¹, 0.5° grid), plus a diagnostics PDF alongside it with the same name but `.nc` replaced by `_diagnostics.pdf`:

```
<output>/histsoc/<method>/n-fertilizer_<crop>_histsoc_<method>_annual_1850_2014.nc
<output>/<ssp>soc-adapt/<method>/n-fertilizer_<crop>_<iam>_<gcm>_<ssp>_<method>_annual_2015_2100.nc
```

When both methods are enabled, a comparison PDF is also written to the scenario directory:

```
<output>/histsoc/comparison_relative_lambda_<crop>_histsoc.pdf
<output>/<ssp>soc-adapt/comparison_relative_lambda_<crop>_<ssp>_<iam>_<gcm>.pdf
```

### Full production sweep (PIK cluster)

`submit_fertilizer_scaling_full.jcf` is a SLURM array job that runs all 465 combinations (15 crops × [1 histsoc + 3 SSPs × 2 IAMs × 5 GCMs]):

```bash
sbatch submit_fertilizer_scaling_full.jcf
```

It changes into a hard-coded `SCRIPT_DIR`, writes logs to `logs/` under the default output path (the `--output`, `--error`, and `mkdir -p` lines), and charges the `macmit` account. It runs `Rscript --vanilla`, which ignores `.Renviron`, so outputs go to the default production output path unless you export the `FERT_*` variables in your shell before running `sbatch`. Edit these before submitting from another checkout or account, and if you change the log location, create that directory before running `sbatch` (SLURM won't create it).

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for devcontainer setup, input data and paths, running the script, testing (full / fast suites, PNG snapshot review), coverage, and container internals (firewall allowlist, security caveat).
