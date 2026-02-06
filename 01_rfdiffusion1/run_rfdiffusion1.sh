#!/bin/bash
# =============================================================================
# Step 1A: RFdiffusion1 — De novo peptide backbone generation
# =============================================================================
# Generates 8-mer peptide backbones in the MHC groove of HLA-A*02:01 TCR-pMHC
# complex (PDB: 8GOM) using 8 hotspot constraint configurations.
#
# Input:  HLA_A02_8GOM_std_clean.pdb (TCR-pMHC with peptide chain C removed)
# Output: 100 backbone PDBs per experiment x 8 experiments = 800 total
#
# Prerequisites:
#   conda activate SE3nv
#   RFdiffusion installed: https://github.com/RosettaCommons/RFdiffusion
#
# Usage:
#   conda activate SE3nv
#   bash run_rfdiffusion1.sh <experiment>    # Run one experiment
#   bash run_rfdiffusion1.sh all             # Run all 8 experiments
#
# Examples:
#   bash run_rfdiffusion1.sh exp4_MHC+TCR_minimal
#   bash run_rfdiffusion1.sh all
#
# SLURM submission (one GPU per experiment):
#   sbatch --partition=gpu --gpus=1 --mem=32g --time=10:00:00 \
#          --wrap="cd 01_rfdiffusion1 && bash run_rfdiffusion1.sh exp4_MHC+TCR_minimal"
# =============================================================================

set -euo pipefail

# =========================== User Configuration ==============================
RFDIFFUSION_PATH="/path/to/RFdiffusion"       # Set your RFdiffusion install path
# =============================================================================

# --- Fixed Parameters ---
PDB_FILE="../input/HLA_A02_8GOM_std_clean.pdb"
OUTPUT_DIR="./outputs"
TAG="8GOM"
NUM_DESIGNS=100

# Contig: Chain A (MHC 1-275), 8-mer peptide, Chain D (TCRa 1-180,183-193),
#         Chain E (TCRb 2-245). Chain D has a gap at residues 181-182.
CONTIGS="[A1-275/0 8-8/0 D1-180/D183-193/0 E2-245]"

# --- Validate ---
if [ ! -f "$PDB_FILE" ]; then
    echo "ERROR: Input PDB not found: $PDB_FILE"
    echo "Place HLA_A02_8GOM_std_clean.pdb in ../input/"
    exit 1
fi

if [ ! -f "${RFDIFFUSION_PATH}/scripts/run_inference.py" ]; then
    echo "ERROR: RFdiffusion not found at: ${RFDIFFUSION_PATH}"
    echo "Set RFDIFFUSION_PATH to your RFdiffusion installation directory."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# =============================================================================
# 8 Experiments: hotspot configurations from 8gom_peptide_design.json
#
# exp1-3: MHC-only hotspots (minimal -> extensive)
# exp4-5: MHC + TCR hotspots (balanced)
# exp6:   TCR-focused hotspots
# exp7:   MHC-focused hotspots
# exp8:   Over-constrained (all hotspots)
#
# MHC hotspots: residues lining the peptide binding groove (Chain A)
# TCRa hotspots: CDR3a loop contacts (Chain D: D95-D99)
# TCRb hotspots: CDR3b loop contacts (Chain E: E99-E103)
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

declare -a EXP_HOTSPOTS=(
    "['A66','A159','A77','A143']"
    "['A66','A159','A7','A99','A77','A143','A116','A123']"
    "['A66','A63','A159','A167','A7','A99','A77','A80','A143','A146','A116','A123']"
    "['A66','A159','A77','A143','D97','D98','E99','E100']"
    "['A66','A159','A7','A99','A77','A143','A116','A123','D96','D97','D98','E99','E100','E101']"
    "['A66','A159','A7','A77','A143','A116','D95','D96','D97','D98','D99','E99','E100','E101','E102','E103']"
    "['A66','A159','A7','A77','A143','A116','D97','D98','E99','E100']"
    "['A66','A63','A159','A167','A7','A99','A77','A80','A143','A146','A116','A123','D95','D96','D97','D98','D99','E99','E100','E101','E102','E103']"
)

# =============================================================================
# Argument parsing: select which experiment(s) to run
# =============================================================================

usage() {
    echo "Usage: bash run_rfdiffusion1.sh <experiment|all>"
    echo ""
    echo "Available experiments:"
    for name in "${EXP_NAMES[@]}"; do echo "  ${name}"; done
    echo "  all  (run all 8 experiments sequentially)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

# Build list of experiment indices to run
declare -a RUN_INDICES=()

if [ "$1" == "all" ]; then
    for i in "${!EXP_NAMES[@]}"; do RUN_INDICES+=("$i"); done
else
    FOUND=false
    for i in "${!EXP_NAMES[@]}"; do
        if [ "${EXP_NAMES[$i]}" == "$1" ]; then
            RUN_INDICES+=("$i")
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
echo "RFdiffusion1: 8GOM Peptide Backbone Design"
echo "============================================"
echo "Input PDB: ${PDB_FILE}"
echo "Designs per experiment: ${NUM_DESIGNS}"
echo "Experiments to run: ${#RUN_INDICES[@]}"
echo "============================================"
echo ""

for i in "${RUN_INDICES[@]}"; do
    EXP="${EXP_NAMES[$i]}"
    HOTSPOTS="${EXP_HOTSPOTS[$i]}"

    echo "--- Running ${EXP} ---"

    python "${RFDIFFUSION_PATH}/scripts/run_inference.py" \
        inference.input_pdb="${PDB_FILE}" \
        inference.output_prefix="${OUTPUT_DIR}/${TAG}_${EXP}" \
        'contigmap.contigs='"${CONTIGS}" \
        "ppi.hotspot_res=${HOTSPOTS}" \
        inference.num_designs=${NUM_DESIGNS}

    echo "--- ${EXP} complete ---"
    echo ""
done

echo "============================================"
echo "Done. Output: ${OUTPUT_DIR}/"
echo "============================================"
