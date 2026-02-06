#!/bin/bash
# =============================================================================
# Step 1B: RFdiffusion3 (Foundry) — De novo peptide all-atom generation
# =============================================================================
# Generates 8-mer peptide structures (all-atom) in the MHC groove of
# HLA-A*02:01 TCR-pMHC complex (PDB: 8GOM) using 8 hotspot configurations.
#
# Input:  HLA_A02_8GOM_std_clean.pdb (TCR-pMHC with peptide chain C removed)
#         8gom_peptide_design.json (experiment definitions with hotspots)
# Output: 100 structures per experiment x 8 experiments = 800 total (.cif.gz)
#
# Prerequisites:
#   conda activate RF3
#   Foundry installed: pip install rc-foundry[all]
#   Model weights downloaded: foundry install base-models
#
# Usage:
#   conda activate RF3
#   bash run_rfdiffusion3.sh <experiment>    # Run one experiment
#   bash run_rfdiffusion3.sh all             # Run all 8 experiments
#
# Examples:
#   bash run_rfdiffusion3.sh exp4_MHC+TCR_minimal
#   bash run_rfdiffusion3.sh all
#
# SLURM submission (one GPU per experiment):
#   sbatch --partition=gpu --gpus=1 --mem=32g --time=08:00:00 \
#          --wrap="cd 01_rfdiffusion3 && bash run_rfdiffusion3.sh exp4_MHC+TCR_minimal"
# =============================================================================

set -euo pipefail

# =========================== User Configuration ==============================
# Checkpoint path (optional — omit if using default Foundry checkpoint location)
# CKPT_PATH="~/.foundry/checkpoints/rfd3_latest.ckpt"
# =============================================================================

# --- Fixed Parameters ---
PDB_FILE="../input/HLA_A02_8GOM_std_clean.pdb"
INPUT_JSON="8gom_peptide_design.json"
OUTPUT_DIR="./outputs"
TAG="8GOM"

# Generation: 10 batches x 10 per batch = 100 designs per experiment
N_BATCHES=10
BATCH_SIZE=10

# --- Validate ---
if [ ! -f "$PDB_FILE" ]; then
    echo "ERROR: Input PDB not found: $PDB_FILE"
    echo "Place HLA_A02_8GOM_std_clean.pdb in ../input/"
    exit 1
fi

if [ ! -f "$INPUT_JSON" ]; then
    echo "ERROR: Config JSON not found: $INPUT_JSON"
    exit 1
fi

# Link PDB into working directory (RFD3 resolves paths relative to cwd)
ln -sf "$(cd "$(dirname "$PDB_FILE")" && pwd)/$(basename "$PDB_FILE")" ./HLA_A02_8GOM_std_clean.pdb

mkdir -p "$OUTPUT_DIR"

# =============================================================================
# 8 Experiments defined in 8gom_peptide_design.json
# (same hotspot configurations as 01_rfdiffusion1 for fair benchmarking)
# =============================================================================

declare -a EXP_NAMES=(
    "exp1_MHC_minimal"
    "exp2_MHC_moderate"
    "exp3_MHC_extensive"
    "exp4_MHC+TCR_minimal"
    "exp5_MHC+TCR_balanced"
    "exp6_MHC+TCR_TCR-focused"
    "exp7_MHC+TCR_MHC-focused"
    "exp8_MHC+TCR_overconstrained"
)

# =============================================================================
# Argument parsing: select which experiment(s) to run
# =============================================================================

usage() {
    echo "Usage: bash run_rfdiffusion3.sh <experiment|all>"
    echo ""
    echo "Available experiments:"
    for name in "${EXP_NAMES[@]}"; do echo "  ${name}"; done
    echo "  all  (run all 8 experiments sequentially)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

# Build list of experiment names to run
declare -a RUN_EXPS=()

if [ "$1" == "all" ]; then
    RUN_EXPS=("${EXP_NAMES[@]}")
else
    FOUND=false
    for name in "${EXP_NAMES[@]}"; do
        if [ "${name}" == "$1" ]; then
            RUN_EXPS+=("$name")
            FOUND=true
            break
        fi
    done
    if [ "$FOUND" == false ]; then
        echo "ERROR: Unknown experiment '$1'"
        echo ""
        usage
    fi
fi

# =============================================================================
# Run selected experiments
# =============================================================================

echo "============================================"
echo "RFdiffusion3: 8GOM Peptide All-Atom Design"
echo "============================================"
echo "Input PDB: ${PDB_FILE}"
echo "Config JSON: ${INPUT_JSON}"
echo "Designs per experiment: $(( N_BATCHES * BATCH_SIZE ))"
echo "Experiments to run: ${#RUN_EXPS[@]}"
echo "============================================"
echo ""

for EXP in "${RUN_EXPS[@]}"; do
    echo "--- Running ${EXP} ---"

    TASK_OUTDIR="${OUTPUT_DIR}/${TAG}_${EXP}"
    mkdir -p "${TASK_OUTDIR}"

    # Build rfd3 command
    RFD3_CMD="rfd3 design \
        out_dir=${TASK_OUTDIR} \
        inputs=${INPUT_JSON} \
        json_keys_subset=[\"${EXP}\"] \
        n_batches=${N_BATCHES} \
        diffusion_batch_size=${BATCH_SIZE} \
        skip_existing=True \
        dump_trajectories=False"

    # Add checkpoint path if specified
    if [ -n "${CKPT_PATH:-}" ]; then
        RFD3_CMD="${RFD3_CMD} ckpt_path=${CKPT_PATH}"
    fi

    eval ${RFD3_CMD}

    echo "--- ${EXP} complete ---"
    echo ""
done

echo "============================================"
echo "Done. Output: ${OUTPUT_DIR}/"
echo ""
echo "Note: RFD3 outputs .cif.gz files. Convert to PDB for downstream"
echo "ProteinMPNN with PyMOL: pymol -cq convert_to_pdb.py"
echo "============================================"
