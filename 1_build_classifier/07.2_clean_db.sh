# dereplicate reference database
# katherine carbeck
# 14 oct 2025

# activate qiime2 environment
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10

# paths
WORK_DIR=/lustre2/home/lc736_0001/diet/mandarte
ref_dir=$WORK_DIR/coi_database
log_dir=$WORK_DIR/logs


##############################################################################
#*               1. import sequences and taxonomy into qiime
##############################################################################
# import sequences into qiime
qiime tools import \
  --type 'FeatureData[Sequence]' \
  --input-path $ref_dir/mandarte_database_WA_BC_20251027_seqs.fasta \
  --output-path $ref_dir/mandarte_database_WA_BC_20251027_seqs.qza 

# import taxonomy
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-format HeaderlessTSVTaxonomyFormat \
  --input-path $ref_dir/mandarte_database_WA_BC_20251027_taxonomy.txt \
  --output-path $ref_dir/mandarte_database_WA_BC_20251027_taxonomy.qza 


##############################################################################
#*               2. dereplicate using 2 methodss:
#*                       super mode & LCA 
##############################################################################
# "super" finds the LCA consensus while giving preference to majority labels and collapsing substrings into superstrings. For example, when a more specific taxonomy does not contradict a less specific taxonomy, the more specific is chosen. That is, "g__Faecalibacterium; s__prausnitzii", will be preferred over "g__Faecalibacterium; s__" 

time qiime rescript dereplicate \
  --i-sequences $ref_dir/mandarte_database_WA_BC_20251027_seqs.qza \
  --i-taxa $ref_dir/mandarte_database_WA_BC_20251027_taxonomy.qza \
  --p-mode super \
  --p-threads 22 \
  --o-dereplicated-sequences $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.qza \
  --o-dereplicated-taxa $ref_dir/mandarte_database_WA_BC_20251027_taxonomy_derep.qza \
  --verbose 2>&1 | tee $log_dir/derep_mandarte_database_WA_BC_20251027_super.log


##############################################################################
#*               2. export sequences and taxonomy to text files
##############################################################################
qiime tools peek $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.qza
# expect: type: FeatureData[Sequence]

# export to fasta
qiime tools export \
  --input-path $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.qza \
  --output-path $ref_dir
# Exported /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_WA_BC_20251027_seqs_derep.qza as DNASequencesDirectoryFormat to directory /lustre2/home/lc736_0001/diet/mandarte/coi_database
# /lustre2/home/lc736_0001/diet/mandarte/coi_database/dna-sequences.fasta

#rename
mv $ref_dir/dna-sequences.fasta $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.fasta


# make a 2 column tsv with feature-id and sequence
awk '
  BEGIN{h=""; s=""}
  /^>/{
    if(h!=""){print h "\t" s}
    h=substr($0,2); s=""
    next
  }
  {s=s $0}
  END{if(h!=""){print h "\t" s}}
' $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.fasta \
  > $ref_dir/mandarte_database_WA_BC_20251027_seqs_derep.tsv


# taxonomy file:
qiime tools export \
  --input-path $ref_dir/mandarte_database_WA_BC_20251027_taxonomy_derep.qza  \
  --output-path $ref_dir
# Exported /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_WA_BC_20251027_taxonomy_derep.qza as TSVTaxonomyDirectoryFormat to directory /lustre2/home/lc736_0001/diet/mandarte/coi_database
# /lustre2/home/lc736_0001/diet/mandarte/coi_database/taxonomy.tsv

#rename
mv $ref_dir/taxonomy.tsv $ref_dir/mandarte_database_WA_BC_20251027_taxonomy_derep.tsv


