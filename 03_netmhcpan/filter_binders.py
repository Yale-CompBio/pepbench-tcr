#!/usr/bin/env python3
"""
Filter NetMHCpan results for strong/weak binders and map back to MPNN sources.

Parses NetMHCpan output, extracts peptides predicted as Strong Binders (SB)
or Weak Binders (WB), trims the prepended N-terminal amino acid (added by
prepare_sequences.py), deduplicates, and writes a FASTA with provenance headers.

Usage:
    python filter_binders.py <netmhcpan_result> <mpnn_output_dir> <output_fasta>

Example:
    python filter_binders.py ./rfd1_netmhcpan_result.txt ../02_proteinmpnn/outputs_rfd1 ./rfd1_filtered.fa
    python filter_binders.py ./rfd3_netmhcpan_result.txt ../02_proteinmpnn/outputs_rfd3 ./rfd3_filtered.fa
"""

import sys
import os
import re
from pathlib import Path


def get_experiment_name(path: Path) -> str:
    """Extract experiment name from MPNN output directory structure."""
    parts = path.parts
    if "seqs" in parts:
        idx = parts.index("seqs")
        if idx > 0:
            return parts[idx - 1]
    return path.parent.name


def main():
    if len(sys.argv) < 4:
        print("Usage: python filter_binders.py <netmhcpan_result> <mpnn_output_dir> <output_fasta>")
        sys.exit(1)

    netmhc_file = sys.argv[1]
    mpnn_dir = sys.argv[2]
    out_fasta = sys.argv[3]

    # Step 1: Index original MPNN peptides -> headers
    peptide_to_header = {}
    total_files, total_entries = 0, 0

    for root, _, files in os.walk(mpnn_dir):
        for f in sorted(files):
            if not f.lower().endswith(".fa"):
                continue
            total_files += 1
            fpath = Path(root) / f
            exp_name = get_experiment_name(fpath)

            with open(fpath, "r", encoding="utf-8", errors="ignore") as fh:
                header = None
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith(">"):
                        header = line[1:]
                        continue
                    seq = line.upper()
                    if seq and header:
                        peptide_to_header[seq] = f"{exp_name}__{header}"
                        total_entries += 1

    print(f"[INDEX] {total_files} FASTA files, {total_entries} entries, "
          f"{len(peptide_to_header)} unique peptides")

    # Step 2: Parse NetMHCpan results — filter SB/WB, trim N-terminal AA
    sbwb_trimmed = set()
    too_short = 0

    with open(netmhc_file, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "<= SB" in line or "<= WB" in line:
                parts = re.split(r"\s+", line.strip())
                if len(parts) >= 3:
                    pep_full = parts[2].upper()
                    if len(pep_full) < 2:
                        too_short += 1
                        continue
                    pep_orig = pep_full[1:]  # trim prepended AA
                    if pep_orig:
                        sbwb_trimmed.add(pep_orig)

    print(f"[FILTER] {len(sbwb_trimmed)} unique SB/WB peptides after trimming")

    # Step 3: Write deduplicated FASTA with provenance headers
    unmapped = 0
    os.makedirs(os.path.dirname(out_fasta) or ".", exist_ok=True)

    with open(out_fasta, "w") as out:
        count = 0
        for pep in sorted(sbwb_trimmed):
            hdr = peptide_to_header.get(pep)
            if hdr is None:
                hdr = f"unmapped__{pep}"
                unmapped += 1
            out.write(f">{hdr}\n{pep}\n")
            count += 1

    print(f"[OUTPUT] {count} peptides -> {out_fasta} ({unmapped} unmapped)")


if __name__ == "__main__":
    main()
