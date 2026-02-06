#!/bin/bash
# =============================================================================
# Step 3: NetMHCpan — MHC-I binding prediction and filtering
# =============================================================================
# Predicts peptide-MHC binding affinity using NetMHCpan 4.1 and filters for
# Strong Binders (SB) and Weak Binders (WB) against HLA-A*02:01.
#
# Workflow:
#   1. Prepare sequences: prepend 20 amino acids to each MPNN peptide
#   2. Run NetMHCpan prediction
#   3. Filter for SB/WB, trim prepended AA, deduplicate
#
# Input:  ProteinMPNN FASTA outputs from Step 2
# Output: Filtered FASTA of MHC-binding peptides
#
# Prerequisites:
#   NetMHCpan 4.1 installed and in PATH
#   Python 3.8+
#
# Usage:
#   bash run_netmhcpan.sh <rfd1|rfd3>
#
# Examples:
#   bash run_netmhcpan.sh rfd1
#   bash run_netmhcpan.sh rfd3
# =============================================================================

set -euo pipefail

# =========================== User Configuration ==============================
ALLELE="HLA-A02:01"      # MHC-I allele for 8GOM
# =============================================================================

# =============================================================================
# Argument parsing
# =============================================================================

usage() {
    echo "Usage: bash run_netmhcpan.sh <rfd1|rfd3>"
    echo ""
    echo "  rfd1   Filter peptides from RFdiffusion1 + ProteinMPNN pipeline"
    echo "  rfd3   Filter peptides from RFdiffusion3 + ProteinMPNN pipeline"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

SOURCE="$1"

case "$SOURCE" in
    rfd1)
        MPNN_DIR="../02_proteinmpnn/outputs_rfd1"
        ALL_SEQ="./all_sequences_rfd1.fa"
        NETMHC_RESULT="./rfd1_netmhcpan_result.txt"
        FILTERED_FA="./rfd1_filtered.fa"
        ;;
    rfd3)
        MPNN_DIR="../02_proteinmpnn/outputs_rfd3"
        ALL_SEQ="./all_sequences_rfd3.fa"
        NETMHC_RESULT="./rfd3_netmhcpan_result.txt"
        FILTERED_FA="./rfd3_filtered.fa"
        ;;
    *)
        echo "ERROR: Unknown source '$SOURCE'"
        echo ""
        usage
        ;;
esac

# --- Validate ---
if [ ! -d "$MPNN_DIR" ]; then
    echo "ERROR: ProteinMPNN output not found: $MPNN_DIR"
    echo "Run 02_proteinmpnn/run_proteinmpnn.sh ${SOURCE} first."
    exit 1
fi

if ! command -v netMHCpan &> /dev/null; then
    echo "ERROR: netMHCpan not found in PATH."
    echo "Install NetMHCpan 4.1: https://services.healthtech.dtu.dk/services/NetMHCpan-4.1/"
    exit 1
fi

# =============================================================================
# Step 1: Prepare sequences (prepend 20 AAs for P1 anchor testing)
# =============================================================================

echo "============================================"
echo "NetMHCpan: ${SOURCE} Pipeline"
echo "============================================"
echo "Allele: ${ALLELE}"
echo "MPNN input: ${MPNN_DIR}"
echo "============================================"
echo ""

echo "--- Step 1: Preparing sequences ---"
python prepare_sequences.py "$MPNN_DIR" "$ALL_SEQ"
echo ""

# =============================================================================
# Step 2: Run NetMHCpan prediction
# =============================================================================

echo "--- Step 2: Running NetMHCpan ---"
echo "Input: ${ALL_SEQ}"
echo "Allele: ${ALLELE}"

netMHCpan -p "$ALL_SEQ" -a "$ALLELE" > "$NETMHC_RESULT"

echo "Result: ${NETMHC_RESULT}"
echo ""

# =============================================================================
# Step 3: Filter SB/WB binders, trim, deduplicate
# =============================================================================

echo "--- Step 3: Filtering binders ---"
python filter_binders.py "$NETMHC_RESULT" "$MPNN_DIR" "$FILTERED_FA"
echo ""

echo "============================================"
echo "Done. Filtered peptides: ${FILTERED_FA}"
echo "============================================"
