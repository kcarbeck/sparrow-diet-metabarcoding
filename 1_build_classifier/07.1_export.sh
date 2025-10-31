# export databases for specific projects
# katherine carbeck
# 11 sep 2025

# paths
WORK_DIR=/lustre2/home/lc736_0001/diet/mandarte
ref_dir=$WORK_DIR/coi_database

##############################################################################
#*        QIIME2-compatible formats: sequences and taxonomy
##############################################################################
# seqs
crabs --export \
  --input $ref_dir/mandarte_database_WA_BC_20251027.txt \
  --output $ref_dir/mandarte_database_WA_BC_20251027_seqs.fasta \
  --export-format 'qiime-fasta' &
#  Results | Written 1640740 sequences to /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_WA_BC_20251027_seqs.fasta out of 1640740 initial sequences (100.0%)


# taxonomy
crabs --export \
  --input $ref_dir/mandarte_database_WA_BC_20251027.txt \
  --output $ref_dir/mandarte_database_WA_BC_20251027_taxonomy.txt \
  --export-format 'qiime-text'
# Results | Written 1640740 sequences to /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_WA_BC_20251027_taxonomy.txt out of 1640740 initial sequences (100.0%)




