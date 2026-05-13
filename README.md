# christoph_fert_scripts

R scripts for fertilizer-scaling climate/agricultural modeling.

This repo ships a `.devcontainer` that runs Claude Code inside a firewalled sandbox with R 4.5 and the repo's pinned dependencies pre-installed. The Superpowers Claude Code plugin is pre-configured at the project scope so it loads automatically the first time you trust the folder.

## Prerequisites

- **Podman**: `brew install podman && podman machine init && podman machine start`
- **VS Code** with the **Dev Containers** extension
- An **Anthropic** account (for first-run `claude` authentication)

On first install only, tell VS Code's Dev Containers extension to use podman instead of docker. Open User Settings (JSON) and add:

```json
"dev.containers.dockerPath": "podman"
```

The podman VM must be running (`podman machine start`) whenever you open the container.

## Opening the container

```bash
code .
```

Then: Command Palette → **"Dev Containers: Reopen in Container"**.

First build takes several minutes (R package compilation). Subsequent opens are fast thanks to image caching. The container's firewall activates automatically via the `postStartCommand` and verifies itself by confirming `https://example.com` is unreachable while `https://api.github.com` is.

## First-run inside the container

Open the integrated terminal (``Ctrl+` ``) and run:

```bash
claude
```

- Complete the first-run device-code authentication.
- Accept the folder-trust prompt for `/workspace`.
- Accept the "Install superpowers from claude-plugins-official?" prompt.

Verify with `/plugin` — the Installed tab should list `superpowers@claude-plugins-official` as enabled, and `/superpowers:` tab-completion should expose Superpowers' namespaced skills.

Authentication and the installed plugin persist across restarts via the `claude-code-config-${devcontainerId}` volume; you don't need to re-authenticate on every rebuild.

## Testing

Run the full test suite (unit tests + PNG regression tests):

    Rscript tests/testthat.R

The PNG regression tests render diagnostic plots for two reference
scenarios (`mai histsoc` and `mai ssp126 image gfdl-esm4`) and compare
them byte-for-byte against committed baseline PNGs. Each scenario
takes ~30–40 seconds, so the full suite takes a few minutes.

To skip the slow tests during rapid iteration:

    Rscript tests/testthat-fast.R

### When a PNG snapshot fails

testthat writes the mismatched render to
`tests/testthat-slow/_snaps/plot_diagnostics_regression/<name>.new.png`
alongside the baseline. To review in R:

    > testthat::snapshot_review("plot_diagnostics_regression")

If the change is intentional, accept the new baseline:

    Rscript tools/accept_diagnostics_baseline.R

Then commit the updated snapshot files alongside the code change that
produced them.

### Environment caveat

Byte-identical PNG output is guaranteed only inside this repo's
devcontainer (`rocker/r-ver:4.5.0` base image + pinned apt cairo/png
libs + `renv`-locked R packages). Runs outside the container may
produce legitimate pixel differences and will need fresh baselines
captured in the devcontainer environment.

### Coverage

Generate a line-coverage report for `fertilizer_scaling_functions.R`:

    Rscript tests/coverage.R

The script instruments the source file with `covr` and runs both the
fast and slow test suites against it. The slow PNG-regression tests
are required to cover `main()`, `plot_diagnostics()`, and
`compare_relative_lambda()` — they are exercised end-to-end rather
than unit-tested — so the run takes a few minutes.

Pass an optional threshold percentage to fail the run when coverage
drops below it (intended for CI):

    Rscript tests/coverage.R 90

A companion fast-only report measures the support library files
(`fertilizer_scaling_settings.R`,
`fertilizer_scaling_plot_diagnostics_functions.R`,
`tools/diagnostics_png_harness.R`) using just the fast suite — it runs
in seconds and is forward-looking scaffolding for future unit tests of
those helpers (today's number is 0% because no fast tests exercise
them):

    Rscript tests/coverage_fast.R

## Running the R scripts

```bash
Rscript fertilizer_scaling.R
```

R packages (`ncdf4`, `testthat`, `fields`, `abind`, `MASS`, `lintr`) are baked into the image and resolved via `RENV_CONFIG_EXTERNAL_LIBRARIES`, so the repo's `.Rprofile` (which activates renv) still finds them. `renv.lock` is the authoritative dependency manifest; to install a new package, run `install.packages("pkg")` inside the container and — if you want the lockfile to reflect it — then `renv::snapshot()` and commit `renv.lock`.

## What the firewall allows

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

## Rebuilding

If you change the `Dockerfile`, the firewall script, or `devcontainer.json`: Command Palette → **"Dev Containers: Rebuild Container"**. Claude auth persists across rebuilds because the `/home/node/.claude` volume is keyed to the devcontainer ID, not the image.

## Security caveat

Per Anthropic's own guidance: this devcontainer provides substantial isolation but is not a complete sandbox. A malicious project could still exfiltrate anything accessible inside the container, including Claude Code credentials. **Only use this workflow with trusted repositories.**
