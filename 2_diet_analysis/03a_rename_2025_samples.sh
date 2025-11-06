# katherine carbeck
# quick fix: make 2025 SampleIDs unique and relabel table to match
# Why: QIIME 2 artifacts (tables) carry sample IDs internally. If two years share
# the same SampleID, merging will fail or mismatch metadata. We add a unique ID
# column for 2025, relabel the table to those IDs, and create a metadata file
# whose #SampleID matches the relabeled table.

##############################################################################
#*              activate qiime2 environment
##############################################################################

export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10

##############################################################################
#*                FILE PATHS (UPDATE THESE ACCORDINGLY)
##############################################################################
WORK_DIR=/lustre2/home/lc736_0001/song_sparrow/Mandarte_diet
outdir_2025=$WORK_DIR/Mandarte_diet_2025

##############################################################################
#*        Add UniqueSampleID and relabel 2025 feature table
##############################################################################
# Step 1: Create metadata_2025_unique.txt by appending a UniqueSampleID column.
# - Keeps original #SampleID as-is (needed to map existing table rows)
# - Adds UniqueSampleID = "2025_" + #SampleID (idempotent if already prefixed)
head $outdir_2025/metadata_2025.txt
#SampleID	Species	Year	Age	UniqueSampleID
#q2 : types	Categorical	Categorical	Categorical 	Categorical
#PCR-BLANK-1	NA	2025	NA	2025_PCR-BLANK-1
#S-908-CH	SOSP	2025	CH	2025_S-908-CH
#B-908	FBLANK	2025	NA	2025_B-908
#S-889-CH	SOSP	2025	CH	2025_S-889-CH
#S-893-CH	SOSP	2025	CH	2025_S-893-CH
#S-899-CH	SOSP	2025	CH	2025_S-899-CH
#B-708	FBLANK	2025	NA	2025_B-708
#S-708-AD	SOSP	2025	AD	2025_S-708-AD

# Step 2 (optional): Validate the new metadata
qiime metadata tabulate \
  --m-input-file $outdir_2025/metadata_2025_unique.txt \
  --o-visualization $outdir_2025/metadata_2025_unique.qzv

# Step 3: Relabel the 2025 feature table sample IDs to UniqueSampleID.
# - Uses qiime feature-table group on sample axis with mode=sum
# - One-to-one mapping preserves counts; no rows are collapsed unless IDs collide
qiime feature-table group \
  --i-table $outdir_2025/table_plate1_2025.qza \
  --m-metadata-file $outdir_2025/metadata_2025_unique.txt \
  --m-metadata-column UniqueSampleID \
  --p-axis sample \
  --p-mode sum \
  --o-grouped-table $outdir_2025/table_plate1_2025_renamed.qza

# Step 4: Create metadata_2025_reindexed.txt where #SampleID = UniqueSampleID.
# - This is the file to use when merging metadata across years and when
#   summarizing the relabeled 2025 table so headers match sample IDs in artifacts.
head $outdir_2025/metadata_2025_reindexed.txt
#SampleID	Species	Year	Age
#q2 : types	Categorical	Categorical	Categorical
#2025_PCR-BLANK-1	NA	2025	NA
#2025_S-908-CH	SOSP	2025	CH
#2025_B-908	FBLANK	2025	NA
#2025_S-889-CH	SOSP	2025	CH
#2025_S-893-CH	SOSP	2025	CH
#2025_S-899-CH	SOSP	2025	CH
#2025_B-708	FBLANK	2025	NA
#2025_S-708-AD	SOSP	2025	AD

# Step 4.1 (optional): Validate the reindexed metadata
qiime metadata tabulate \
  --m-input-file $outdir_2025/metadata_2025_reindexed.txt \
  --o-visualization $outdir_2025/metadata_2025_reindexed.qzv

