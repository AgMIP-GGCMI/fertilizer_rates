# Development

Developer-facing companion to [README.md](README.md). Read that for what the project produces and how to run it; read here for how to set up the devcontainer, point the script at input data, exercise the test suites, and measure coverage.

## Devcontainer setup

This repo ships a `.devcontainer` that runs Claude Code inside a firewalled sandbox with R 4.5 and the R packages the scripts and tests use pre-installed (the current CRAN versions at image build time, not the versions pinned in `renv.lock`). The Superpowers Claude Code plugin is pre-configured at the project scope so it loads automatically the first time you trust the folder.

### Prerequisites

- **Podman**: `brew install podman && podman machine init && podman machine start`
- **VS Code** with the **Dev Containers** extension
- An **Anthropic** account (for first-run `claude` authentication)

On first install only, tell VS Code's Dev Containers extension to use podman instead of docker. Open User Settings (JSON) and add:

```json
"dev.containers.dockerPath": "podman"
```

The podman VM must be running (`podman machine start`) whenever you open the container.

### Opening the container

```bash
code .
```

Then: Command Palette → **"Dev Containers: Reopen in Container"**.

First build takes several minutes (R package compilation). Subsequent opens are fast thanks to image caching. The container's firewall activates automatically via the `postStartCommand` and verifies itself by confirming `https://example.com` is unreachable while `https://api.github.com` is.

### First-run inside the container

