# train a naive bayes classifier for orchard fecal samples
# katherine carbeck
# 14 oct 2025

# activate qiime2 environment
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10

# paths
WORK_DIR=/lustre2/home/lc736_0001/diet/mandarte
ref_dir=$WORK_DIR/coi_database
class_dir=$WORK_DIR/classifier
log_dir=$WORK_DIR/logs

##############################################################################
#*               1. train a naive bayes classifier
##############################################################################
# validate inputs
qiime tools validate $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.qza
qiime tools validate $ref_dir/mandarte_database_WA_BC_20251027_taxonomy_derep.qza
# Result /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_WA_BC_20251027_seqs_derep.qza appears to be valid at level=max.
# Result /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_WA_BC_20251027_taxonomy_derep.qza appears to be valid at level=max.

# train a naive bayes classifier (output from super mode dereplication)
time qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.qza  \
  --i-reference-taxonomy $ref_dir/mandarte_database_WA_BC_20251027_taxonomy_derep.qza \
  --o-classifier $class_dir/nb_anml_mandarte_classifier_20251027.qza \
  --verbose 2>&1 | tee $log_dir/train_nb_classifier_mandarte_database_WA_BC_20251027.log
#/programs/miniconda3/envs/qiime2-amplicon-2024.10/lib/python3.10/site-packages/q2_feature_classifier/classifier.py:106: UserWarning: The TaxonomicClassifier artifact that results from this method was trained using scikit-learn version 1.4.2. It cannot be used with other versions of scikit-learn. (While the classifier may complete successfully, the results will be unreliable.)

# Saved TaxonomicClassifier to: lustre2/home/lc736_0001/diet/mandarte/classifier/nb_anml_mandarte_classifier_20251027.qza

