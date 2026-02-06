#!/usr/bin/env python3
"""
Convert RFdiffusion3 CIF.GZ outputs to PDB format for ProteinMPNN.

RFdiffusion3 (Foundry) outputs .cif.gz files. ProteinMPNN requires .pdb input.
This script uses PyMOL to batch-convert all CIF.GZ files to PDB.

Usage:
    pymol -cq convert_cif_to_pdb.py -- <input_dir> <output_dir>

Example:
    pymol -cq convert_cif_to_pdb.py -- ../01_rfdiffusion3/outputs ./inputs_rfd3
"""

import sys
import os
from pathlib import Path
from pymol import cmd

# --- Parse arguments (after '--' in pymol -cq script.py -- args) ---
argv = sys.argv[1:]
if len(argv) < 2:
    print("Usage: pymol -cq convert_cif_to_pdb.py -- <input_dir> <output_dir>")
    sys.exit(1)

IN_DIR = Path(argv[0])
OUT_DIR = Path(argv[1])
OUT_DIR.mkdir(parents=True, exist_ok=True)

if not IN_DIR.exists():
    print(f"ERROR: Input directory not found: {IN_DIR}")
    sys.exit(1)

# --- Convert all CIF.GZ files ---
cif_files = sorted(IN_DIR.rglob("*.cif.gz"))
print(f"Found {len(cif_files)} CIF.GZ files in {IN_DIR}")

converted = 0
skipped = 0
failed = 0

for cif_path in cif_files:
    # Output PDB: flatten directory structure, replace extension
    stem = cif_path.name.replace(".cif.gz", "")
    # Include parent folder name if nested (e.g., task subdirectories)
    if cif_path.parent != IN_DIR:
        parent_name = cif_path.parent.name
        out_name = f"{stem}_{parent_name}.pdb"
    else:
        out_name = f"{stem}.pdb"

    out_pdb = OUT_DIR / out_name

    if out_pdb.exists() and out_pdb.stat().st_size > 0:
        skipped += 1
        continue

    obj_name = f"obj_{converted}"
    try:
        cmd.load(str(cif_path), obj_name)
        cmd.save(str(out_pdb), obj_name)
        cmd.delete(obj_name)
        converted += 1
    except Exception as e:
        print(f"[FAIL] {cif_path}: {e}")
        failed += 1

print(f"\nConversion complete: {converted} converted, {skipped} skipped, {failed} failed")
print(f"Output: {OUT_DIR}")
