# shellcheck shell=bash
# Generic body of the fertilizer-scaling SLURM array jobs. Sourced (not executed) by a job script, after it has set:
#   SCRIPT_DIR      directory holding the entry script; the job runs from here
#   ENTRY_SCRIPT    file name of the R entry script in SCRIPT_DIR, called with the selected task's arguments
#   EXPECTED_TASKS  number of tasks the job script's list must hold
#   TASKS           array with one string of space-separated entry-script arguments per task
# The task is picked by SLURM_ARRAY_TASK_ID. The sourcing script's `set -e` applies, so a failing Rscript exits before the "Finished" line.

# PIK R/module environment.
source /p/system/modulefiles/defaults/piam/module_load_piam

# Enable nounset after cluster/module init scripts, which may read unset vars.
set -u

if [[ ! -f "$SCRIPT_DIR/$ENTRY_SCRIPT" ]]; then
  echo "ERROR: $ENTRY_SCRIPT not found in working directory: $SCRIPT_DIR"
  exit 4
fi

cd "$SCRIPT_DIR"

TOTAL_TASKS=${#TASKS[@]}
if [[ "$TOTAL_TASKS" -ne "$EXPECTED_TASKS" ]]; then
  echo "ERROR: expected $EXPECTED_TASKS tasks, found $TOTAL_TASKS"
  exit 1
fi

if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  echo "ERROR: This script is intended for sbatch array execution."
  exit 2
fi

if (( SLURM_ARRAY_TASK_ID < 0 || SLURM_ARRAY_TASK_ID >= TOTAL_TASKS )); then
  echo "ERROR: SLURM_ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID out of range 0..$((TOTAL_TASKS - 1))"
  exit 3
fi

TASK="${TASKS[$SLURM_ARRAY_TASK_ID]}"

echo "[$(date -Iseconds)] Job ${SLURM_JOB_ID:-NA}, array task $SLURM_ARRAY_TASK_ID/$((TOTAL_TASKS - 1))"
echo "[$(date -Iseconds)] CWD: $(pwd)"
echo "[$(date -Iseconds)] Script dir: $SCRIPT_DIR"
echo "[$(date -Iseconds)] Submit dir: ${SLURM_SUBMIT_DIR:-NA}"
echo "[$(date -Iseconds)] Running: Rscript --vanilla $ENTRY_SCRIPT $TASK"

# Use module/system library stack on batch nodes; do not auto-activate project renv.
export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE

# TASK is intentionally split into positional CLI args.
# shellcheck disable=SC2086
Rscript --vanilla "$ENTRY_SCRIPT" $TASK

RC=$?
echo "[$(date -Iseconds)] Finished with exit code $RC"
exit $RC
