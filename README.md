# christoph_fert_scripts

R scripts that prepare gridded nitrogen-fertilizer application rates for the agriculture sector of the [Inter-Sectoral Impacts Model Intercomparison Project (ISIMIP)](https://www.isimip.org/), targeting the ISIMIP3b round.

## What this does

`fertilizer_scaling_isimip3b.R` (the ISIMIP3b group III script; an ISIMIP4 script is coming in this branch) produces per-crop, half-degree (0.5°), annual N-fertilizer application-rate NetCDF files covering 1850–2100 for the 15 ISIMIP3b / GGCMI crops (`swh`, `wwh`, `mai`, `ri1`, `ri2`, `soy`, `mil`, `sor`, `pea`, `sgb`, `cas`, `rap`, `sun`, `nut`, `sgc`). It combines two inputs per crop:

- a **spatial baseline** at 5 arc-minute resolution from Mueller et al. (year-2000 sub-national application rates), aggregated up to 0.5°, and
- a **temporal time series** at 0.5° from ISIMIP3b's socioeconomic inputs, indexed by crop functional group (`fertl_c3ann`, `fertl_c4ann`, `fertl_c3nfx`, `fertl_c3per`, `fertl_c4per`).

The scaling method used in production is **lambda**, applied per grid cell:

`scaled[t] = base_rate × [1 + (timeseries[t] − timeseries[2000]) / base_rate × (base_rate / timeseries[2000])^λ]`

With λ = 1 this reduces to the relative-change method below. Where the timeseries baseline is lower than the spatial baseline, λ = √(timeseries[2000] / base_rate) < 1, which dampens how strongly timeseries changes are amplified. In addition:

- results are clamped to 0–500 kg ha⁻¹ yr⁻¹;
- cells with a zero spatial baseline take the raw timeseries;
- cells whose year-2000 timeseries value is below 1 kg ha⁻¹ yr⁻¹ are instead scaled by `timeseries[t] / timeseries[y*]`, where y* is the first year of the run's own series (1850–2014 for histsoc, 2015–2100 for futures) in which the timeseries reaches 1. For histsoc, y* can therefore fall before 2000. If the series never reaches 1, the cell takes the raw timeseries.

Outputs go to a `lambda/` output tree.

An alternative **relative-change** method, `scaled[t] = base_rate × (timeseries[t] / timeseries[2000])`, is also implemented. It preserves the spatial pattern and applies the temporal trend as a multiplicative factor, writing to a parallel `relative/` tree. It is not run in production, but can be enabled for comparison through `scaling_methods` (see [Running one job](#running-one-job)).

Scenarios cover historical (`histsoc`, 1850–2014) and futures (each SSP × IAM × GCM combination, 2015–2100). The production sweep over all 15 crops × (histsoc + 3 SSPs × 2 IAMs × 5 GCMs) runs as a SLURM array job (see [Full production sweep](#full-production-sweep-pik-cluster)). Each run also writes a diagnostics PDF per enabled method and, when both methods are enabled, a relative-vs-lambda comparison PDF.

## Usage

### Requirements

R with the packages `ncdf4`, `fields`, `abind`, `MASS`, and `testthat` (developed with R 4.5).

The repo's `.Rprofile` activates renv, which hides your usual R library whenever R starts in the repo root. So install the versions pinned in `renv.lock` once, from the repo root:

```bash
Rscript -e 'renv::restore()'
```

The lockfile also covers the dev and test tools (covr, lintr, DT, shiny, diffviewer and their dependencies), and some locked versions are archived CRAN releases that need a source build (e.g. `fields` needs gfortran). If you only run the scripts, restore just what they load: `Rscript -e 'renv::restore(packages = c("ncdf4", "fields", "abind", "MASS", "testthat"))'`.

Alternatively, use the devcontainer described in [DEVELOPMENT.md](DEVELOPMENT.md), which provides the packages (restored from `renv.lock`), or set `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` to skip renv and use your own library, as `slurm_run_task.sh` does.

### Input and output locations

By default the script reads its inputs from, and writes its outputs to, fixed paths on the PIK cluster. To run anywhere else, point it at local copies through a `.Renviron` file — see [Input data and paths](DEVELOPMENT.md#input-data-and-paths).

### Running one job

Run from the repo root. Each invocation processes one crop for one scenario:

```bash
Rscript fertilizer_scaling_isimip3b.R <crop> <scenario> [iam] [gcm]

# Historical, 1850–2014
Rscript fertilizer_scaling_isimip3b.R mai histsoc

# Future, 2015–2100 (iam and gcm are required)
Rscript fertilizer_scaling_isimip3b.R mai ssp585 image gfdl-esm4
```

| Argument | Values |
| --- | --- |
| `crop` | `swh`, `wwh`, `mai`, `ri1`, `ri2`, `soy`, `mil`, `sor`, `pea`, `sgb`, `cas`, `rap`, `sun`, `nut`, `sgc` |
| `scenario` | `histsoc`, `ssp126`, `ssp370`, `ssp585` |
| `iam` | `image`, `magpie` |
| `gcm` | `gfdl-esm4`, `ipsl-cm6a-lr`, `mpi-esm1-2-hr`, `mri-esm2-0`, `ukesm1-0-ll` |

Only the argument count and `crop` are checked up front. A mistyped scenario, IAM, or GCM prints `Time series file does not exist: <path>`, writes nothing, and still exits with status 0, so a SLURM task with a typo looks successful. Check the output for `does not exist` lines (see [Missing inputs](DEVELOPMENT.md#missing-inputs)).

Which scaling methods run is set by `scaling_methods` in [fertilizer_scaling_settings.R](fertilizer_scaling_settings.R). It is set to `"lambda"` only (the production configuration), so only `lambda/` outputs are written; set it to `c("relative", "lambda")` to also get `relative/` outputs and the relative-vs-lambda comparison PDF.

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

The job body (module load, task checks, `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE`, the `Rscript --vanilla` call) lives in `slurm_run_task.sh`, which the `.jcf` sources from `SCRIPT_DIR`; it must sit there next to the `.jcf` on the cluster, or the job exits with status 4. The job changes into a hard-coded `SCRIPT_DIR`, writes logs to `logs/` under the default output path (the `--output`, `--error`, and `mkdir -p` lines), and charges the `macmit` account. It runs `Rscript --vanilla`, which ignores `.Renviron`, so outputs go to the default production output path unless you export the `FERT_*` variables in your shell before running `sbatch`. Edit these before submitting from another checkout or account, and if you change the log location, create that directory before running `sbatch` (SLURM won't create it).

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for devcontainer setup, input data and paths, testing (full / fast suites, PNG snapshot review), coverage, and container internals (firewall allowlist, security caveat).
