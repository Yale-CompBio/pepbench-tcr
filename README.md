# pepbench-tcr

**Benchmarking generative scaffold design methods for peptide engineering in TCR–MHC complexes**

This repository provides the computational pipeline for benchmarking de novo peptide design in T-cell receptor (TCR)–peptide–MHC (pMHC) complexes.

We compare **RFdiffusion** (backbone-only) and **RFdiffusion3** (all-atom) for generating peptides that simultaneously satisfy MHC groove constraints and TCR recognition. The pipeline proceeds through four stages: diffusion-based structure generation, sequence inpainting with ProteinMPNN, MHC binding prediction with NetMHCpan, and Rosetta side-chain threading.

<p align="center">
  <img src="docs/workflow.png" alt="Pipeline overview" width="700">
</p>

---

## Pipeline Overview

```
Step 1: Backbone / All-atom Generation
  ├── 01_rfdiffusion1/   RFdiffusion   (backbone-only, SE3nv)
  └── 01_rfdiffusion3/   RFdiffusion3  (all-atom, Foundry/RF3)
          │
          ▼
Step 2: Sequence Design
  └── 02_proteinmpnn/    ProteinMPNN sequence inpainting
          │
          ▼
Step 3: MHC Binding Filter
  └── 03_netmhcpan/      NetMHCpan 4.1 binding prediction
          │
          ▼
Step 4: Structure Refinement
  └── 04_rosetta_thread/  Rosetta SimpleThreadingMover
```

Each step reads from the previous step's `outputs/` directory. All steps use the same input structure (`HLA_A02_8GOM_std_clean.pdb`) for reproducibility.

---

## Repository Structure

```
├── README.md
├── LICENSE
├── input/
│   └── HLA_A02_8GOM_std_clean.pdb        # Input TCR-pMHC (peptide removed)
│
├── 01_rfdiffusion1/                      # Step 1A: RFdiffusion (backbone)
│   └── run_rfdiffusion1.sh
│
├── 01_rfdiffusion3/                      # Step 1B: RFdiffusion3 (all-atom)
│   ├── 8gom_peptide_design.json          #   Hotspot configuration (8 experiments)
│   └── run_rfdiffusion3.sh
│
├── 02_proteinmpnn/                       # Step 2: Sequence inpainting
│   ├── run_proteinmpnn.sh                #   Main script (handles rfd1 and rfd3)
│   └── convert_cif_to_pdb.py             #   RFD3 CIF.GZ → PDB conversion (PyMOL)
│
├── 03_netmhcpan/                         # Step 3: MHC-I binding filter
│   ├── run_netmhcpan.sh                  #   Main script (handles rfd1 and rfd3)
│   ├── prepare_sequences.py              #   Prepend 20 AAs for P1 anchor testing
│   └── filter_binders.py                 #   Filter SB/WB, trim, deduplicate
│
└── 04_rosetta_thread/                    # Step 4: Side-chain threading
    ├── run_rosetta_thread.sh             #   Main script (handles rfd1 and rfd3)
    ├── thread.xml                        #   Rosetta SimpleThreadingMover protocol
    └── prepare_threading.py              #   Map filtered peptides to source PDBs
```

---

## Input Structure

