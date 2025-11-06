# merge per-plate tables and rep-seqs
# katherine carbeck
# 31 oct 2025

#* IMPORTANT NOTE:
#* ensure that the sample names are unique across plates/years --- very important!!

##############################################################################
#*                FILE PATHS (UPDATE THESE ACCORDINGLY)
##############################################################################
WORK_DIR=/lustre2/home/lc736_0001/song_sparrow/Mandarte_diet
outdir_2024=$WORK_DIR/Mandarte_diet_2024
outdir_2025=$WORK_DIR/Mandarte_diet_2025
outdir_merged=$WORK_DIR/Mandarte_diet_merged

##############################################################################
#*                              merge !
##############################################################################
# merge feature tables
# - Use the 2025 RENAMED table here because we relabeled 2025 sample IDs
#   to be unique (via UniqueSampleID) before merging across years.
qiime feature-table merge \
  --i-tables $outdir_2024/table_plate1_2024.qza \
  --i-tables $outdir_2025/table_plate1_2025_renamed.qza \
  --o-merged-table $outdir_merged/table_merged.qza

# merge seqs
qiime feature-table merge-seqs \
  --i-data $outdir_2024/rep-seqs_plate1_2024.qza \
  --i-data $outdir_2025/rep-seqs_plate1_2025.qza \
  --o-merged-data $outdir_merged/rep-seqs_merged.qza

####----------------------        merge metadata        ----------------------------####
# make a merged metadata artifact
# NOTE on metadata files and alignment with tables:
# - 2024 uses the original per-year metadata (`metadata_2024.txt`) whose #SampleID
#   matches the 2024 table.
# - 2025 uses the REINDEXED metadata (`metadata_2025_reindexed.txt`) where
#   #SampleID has been replaced with UniqueSampleID. This matches the renamed
#   2025 table used above and ensures no overlapping sample IDs across years.
# - Do NOT use `metadata_2025_unique.txt` here; that file is only an intermediate
#   used to drive the table relabel step (it still has original #SampleID values).
# - With unique #SampleID values, overlapping columns like Year/Age/Species are
#   allowed by QIIME 2 during metadata merge.
qiime metadata merge \
  --m-metadata1-file $outdir_2024/metadata_2024.txt \
  --m-metadata2-file $outdir_2025/metadata_2025_reindexed.txt \
  --o-merged-metadata $outdir_merged/metadata_merged.qza

#inspect / validate metadata file
qiime metadata tabulate \
  --m-input-file $outdir_merged/metadata_merged.qza \
  --o-visualization $outdir_merged/metadata_merged.qzv

#export to a TSV (for tools that expect a plain file downstream)
qiime tools export \
  --input-path $outdir_merged/metadata_merged.qza \
  --output-path $outdir_merged
# ^ this should create a metadata.tsv file in the output directory


# summarize per-sample info:
qiime feature-table summarize \
  --i-table $outdir_merged/table_merged.qza \
  --m-sample-metadata-file $outdir_merged/metadata.tsv \
  --o-visualization $outdir_merged/table_merged.qzv

# make sure your merged output looks as expected, make sure all samples are present, etc