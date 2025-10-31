# Songbird diet metabarcoding: COI classifier (ANML) and diet metabarcoding pipeline

Build and apply a QIIME 2–compatible COI classifier for songbird diet metabarcoding using ANML primers. This repository provides modular shell scripts for: downloading COI references, importing and merging with CRABS, in silico PCR for ANML, dereplication and filtering, subsetting to project taxa, exporting QIIME 2 formats, training a Naive Bayes (QIIME 2 feature-classifier) model, and evaluating outputs.

The diet analysis workflow relies on QIIME 2 (2024.10) and R for `decontam` and posthoc analyses. Scripts live in `2_diet_analysis/` and are intended to be run in order, checking `.qzv` visualizations along the way.

**Please site this repo if you use it! :)**

## Repository structure

```text
sparrow-diet-metabarcoding/
├── 1_build_classifier/
│   ├── 00_setup.sh                    # create CRABS env,
│   ├── 01_download_COI.sh             # CRABS downloads from BOLD, NCBI, MIDORI
│   ├── 02_merge.sh                    # CRABS import; merge + dedup
│   ├── 03_in_silico_pcr.sh            # ANML in-silico PCR
│   ├── 04_global_alignment.sh         # recover amplicons; length QC
│   ├── 05_database_filtering.sh       # dereplicate + filter
│   ├── 06.1_database_subsetting.sh    # subset database to target taxa
│   ├── 06.2_gbif_subsetting.sh        # GBIF-based subsetting (R helper)
│   ├── 07.1_export.sh                 # export QIIME 2 sequences/taxonomy
│   ├── 07.2_clean_db.sh               # taxonomy cleanup
│   ├── 08_train_nb_classifier.sh      # train Naive Bayes classifier (QIIME 2)
│   └── helper_scripts/
│       ├── 06_helper_count_pests.sh   # presence/absence of priority pests in DB
│       ├── gbif_filter_regions.R      # GBIF geographic filters
│       └── gbif_filter_guide.md       # notes for region filtering
├── 2_diet_analysis/
│   ├── 00_demux.sh                    # import/demultiplex per-plate reads
│   ├── 01_cutadapt.sh                 # primer trimming
│   ├── 02_dada2.sh                    # denoise paired reads
│   ├── 03_merge.sh                    # merge tables/rep-seqs/metadata across years/plates (optional)
│   ├── 04.1_classify.sh               # classify rep-seqs with trained classifier
│   ├── 04.2_evaluate_classifier.sh    # evaluate classifier on mock community (optional)
│   ├── 04.3_confusion_matrix.sh       # build confusion matrices from eval (optional)
│   ├── 05.1_decontam_prevalence.R     # identify contaminants (R)
│   ├── 05.2_filter_contaminants.sh    # remove contaminants per plate/batch
│   ├── 06_qc_and_get_analysis_files.sh# QC plots; analysis-only tables
│   ├── 07_posthoc_analyses.R          # alpha/beta; FOO/RRA; pest summaries (R)
│   ├── merge_taxonomy.R               # helper for taxonomy merge (R)
│   └── merge_metadata.R               # helper for metadata merge (R)
└── README.md
```

## Dependencies & install

Required software:

- QIIME 2: `qiime2-amplicon-2024.10` (activates via `source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10` on Cornell BioHPC)
- CRABS: `>=1.8,<2.0` (banner shows v1.9.0 during help)
- cutadapt: `4.4` (required by CRABS in-silico PCR path)
- xopen: `<2.0` (workaround for known build issue)
- VSEARCH: `2.16.0` (used by CRABS pairwise alignment)
- BLAST+ makeblastdb: `2.10.1+` (listed as external dependency)
- GNU parallel, awk; optional R (base) for comparisons

Create and populate CRABS environment (Conda/Mamba):

