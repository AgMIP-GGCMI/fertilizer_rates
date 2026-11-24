# ============================================================================
# dev_dependencies.R
# ============================================================================
# NEVER RUN. This file exists only so that renv::snapshot() (the project uses
# "snapshot.type": "implicit" in renv/settings.json) records dev-only tools
# that no other R code refers to. In implicit mode renv keeps only packages
# that renv::dependencies() finds in the project's code, so a package used
# solely through a config file or the editor would otherwise be dropped from
# renv.lock.
#
# lintr: used through the .lintr config file and the editor.
# ============================================================================

if (FALSE) {
  library(lintr)
}
