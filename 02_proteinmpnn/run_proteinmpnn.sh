#!/bin/bash
# =============================================================================
# Step 2: ProteinMPNN — Sequence inpainting for designed peptide backbones
# =============================================================================
# Designs amino acid sequences for the peptide chain (chain B) of each
# RFdiffusion-generated backbone, keeping MHC/TCR chains fixed.
#
# Input:  PDB files from Step 1 (01_rfdiffusion1 or 01_rfdiffusion3)
# Output: 20 designed sequences per backbone (.fa FASTA files)
#
# Prerequisites:
#   conda activate mlfold
#   ProteinMPNN installed: https://github.com/dauparas/ProteinMPNN
#
# Usage:
#   conda activate mlfold
#   bash run_proteinmpnn.sh <rfd1|rfd3>
#
# Examples:
#   bash run_proteinmpnn.sh rfd1    # Process RFdiffusion1 PDB outputs
#   bash run_proteinmpnn.sh rfd3    # Convert CIF.GZ then process RFdiffusion3
#
# SLURM submission:
#   sbatch --partition=gpu --gpus=1 --mem=16g --time=04:00:00 \
#          --wrap="cd 02_proteinmpnn && bash run_proteinmpnn.sh rfd1"
# =============================================================================

set -euo pipefail

# =========================== User Configuration ==============================
PROTEINMPNN_PATH="/path/to/ProteinMPNN"       # Set your ProteinMPNN install path
# =============================================================================

# --- Fixed Parameters ---
DESIGN_CHAIN="B"          # Chain B = designed peptide
NUM_SEQ=20                # Sequences per backbone
SAMPLING_TEMP=0.1         # Low temperature for high-confidence sequences
SEED=3407                 # Reproducibility

# =============================================================================
# Argument parsing
# =============================================================================

usage() {
    echo "Usage: bash run_proteinmpnn.sh <rfd1|rfd3>"
    echo ""
    echo "  rfd1   Process RFdiffusion1 outputs (PDB files)"
    echo "  rfd3   Process RFdiffusion3 outputs (CIF.GZ -> PDB conversion, then MPNN)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

SOURCE="$1"

case "$SOURCE" in
    rfd1)
        INPUT_DIR="../01_rfdiffusion1/outputs"
        OUTPUT_DIR="./outputs_rfd1"
        ;;
    rfd3)
        INPUT_DIR="./inputs_rfd3"       # Converted PDBs (created below)
        OUTPUT_DIR="./outputs_rfd3"
        RFD3_RAW_DIR="../01_rfdiffusion3/outputs"
        ;;
    *)
        echo "ERROR: Unknown source '$SOURCE'"
        echo ""
        usage
        ;;
esac

# --- Validate ProteinMPNN ---
if [ ! -f "${PROTEINMPNN_PATH}/protein_mpnn_run.py" ]; then
    echo "ERROR: ProteinMPNN not found at: ${PROTEINMPNN_PATH}"
    echo "Set PROTEINMPNN_PATH to your ProteinMPNN installation directory."
    exit 1
fi

# =============================================================================
# RFD3 only: Convert CIF.GZ to PDB using PyMOL
# =============================================================================

if [ "$SOURCE" == "rfd3" ]; then
    if [ ! -d "$RFD3_RAW_DIR" ]; then
        echo "ERROR: RFdiffusion3 output directory not found: $RFD3_RAW_DIR"
        echo "Run 01_rfdiffusion3/run_rfdiffusion3.sh first."
        exit 1
    fi

    echo "============================================"
    echo "Converting RFD3 CIF.GZ to PDB (PyMOL)..."
    echo "============================================"

    pymol -cq convert_cif_to_pdb.py -- "$RFD3_RAW_DIR" "$INPUT_DIR"

    echo ""
fi

# =============================================================================
# Run ProteinMPNN on all PDB files
# =============================================================================

if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: Input directory not found: $INPUT_DIR"
    echo "Run the corresponding RFdiffusion step first."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Collect all PDB files
PDB_FILES=( $(find "$INPUT_DIR" -name "*.pdb" -type f | sort) )

if [ ${#PDB_FILES[@]} -eq 0 ]; then
    echo "ERROR: No PDB files found in $INPUT_DIR"
    exit 1
fi

echo "============================================"
echo "ProteinMPNN: Sequence Inpainting"
echo "============================================"
echo "Source: ${SOURCE}"
echo "Input PDBs: ${#PDB_FILES[@]}"
echo "Design chain: ${DESIGN_CHAIN}"
echo "Sequences per backbone: ${NUM_SEQ}"
echo "Sampling temperature: ${SAMPLING_TEMP}"
echo "Output: ${OUTPUT_DIR}/"
echo "============================================"
echo ""

TOTAL=${#PDB_FILES[@]}
COUNT=0

for PDB in "${PDB_FILES[@]}"; do
    COUNT=$(( COUNT + 1 ))
    BASENAME=$(basename "$PDB" .pdb)
    OUT_FOLDER="${OUTPUT_DIR}/${BASENAME}"

    # Skip if already completed
    if [ -d "$OUT_FOLDER" ] && [ "$(find "$OUT_FOLDER" -name '*.fa' 2>/dev/null | head -1)" ]; then
        echo "[${COUNT}/${TOTAL}] Skip (exists): ${BASENAME}"
        continue
    fi

    echo "[${COUNT}/${TOTAL}] Designing: ${BASENAME}"

    python "${PROTEINMPNN_PATH}/protein_mpnn_run.py" \
        --pdb_path "$PDB" \
        --pdb_path_chains "$DESIGN_CHAIN" \
        --out_folder "$OUT_FOLDER" \
        --num_seq_per_target "$NUM_SEQ" \
        --sampling_temp "$SAMPLING_TEMP" \
        --seed "$SEED"
done

echo ""
echo "============================================"
echo "Done. Output: ${OUTPUT_DIR}/"
echo "Total PDBs processed: ${TOTAL}"
echo "Sequences generated: $(( TOTAL * NUM_SEQ ))"
echo "============================================"
