#!/usr/bin/env python3
"""
Generate Rosetta threading commands from filtered NetMHCpan peptides.

Maps each filtered peptide back to its source RFdiffusion PDB and generates
a rosetta_scripts command that threads the sequence onto the backbone using
SimpleThreadingMover.

Usage:
    python prepare_threading.py <filtered.fa> <pdb_dir> <output_dir>

Example:
    python prepare_threading.py ../03_netmhcpan/rfd1_filtered.fa ../01_rfdiffusion1/outputs ./outputs_rfd1
    python prepare_threading.py ../03_netmhcpan/rfd3_filtered.fa ../02_proteinmpnn/inputs_rfd3 ./outputs_rfd3
"""

import sys
import os
from collections import defaultdict


def header_to_pdb_stem(header: str) -> str:
    """Extract PDB stem from filtered FASTA header.

    Header format: experiment_name__T=0.1, sample=20, ...
    PDB stem: everything before '__' (and before ',')
    """
    before_comma = header.split(",", 1)[0]
    stem = before_comma.split("__", 1)[0]
    return stem


def main():
    if len(sys.argv) < 4:
        print("Usage: python prepare_threading.py <filtered.fa> <pdb_dir> <output_dir>")
        sys.exit(1)

    fasta_path = sys.argv[1]
    pdb_dir = sys.argv[2]
    output_dir = sys.argv[3]

    if not os.path.isfile(fasta_path):
        print(f"ERROR: Filtered FASTA not found: {fasta_path}")
        sys.exit(1)

    if not os.path.isdir(pdb_dir):
        print(f"ERROR: PDB directory not found: {pdb_dir}")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    # Track local index per PDB (multiple peptides may map to same backbone)
    per_pdb_count = defaultdict(int)
    n_commands = 0
    missing = []
    commands = []

    with open(fasta_path, "r") as fin:
        header = None
        for line in fin:
            line = line.strip()
            if not line:
                continue

            if line.startswith(">"):
                header = line[1:]
                continue

            seq = line
            if header is None:
                raise RuntimeError("FASTA format error: sequence before header")

            pdb_stem = header_to_pdb_stem(header)
            pdb_path = os.path.join(pdb_dir, pdb_stem + ".pdb")

            if not os.path.isfile(pdb_path):
                missing.append(pdb_stem)
                continue

            per_pdb_count[pdb_stem] += 1
            local_idx = per_pdb_count[pdb_stem]

            prefix = os.path.join(output_dir, f"threaded_{local_idx}_")

            cmd = (
                f"rosetta_scripts -in:file:s {pdb_path} "
                f"-parser:protocol thread.xml "
                f"-parser:script_vars sequence={seq} "
                f"-out:prefix {prefix}"
            )
            commands.append(cmd)
            n_commands += 1

    # Write command file
    cmd_file = os.path.join(output_dir, "threading_commands.txt")
    with open(cmd_file, "w") as fout:
        fout.write("\n".join(commands) + "\n")

    print(f"Generated {n_commands} threading commands -> {cmd_file}")
    print(f"Unique PDB backbones: {len(per_pdb_count)}")

    if missing:
        unique_missing = set(missing)
        print(f"WARNING: {len(unique_missing)} PDB stems not found (skipped).")
        for p in sorted(unique_missing)[:10]:
            print(f"  {p}")


if __name__ == "__main__":
    main()