**PDB ID:** [8GOM](https://www.rcsb.org/structure/8GOM) — HLA-A\*02:01 presenting RLQSLQTYV peptide to a TCR

| Chain | Description | Residues |
|-------|-------------|----------|
| A | MHC heavy chain (HLA-A\*02:01) | 1–275 |
| B | Beta-2-microglobulin | 1–99 |
| C | Peptide (RLQSLQTYV) | **Removed for design** |
| D | TCR alpha chain | 1–180, 183–193 (gap at 181–182) |
| E | TCR beta chain | 2–245 |

The input file `HLA_A02_8GOM_std_clean.pdb` has chain C (peptide) removed so the diffusion model generates a de novo peptide backbone in the empty MHC groove.

---

## Prerequisites

Each pipeline step requires its own conda environment:

| Step | Environment | Installation |
|------|-------------|-------------|
| RFdiffusion | `SE3nv` | [RFdiffusion GitHub](https://github.com/RosettaCommons/RFdiffusion) |
| RFdiffusion3 | `RF3` | [RFdiffusion3 GitHub](https://github.com/RosettaCommons/foundry) |
| ProteinMPNN | `mlfold` | [ProteinMPNN GitHub](https://github.com/dauparas/ProteinMPNN) |
| NetMHCpan | system | [NetMHCpan 4.1](https://services.healthtech.dtu.dk/services/NetMHCpan-4.1/) |
| Rosetta | system | [Rosetta GitHub](https://github.com/RosettaCommons/rosetta) |

---

## Quick Start

### Step 1A — RFdiffusion (backbone-only)

```bash
conda activate SE3nv
cd 01_rfdiffusion1/

# Run a single experiment (recommended for job submission)
bash run_rfdiffusion1.sh exp4_MHC+TCR_minimal

# Run all 8 experiments sequentially
bash run_rfdiffusion1.sh all
```

### Step 1B — RFdiffusion3 (all-atom)

```bash
conda activate RF3
cd 01_rfdiffusion3/

# Run a single experiment
bash run_rfdiffusion3.sh exp4_MHC+TCR_minimal

# Run all 8 experiments sequentially
bash run_rfdiffusion3.sh all
```

### Step 2 — ProteinMPNN (sequence inpainting)

```bash
conda activate mlfold
cd 02_proteinmpnn/

bash run_proteinmpnn.sh rfd1    # Process RFdiffusion1 backbones
bash run_proteinmpnn.sh rfd3    # Convert CIF.GZ + process RFdiffusion3
```

### Step 3 — NetMHCpan (MHC-I binding filter)

```bash
cd 03_netmhcpan/

bash run_netmhcpan.sh rfd1      # Filter RFdiffusion1 peptides
bash run_netmhcpan.sh rfd3      # Filter RFdiffusion3 peptides
```

### Step 4 — Rosetta Threading (side-chain packing)

```bash
cd 04_rosetta_thread/

bash run_rosetta_thread.sh rfd1   # Thread onto RFdiffusion1 backbones
bash run_rosetta_thread.sh rfd3   # Thread onto RFdiffusion3 backbones
```

### Submitting to a Job Scheduler (SLURM example)

Each experiment can be submitted independently, enabling parallelism across a cluster:

```bash
# Submit all 8 RFdiffusion1 experiments in parallel
for EXP in exp1_MHC_minimal exp2_MHC_moderate exp3_MHC_extensive \
           exp4_MHC+TCR_minimal exp5_MHC+TCR_balanced \
           exp6_MHC+TCR_TCR-focused exp7_MHC+TCR_MHC-focused \
           exp8_MHC+TCR_overconstrained; do
    sbatch --job-name="rfd1_${EXP}" --partition=gpu --gpus=1 \
           --cpus-per-task=2 --mem=32g --time=10:00:00 \
           --wrap="cd 01_rfdiffusion1 && bash run_rfdiffusion1.sh ${EXP}"
done
```

---

## Experimental Design

We test **8 hotspot configurations** to study how structural constraints affect peptide design quality. All experiments share the same contig specification (8-mer peptide in the MHC groove) and differ only in which residues are designated as hotspots.

| Experiment | MHC Hotspots | TCR&alpha; | TCR&beta; | Description |
|------------|:------------:|:----------:|:---------:|-------------|
| exp1 | 4 | — | — | MHC groove contacts only (minimal) |
| exp2 | 8 | — | — | MHC groove contacts (moderate) |
| exp3 | 12 | — | — | MHC groove contacts (extensive) |
| exp4 | 4 | 2 | 2 | MHC + TCR minimal |
| exp5 | 8 | 3 | 3 | Balanced MHC/TCR |
| exp6 | 6 | 5 | 5 | TCR-focused |
| exp7 | 6 | 2 | 2 | MHC-focused |
| exp8 | 12 | 5 | 5 | Over-constrained |

**Hotspot rationale:**
- **MHC hotspots** (Chain A): residues lining the peptide binding groove — A7, A63, A66, A77, A80, A99, A116, A123, A143, A146, A159, A167
- **TCR&alpha; hotspots** (Chain D): CDR3&alpha; loop residues contacting peptide — D95, D96, D97, D98, D99
- **TCR&beta; hotspots** (Chain E): CDR3&beta; loop residues contacting peptide — E99, E100, E101, E102, E103

---

## Contig Specification

Both RFdiffusion and RFdiffusion3 use the same topology, expressed in their respective dialects:

**RFdiffusion1 (Hydra CLI):**
```
[A1-275/0 8-8/0 D1-180/D183-193/0 E2-245]
```

**RFdiffusion3 (JSON dialect 2):**
```
A1-275,/0,8-8,/0,D1-180,D183-193,/0,E2-245
```

| Segment | Meaning |
|---------|---------|
| `A1-275` | Fix MHC heavy chain from input |
| `/0` | Chain break |
| `8-8` | Design exactly 8 residues (peptide) |
| `D1-180, D183-193` | Fix TCR&alpha; (gap at 181–182) |
| `E2-245` | Fix TCR&beta; |

---

## Output Summary

| Step | Input | Output | Count |
|------|-------|--------|-------|
| RFdiffusion1 | 1 PDB | Backbone PDBs | 100 &times; 8 = 800 |
| RFdiffusion3 | 1 PDB | All-atom CIF.GZ | 100 &times; 8 = 800 |
| ProteinMPNN | 800 PDBs | Peptide sequences | 800 &times; 20 = 16,000 |
| NetMHCpan | 16,000 seqs | Filtered binders | ~500–2,000 |
| Rosetta | Filtered seqs | Threaded PDBs | ~500–2,000 |

---

## Citation

If you find this benchmark helpful for your research, please cite our preprint:

> Xie L, Dam G-B, Patel Y, Denzler L, Shao Y, Wang R, Caron E, Yasumizu Y, Hafler DA, Rodriguez Martinez M. **Benchmarking generative scaffold design methods for peptide engineering in TCR-MHC complexes.** *bioRxiv* (2026). https://www.biorxiv.org/content/10.64898/2026.01.22.701133v1

```bibtex
@article{xie2026benchmarking,
  title={Benchmarking generative scaffold design methods for peptide engineering in TCR-MHC complexes},
  author={Xie, Linhui and Dam, Gia-Bao and Patel, Yashvi and Denzler, Lilian and Shao, Yanjun and Wang, Ruimin and Caron, Etienne and Yasumizu, Yoshiaki and Hafler, David A and Rodriguez Martinez, Maria},
  journal={bioRxiv},
  pages={2026--01},
  year={2026},
  publisher={Cold Spring Harbor Laboratory}
}
```

Please also cite the underlying tools used in this pipeline:

- Watson JL, et al. (2023). De novo design of protein structure and function with RFdiffusion. *Nature*. https://doi.org/10.1038/s41586-023-06415-8
- Krishna R, et al. (2025). De novo design of all-atom biomolecular interactions with RFdiffusion3. *bioRxiv*. https://www.biorxiv.org/content/10.1101/2025.09.18.676967v2
- Dauparas J, et al. (2022). Robust deep learning–based protein sequence design using ProteinMPNN. *Science*. https://doi.org/10.1126/science.add2187
- Reynisson B, et al. (2020). NetMHCpan-4.1 and NetMHCIIpan-4.0. *Nucleic Acids Research*. https://doi.org/10.1093/nar/gkaa379
- Alford RF, et al. (2017). The Rosetta all-atom energy function for macromolecular modeling and design. *J Chem Theory Comput*. https://doi.org/10.1021/acs.jctc.7b00125

---

## License

The pipeline scripts in this repository are licensed under the [MIT License](LICENSE).

This repository does **not** distribute any third-party software. Users are responsible for independently installing and complying with the licenses of each tool used in the pipeline:

| Tool | License |
|------|---------|
| [RFdiffusion](https://github.com/RosettaCommons/RFdiffusion) | BSD-3-Clause |
| [RFdiffusion3 / Foundry](https://github.com/RosettaCommons/foundry) | See repository |
| [ProteinMPNN](https://github.com/dauparas/ProteinMPNN) | MIT |
| [NetMHCpan](https://services.healthtech.dtu.dk/services/NetMHCpan-4.1/) | Academic license |
| [Rosetta](https://github.com/RosettaCommons/rosetta) | Rosetta license (academic/commercial) |