Open the integrated terminal (``Ctrl+` ``) and run:

```bash
claude
```

- Complete the first-run device-code authentication.
- Accept the folder-trust prompt for `/workspace`.
- Accept the "Install superpowers from claude-plugins-official?" prompt.

Verify with `/plugin` — the Installed tab should list `superpowers@claude-plugins-official` as enabled, and `/superpowers:` tab-completion should expose Superpowers' namespaced skills.

Authentication and the installed plugin persist across restarts via the `claude-code-config-${devcontainerId}` volume; you don't need to re-authenticate on every rebuild.

### Rebuilding

If you change the `Dockerfile`, the firewall script, or `devcontainer.json`: Command Palette → **"Dev Containers: Rebuild Container"**. Claude auth persists across rebuilds because the `/home/node/.claude` volume is keyed to the devcontainer ID, not the image.

### R packages

R packages (`ncdf4`, `testthat`, `fields`, `abind`, `MASS`, `lintr`) are baked into the image and resolved via `RENV_CONFIG_EXTERNAL_LIBRARIES`, so the repo's `.Rprofile` (which activates renv) still finds them. `renv.lock` is the authoritative dependency manifest; to install a new package, run `install.packages("pkg")` inside the container and — if you want the lockfile to reflect it — then `renv::snapshot()` and commit `renv.lock`.

## Input data and paths

`main()` reads its inputs from, and writes its outputs to, three directories defined in [fertilizer_scaling_settings.R](fertilizer_scaling_settings.R). Each can be overridden by an environment variable; when the variable is unset, the PIK cluster path is used.

| Environment variable | Contents | Default (PIK cluster) |
| --- | --- | --- |
| `FERT_BASE_PATH_5MIN` | Mueller et al. year-2000 N application rates at 5 arc-minutes, one file per input crop (some GGCMI crops share a file) | `/p/projects/ikiimp/5min_input/toolbox_paper_application/fertilizer_paper/tmp/work_5min` |
| `FERT_BASE_PATH_TIMESERIES` | ISIMIP3b `n-fertilizer-5crops` time series (LUH2 crop functional types) | `/p/projects/isimip/isimip/ISIMIP3b/InputData/socioeconomic/n-fertilizer` |
| `FERT_OUTPUT_BASE_PATH` | Output NetCDFs and diagnostic PDFs | `/p/projects/macmit/data/GGCMI/AgMIP.input/phase3/n-fertilizer/group_iii` |

### Running off the cluster: `.Renviron` and `data/`

Anywhere other than the PIK cluster (including this devcontainer), copy (or symlink) the inputs you need into `data/` and create a `.Renviron` in the repo root that points at them:

```
FERT_BASE_PATH_5MIN=./data/inputs/Napprate_gadm_subnational
FERT_BASE_PATH_TIMESERIES=./data/inputs/isimip_files
FERT_OUTPUT_BASE_PATH=./data/outputs
```

Both `.Renviron` and `data/` are gitignored, so every checkout needs its own copy — including each git worktree. Symlinking `data/inputs` (not `data` itself, which `.gitignore` only matches as a real directory), or using absolute paths in `.Renviron`, avoids duplicating the input files.

How `.Renviron` is picked up:

- R reads it only when started with the repo root as the working directory. The relative paths above resolve against that directory too. (`fertilizer_scaling.R` has to be run from the repo root anyway, because it `source()`s its siblings by relative path.)
- Its values take precedence over same-named variables exported in your shell: `FERT_OUTPUT_BASE_PATH=/tmp/x Rscript …` has no effect while `.Renviron` sets that variable.
- `Rscript --vanilla` skips it. The SLURM job script `submit_fertilizer_scaling_full.jcf` runs that way (from a hard-coded checkout directory), so cluster jobs ignore `.Renviron` and use the default paths — unless a `FERT_*` variable is exported in the shell you run `sbatch` from, which SLURM passes through by default.

Expected layout under `data/`:

```
data/
├── inputs/
│   ├── Napprate_gadm_subnational/
│   │   └── <input>Napprate_gadm_subnational.nc               # e.g. maizeNapprate_gadm_subnational.nc
│   └── isimip_files/
│       ├── histsoc/
│       │   └── n-fertilizer-5crops_histsoc_annual_1850_2014.nc
│       └── <ssp>soc-adapt/                                   # e.g. ssp126soc-adapt/
│           └── n-fertilizer-5crops_<iam>_<gcm>_<ssp>_annual_2015_2100.nc
└── outputs/                                                  # created by the script
```

- `<input>` is the crop's file base name from `crop_to_inputfile` in the settings file. Several crops share one (`swh` and `wwh` both read `wheat…`; `ri1` and `ri2` both read `rice…`).
- Future-scenario runs also read the histsoc time-series file, because its year-2000 slice is the scaling baseline.
- The script builds the same relative paths under the cluster defaults, so copying files across with their subdirectories keeps the layout correct. You only need the files for the crops and scenarios you plan to run.

### Missing inputs

Most missing inputs are not errors. If the 5-arcmin file or the scenario's own time-series file is missing, `main()` prints `Input file does not exist: <path>` or `Time series file does not exist: <path>`, returns without writing anything, and the process still exits with status 0. The log's final `Completed processing for <crop>` line appears even then, so if a run produces no output, look for the `does not exist` line. (A future-scenario run whose histsoc time-series file is missing does stop with an error.)

## Testing

Run the full test suite (unit tests + PNG regression tests):

    Rscript tests/testthat.R

The PNG regression tests render diagnostic plots for two reference scenarios (`mai histsoc` and `mai ssp126 image gfdl-esm4`) and compare them byte-for-byte against committed baseline PNGs. The slow suite takes about 50 seconds, and the full suite (fast and slow together) about a minute. The renders enable both scaling methods (relative and lambda) even though production runs lambda only, so the baseline PNGs include relative-method and relative-vs-lambda comparison pages, and the NetCDF baselines include a relative-method file.

To skip the slow tests during rapid iteration:

    Rscript tests/testthat-fast.R

### Test input data

Only the PNG regression tests (`tests/testthat-slow/test-plot_diagnostics_regression.R`) need real input data. Everything else — all of `tests/testthat/` plus `tests/testthat-slow/test-main_full_runs.R` — uses in-memory arrays or tiny synthetic NetCDFs written to temporary directories.

The PNG regression tests run `main()` on real inputs, found through `FERT_BASE_PATH_5MIN` and `FERT_BASE_PATH_TIMESERIES` as described in [Input data and paths](#input-data-and-paths). (Their outputs go to a temporary directory whatever `FERT_OUTPUT_BASE_PATH` says.) With the `.Renviron` shown there, they need:

- `data/inputs/Napprate_gadm_subnational/maizeNapprate_gadm_subnational.nc`
- `data/inputs/isimip_files/histsoc/n-fertilizer-5crops_histsoc_annual_1850_2014.nc`
- `data/inputs/isimip_files/ssp126soc-adapt/n-fertilizer-5crops_image_gfdl-esm4_ssp126_annual_2015_2100.nc`

Run the test and coverage scripts from the repo root (`Rscript tests/testthat.R`, not `cd tests && Rscript testthat.R`); otherwise `.Renviron` isn't loaded and the tests look for inputs at the cluster paths.

If the inputs can't be found, the suite does not say so directly. Look in the test output for the `Input file does not exist:` or `Time series file does not exist:` lines that `main()` prints (see [Missing inputs](#missing-inputs)). In that case the `mai histsoc` test is reported as **skipped ("empty test")**, because `main()` returns early and produces no PNGs to compare, and the `mai ssp126` test fails, either on a missing output file or with that same `does not exist` message as an error. Even with the inputs present, the slow suite reports 2 expected "empty test" skips (from the relative-method base-year and relative-changes checks) and 1 warning ("Could not find suitable cell for relative change test"), all from the `mai ssp126` test, which have nothing to check because a future scenario's output has no year 2000. Those skips are not a sign of missing inputs; missing inputs also make the `mai ssp126` test fail and print `does not exist` lines.

### When a PNG snapshot fails

testthat writes the mismatched render to `tests/testthat-slow/_snaps/plot_diagnostics_regression/<name>.new.png` alongside the baseline. To review in R, from the repo root:

    > testthat::snapshot_review("plot_diagnostics_regression/", "tests/testthat-slow")

If the change is intentional, accept the new baseline:

    Rscript tools/accept_diagnostics_baseline.R

Then commit the updated snapshot files alongside the code change that produced them.

### Environment caveat

Byte-identical PNG output is expected only inside this repo's devcontainer (`rocker/r-ver:4.5.0` base image plus the apt cairo/png libraries and CRAN R packages current when the image was built — a rebuild can pick up newer versions). Runs outside the container may produce legitimate pixel differences and will need fresh baselines captured in the devcontainer environment.

## Coverage

Generate a line-coverage report for `fertilizer_scaling_functions.R`:

    Rscript tests/coverage.R

This requires a one-time installation of the `covr` tool:

    Rscript -e 'renv::install("covr")'

The script instruments the source file with `covr` and runs both the fast and slow test suites against it. The slow PNG-regression tests are required to cover `main()`, `plot_diagnostics()`, and `compare_relative_lambda()` — they are exercised end-to-end rather than unit-tested — so the run takes a few minutes.

It prints a per-file summary to the console and, when the optional rendering deps are available, also writes a per-line HTML report to `coverage.html` (gitignored). Open it in a browser to see exactly which expressions went uncovered. The HTML deps aren't in `renv.lock` because of their transitive footprint; enable HTML output with:

    Rscript -e 'renv::install(c("DT", "htmltools"))'

Pass an optional threshold percentage to fail the run when coverage drops below it (intended for CI):

    Rscript tests/coverage.R 90

A companion fast-only report measures the support library files (`fertilizer_scaling_settings.R`, `fertilizer_scaling_plot_diagnostics_functions.R`, `tools/diagnostics_png_harness.R`) using just the fast suite — it runs in seconds and is forward-looking scaffolding for future unit tests of those helpers (today's number is 0% because no fast tests exercise them). It writes `coverage_fast.html` under the same DT/htmltools condition as above:

    Rscript tests/coverage_fast.R

## Container internals

### Firewall allowlist

The firewall script (`.devcontainer/init-firewall.sh`, forked from Anthropic's reference) runs as a `postStartCommand` and defaults to **deny**. Only the following outbound destinations are allowed:

| Destination | Why |
| --- | --- |
| GitHub IP ranges (fetched live from `api.github.com/meta`) | git push/pull, gh CLI |
| `registry.npmjs.org` | npm |
| `api.anthropic.com`, `statsig.anthropic.com`, `statsig.com` | Claude Code runtime |
| `sentry.io` | Claude Code telemetry |
| `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com` | VS Code extensions/updates |
| `p3m.dev`, `cloud.r-project.org`, `cran.r-project.org` | R package installs |
| DNS (UDP 53), SSH (TCP 22), loopback, host subnet | baseline |

Everything else is rejected with `icmp-admin-prohibited`. See https://code.claude.com/docs/en/devcontainer.md for the canonical reference.

### Security caveat

Per Anthropic's own guidance: this devcontainer provides substantial isolation but is not a complete sandbox. A malicious project could still exfiltrate anything accessible inside the container, including Claude Code credentials. **Only use this workflow with trusted repositories.**
