#!/bin/bash
# =============================================================================
# Step 4: Rosetta Threading — Side-chain packing of designed peptides
# =============================================================================
# Threads NetMHCpan-filtered peptide sequences onto their source RFdiffusion
# backbones using Rosetta SimpleThreadingMover.
# No backbone changes — only side-chain packing within 8A of the peptide.
#
# Input:  Filtered FASTA from Step 3 + source PDBs from Step 1
# Output: Threaded PDB structures with packed side chains
#
# Prerequisites:
#   rosetta_scripts in PATH (Rosetta Software Suite)
#
# Usage:
#   bash run_rosetta_thread.sh <rfd1|rfd3>
#
# Examples:
#   bash run_rosetta_thread.sh rfd1
#   bash run_rosetta_thread.sh rfd3
#
# SLURM submission:
#   sbatch --partition=day --cpus-per-task=1 --mem=8g --time=02:00:00 \
#          --wrap="cd 04_rosetta_thread && bash run_rosetta_thread.sh rfd1"
# =============================================================================

set -euo pipefail

# =============================================================================
# Argument parsing
# =============================================================================

usage() {
    echo "Usage: bash run_rosetta_thread.sh <rfd1|rfd3>"
    echo ""
    echo "  rfd1   Thread peptides onto RFdiffusion1 backbones"
    echo "  rfd3   Thread peptides onto RFdiffusion3 backbones (converted PDBs)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

SOURCE="$1"

case "$SOURCE" in
    rfd1)
        FILTERED_FA="../03_netmhcpan/rfd1_filtered.fa"
        PDB_DIR="../01_rfdiffusion1/outputs"
        OUTPUT_DIR="./outputs_rfd1"
        ;;
    rfd3)
        FILTERED_FA="../03_netmhcpan/rfd3_filtered.fa"
        PDB_DIR="../02_proteinmpnn/inputs_rfd3"
        OUTPUT_DIR="./outputs_rfd3"
        ;;
    *)
        echo "ERROR: Unknown source '$SOURCE'"
        echo ""
        usage
        ;;
esac

# --- Validate ---
if [ ! -f "$FILTERED_FA" ]; then
    echo "ERROR: Filtered FASTA not found: $FILTERED_FA"
    echo "Run 03_netmhcpan/run_netmhcpan.sh ${SOURCE} first."
    exit 1
fi

if [ ! -d "$PDB_DIR" ]; then
    echo "ERROR: PDB directory not found: $PDB_DIR"
    echo "Run the RFdiffusion step first."
    exit 1
fi

if ! command -v rosetta_scripts &> /dev/null; then
    echo "ERROR: rosetta_scripts not found in PATH."
    echo "Install Rosetta: https://github.com/RosettaCommons/rosetta"
    exit 1
fi

if [ ! -f "thread.xml" ]; then
    echo "ERROR: thread.xml not found in current directory."
    exit 1
fi

# =============================================================================
# Step 1: Generate threading commands
# =============================================================================

echo "============================================"
echo "Rosetta Threading: ${SOURCE} Pipeline"
echo "============================================"
echo "Filtered FASTA: ${FILTERED_FA}"
echo "PDB directory: ${PDB_DIR}"
echo "Output: ${OUTPUT_DIR}/"
echo "============================================"
echo ""

echo "--- Generating threading commands ---"
python prepare_threading.py "$FILTERED_FA" "$PDB_DIR" "$OUTPUT_DIR"
echo ""

CMD_FILE="${OUTPUT_DIR}/threading_commands.txt"

if [ ! -f "$CMD_FILE" ]; then
    echo "ERROR: No commands generated."
    exit 1
fi

TOTAL=$(wc -l < "$CMD_FILE" | tr -d ' ')

echo "--- Running ${TOTAL} threading commands ---"
echo ""

# =============================================================================
# Step 2: Execute threading commands
# =============================================================================

COUNT=0
while IFS= read -r CMD; do
    [ -z "$CMD" ] && continue
    COUNT=$(( COUNT + 1 ))
    echo "[${COUNT}/${TOTAL}] ${CMD}"
    eval "$CMD"
done < "$CMD_FILE"

echo ""
echo "============================================"
echo "Done. Threaded structures: ${OUTPUT_DIR}/"
echo "Total commands executed: ${COUNT}"
echo "============================================"