```bash
conda create -y -n CRABS python=3.10
conda activate CRABS
conda config --env --set solver classic
conda config --env --set channel_priority strict
conda install -y -c conda-forge -c bioconda \
  python=3.10 \
  "xopen<2.0" \
  "cutadapt>=4.3,<5.0" \
  "biopython>=1.80" \
  "crabs>=1.8,<2.0"

# verify
export PATH="$CONDA_PREFIX/bin:$PATH" && hash -r
type -a crabs
crabs --help | head
```

QIIME 2 activation (Cornell BioHPC example):

```bash
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10
qiime --help | head
```

## Diet analysis pipeline (QIIME 2 + R)

### Expected inputs
- Per-plate QIIME 2 artifacts: `table_<plate>.qza`, `rep-seqs_<plate>.qza`, and `taxonomy_<plate>.qza` (after classification).
- Per-plate metadata TSVs with at least: `SampleID` (or `#SampleID`), `Species` (used for control detection), `Year`, `Site`, `Plate`.
- Negative controls labeled in `Species` as one of: `EBLANK`, `PBLANK`, `BLANK`, `EMPTY`; positive controls labeled `POS`.

### Run order
1. 00_demux.sh
   - Import/demultiplex reads per plate; review demux stats.
2. 01_cutadapt.sh
   - Primer trimming on demultiplexed reads; review `trim_*.qzv`.
3. 02_dada2.sh
   - Denoise paired-end reads; review `denoise_*.qzv` and `table_*.qzv`.
4. 03_merge.sh 
   - Merge per-batch(year) tables/rep-seqs and metadata into `*_merged.qza/qzv`.
5. 04.1_classify.sh
   - Classify representative sequences with your trained classifier; review taxa barplots.
6. 04.2_evaluate_classifier.sh
   - Evaluate the classifier on a mock community; produces `eval_*.qzv`.
7. 04.3_confusion_matrix.sh
   - Build confusion matrices and per-species precision/recall tables from eval.


## Build classifier pipeline (Naive Bayes)

Scripts in `1_build_classifier/` train and evaluate a QIIME 2 Naive Bayes classifier tailored to the ANML COI amplicon.

1. 00_setup.sh
   - Create CRABS environment and ensure QIIME 2 is available.
2. 01_download_COI.sh
   - Download raw COI references from BOLD/NCBI/MIDORI via CRABS.
3. 02_merge.sh
   - Import, merge, and deduplicate references.
4. 03_in_silico_pcr.sh
   - In-silico PCR with ANML primers to isolate the target amplicon region.
5. 04_global_alignment.sh
   - Global alignment (VSEARCH) for length QC and amplicon validation.
6. 05_database_filtering.sh
   - Dereplicate to unique species; quality and length filters.
7. 06.1_database_subsetting.sh / 06.2_gbif_subsetting.sh
   - Optional biological/geographic subsetting to project-relevant taxa.
8. 07.1_export.sh and 07.2_clean_db.sh
   - Export QIIME 2 `FeatureData[Sequence]` and `FeatureData[Taxonomy]`; optional taxonomy cleanup.
9. 08_train_nb_classifier.sh
   - Train Naive Bayes classifier (QIIME 2 `feature-classifier classify-sklearn` compatible); ensure primer-trimmed amplicon sequences and matching taxonomy are used.

Notes:
- Ensure the training sequences match the exact ANML amplicon region used for classification (primer-trimmed, consistent orientation).
- Prefer species-level dereplication for cleaner NB training; retain lineage strings with consistent rank prefixes.

## Citations

- QIIME 2: Bolyen E, Rideout JR, et al. (2019) Nature Biotechnology 37, 852–857. [Project page](https://qiime2.org)
- VSEARCH: Rognes T, Flouri T, Nichols B, Quince C, Mahé F. (2016) PeerJ 4:e2584. [Project page](https://github.com/torognes/vsearch)
- CRABS: Jeunen G-J, Dowle E, Edgecombe J, von Ammon U, Gemmell NJ, Cross H. (2022) Molecular Ecology Resources. doi:10.1111/1755-0998.13741. [Docs](https://github.com/GenomicsAotearoa/crabs)
- ANML primers: [REFERENCE FOR PRIMERS HERE]

