# train a naive bayes classifier for orchard fecal samples
# katherine carbeck
# 14 oct 2025

# activate qiime2 environment (if needed)
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10

##############################################################################
#*                FILE PATHS (UPDATE THESE ACCORDINGLY)
##############################################################################
WORK_DIR=/lustre2/home/lc736_0001/song_sparrow/Mandarte_diet
outdir_2024=$WORK_DIR/Mandarte_diet_2024
outdir_2025=$WORK_DIR/Mandarte_diet_2025
outdir_merged=$WORK_DIR/Mandarte_diet_merged
classifier_dir=$WORK_DIR/classifier

##############################################################################
#*                              classify !
##############################################################################
# classify 
/usr/bin/time -v \
qiime feature-classifier classify-sklearn \
  --i-classifier $classifier_dir/nb_anml_mandarte_classifier_20251027.qza\
  --i-reads $outdir_merged/rep-seqs_merged.qza \
  --p-n-jobs 22 \
  --o-classification $classifier_dir/classified_taxonomy_20251104.qza \
  --verbose 2>&1 | tee $classifier_dir/classified_taxonomy_20251104.log


qiime metadata tabulate \
  --m-input-file $classifier_dir/classified_taxonomy_20251104.qza \
  --o-visualization $classifier_dir/classified_taxonomy_20251104.qzv

# make taxa barplot
qiime taxa barplot \
  --i-table $outdir_merged/table_merged.qza \
  --i-taxonomy $classifier_dir/classified_taxonomy_20251104.qza \
  --m-metadata-file $outdir_merged/metadata.tsv \
  --o-visualization $classifier_dir/barplot_merged_before_filtering_20251104.qzv

# look at the barplot in qiime view
#next steps: we'll evaluate the classifier on a mock community