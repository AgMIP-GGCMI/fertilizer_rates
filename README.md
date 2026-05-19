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

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for devcontainer setup, running the script, testing (full / fast suites, PNG snapshot review), coverage, and container internals (firewall allowlist, security caveat).
