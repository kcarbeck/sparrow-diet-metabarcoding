# katherine carbeck
# dada2 denoising


##############################################################################
#*                FILE PATHS (UPDATE THESE ACCORDINGLY)
##############################################################################
WORK_DIR=/lustre2/home/lc736_0001/song_sparrow/Mandarte_diet
outdir_2024=$WORK_DIR/Mandarte_diet_2024
outdir_2025=$WORK_DIR/Mandarte_diet_2025


##############################################################################
#*                DADA2 denoising
##############################################################################
#DADA2 denoising models run-specific, quality-score–dependent sequencing errors to statistically infer the true biological sequences in your samples (ASVs). It de-replicates reads, learns an error model, and tests whether each unique read could be an error of a more abundant one—if not, it’s retained as its own ASV. During denoising it also merges paired-end reads (using overlap) and removes chimeras. because error profiles differ by run, denoise each sequencing run separately in qiime2, then merge the resulting feature tables/rep-seqs afterward.

# suggested params:
# expected overlap ≈ truncF + truncR − insert ≈ 130 + 130 − 181 (average insert size from previous step) = 79 bp (plenty).
# our ANML amplicon is ~180 bp between our primers. Our goal overlap is ~50bp. 
# --p-min-overlap 20 gives headroom if you ever need to trim a bit shorter for quality (we can bump this up if we want to me more conservative)
#NOTE: if forward-favored and R2 is weaker can adjust to something like 140/110 (250-180=70bp). 

## UPDATE!!: Update threads if you run the following two commands simultaneously AND add to the end of the command: "&"

# 2024
qiime dada2 denoise-paired \
  --i-demultiplexed-seqs $outdir_2024/trimmed_plate1_2024.qza \
  --p-trunc-len-f 130 \
  --p-trunc-len-r 130 \
  --p-trim-left-f 0 \
  --p-trim-left-r 0 \
  --p-min-overlap 20 \
  --p-n-threads 22 \
  --o-representative-sequences $outdir_2024/rep-seqs_plate1_2024.qza \
  --o-table $outdir_2024/table_plate1_2024.qza \
  --o-denoising-stats $outdir_2024/denoise_plate1_2024.qza

# 2025
qiime dada2 denoise-paired \
  --i-demultiplexed-seqs $outdir_2025/trimmed_plate1_2025.qza \
  --p-trunc-len-f 130 \
  --p-trunc-len-r 130 \
  --p-trim-left-f 0 \
  --p-trim-left-r 0 \
  --p-min-overlap 20 \
  --p-n-threads 22 \
  --o-representative-sequences $outdir_2025/rep-seqs_plate1_2025.qza \
  --o-table $outdir_2025/table_plate1_2025.qza \
  --o-denoising-stats $outdir_2025/denoise_plate1_2025.qza

##############################################################################
#*                visualize denoising results
##############################################################################

####----------------------       2024         ----------------------------####

# metadata on denoising
qiime metadata tabulate \
  --m-input-file $outdir_2024/denoise_plate1_2024.qza \
  --o-visualization $outdir_2024/denoise_plate1_2024.qzv
# look at denoise_plate1_2024.qzv to see how many seqs passed the cutoff for each sample at each step of the denoising process. 

# first, load *your* metadata file - this should fail if it's in an invalid format
qiime metadata tabulate \
  --m-input-file $outdir_2024/metadata_2024.txt \
  --o-visualization $outdir_2024/metadata_2024.qzv

# then, make atable of per-sample sequence counts
qiime feature-table summarize \
  --i-table $outdir_2024/table_plate1_2024.qza \
  --m-sample-metadata-file $outdir_2024/metadata_2024.txt \
  --o-visualization $outdir_2024/table_plate1_2024.qzv

# unique sequences accross samples
qiime feature-table tabulate-seqs\
   --i-data $outdir_2024/rep-seqs_plate1_2024.qza\
   --o-visualization $outdir_2024/rep-seqs_plate1_2024.qzv
# see sequences and the distribution of seq lengths. should center near your target amplicon length (180 bp). each seq should be a link to blast against ncbi

####----------------------       2025         ----------------------------####

# metadata on denoising
qiime metadata tabulate \
  --m-input-file $outdir_2025/denoise_plate1_2025.qza \
  --o-visualization $outdir_2025/denoise_plate1_2025.qzv
# look at denoise_plate1_2025.qzv to see how many seqs passed the cutoff for each sample at each step of the denoising process. 

# first, load *your* metadata file - this should fail if it's in an invalid format
qiime metadata tabulate \
  --m-input-file $outdir_2025/metadata_2025.txt \
  --o-visualization $outdir_2025/metadata_2025.qzv

# then, make atable of per-sample sequence counts
qiime feature-table summarize \
  --i-table $outdir_2025/table_plate1_2025.qza \
  --m-sample-metadata-file $outdir_2025/metadata_2025.txt \
  --o-visualization $outdir_2025/table_plate1_2025.qzv

# unique sequences accross samples
qiime feature-table tabulate-seqs\
   --i-data $outdir_2025/rep-seqs_plate1_2025.qza\
   --o-visualization $outdir_2025/rep-seqs_plate1_2025.qzv
# see sequences and the distribution of seq lengths. should center near your target amplicon length (180 bp). each seq should be a link to blast against ncbi
