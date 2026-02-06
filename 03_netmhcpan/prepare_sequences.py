#!/usr/bin/env python3
"""
Prepare ProteinMPNN sequences for NetMHCpan binding prediction.

Reads all FASTA files from ProteinMPNN output, skips the first (reference)
sequence from each file, and prepends each of 20 standard amino acids to
every designed peptide. This N-terminal expansion allows NetMHCpan to evaluate
all possible P1 anchor variants for MHC-I binding.

Usage:
    python prepare_sequences.py <mpnn_output_dir> <output_fasta>

Example:
    python prepare_sequences.py ../02_proteinmpnn/outputs_rfd1 ./all_sequences_rfd1.fa
    python prepare_sequences.py ../02_proteinmpnn/outputs_rfd3 ./all_sequences_rfd3.fa
"""

import sys
import os

AA_LIST = list("ACDEFGHIKLMNPQRSTVWY")


def main():
    if len(sys.argv) < 3:
        print("Usage: python prepare_sequences.py <mpnn_output_dir> <output_fasta>")
        sys.exit(1)

    input_root = sys.argv[1]
    out_path = sys.argv[2]

    if not os.path.isdir(input_root):
        print(f"ERROR: Input directory not found: {input_root}")
        sys.exit(1)

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)

    all_seqs = []

    for root, _, files in os.walk(input_root):
        for fname in sorted(files):
            if not fname.endswith(".fa"):
                continue
            in_path = os.path.join(root, fname)

            first_header_seen = False
            drop_next_seq_line = False

            with open(in_path, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue

                    if line.startswith(">"):
                        if not first_header_seen:
                            first_header_seen = True
                            drop_next_seq_line = True
                        continue

                    if drop_next_seq_line:
                        drop_next_seq_line = False
                        continue

                    for aa in AA_LIST:
                        all_seqs.append(aa + line)

    with open(out_path, "w") as out:
        out.write("\n".join(all_seqs) + ("\n" if all_seqs else ""))

    print(f"Prepared {len(all_seqs)} sequences -> {out_path}")


if __name__ == "__main__":
    main()
