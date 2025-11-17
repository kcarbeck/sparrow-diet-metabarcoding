# katherine carbeck
# primer trimming (single pass, anchored at 5' end of each read)
# using gene-specific ANML primers (without TruSeq tails)

##############################################################################
#*                FILE PATHS (UPDATE THESE ACCORDINGLY)
##############################################################################
WORK_DIR=/lustre2/home/lc736_0001/song_sparrow/Mandarte_diet
outdir_2024=$WORK_DIR/Mandarte_diet_2024
outdir_2025=$WORK_DIR/Mandarte_diet_2025
#make log directory
mkdir -p $outdir_2024/logs 
mkdir -p $outdir_2025/logs


##############################################################################
#*                cutadapt trimming
##############################################################################

# using anywhere flag because for some reason the primers are preceeded by different bases in different samples, which means we weren't able to trim everyhting and were getting ASVs that were too long.
#previous run:
#  --p-front-f    GGTCAACAAATCATAAAGATATTGG \
#  --p-front-r    GGWACTAATCAATTTCCAAATCC \
#  --p-adapter-f  GGATTTGGAAATTGATTAGTWCC \
#  --p-adapter-r  CCAATATCTTTATGATTTGTTGACC \

# # 2024
qiime cutadapt trim-paired \
  --i-demultiplexed-sequences $outdir_2024/trimmed_plate1_2024.qza \
  --p-anywhere-f GGTCAACAAATCATAAAGATATTGG \
  --p-anywhere-f GGATTTGGAAATTGATTAGTWCC \
  --p-anywhere-r GGWACTAATCAATTTCCAAATCC \
  --p-anywhere-r CCAATATCTTTATGATTTGTTGACC \
  --p-match-adapter-wildcards \
  --p-match-read-wildcards \
  --p-cores 11 \
  --o-trimmed-sequences $outdir_2024/trimmed_plate1_2024.qza \
  --verbose > $outdir_2024/logs/cutadapt_out_plate1_2024_anywhere.log &

# 2025
  qiime cutadapt trim-paired \
  --i-demultiplexed-sequences $outdir_2025/demux_plate1_2025.qza \
  --p-anywhere-f GGTCAACAAATCATAAAGATATTGG \
  --p-anywhere-f GGATTTGGAAATTGATTAGTWCC \
  --p-anywhere-r GGWACTAATCAATTTCCAAATCC \
  --p-anywhere-r CCAATATCTTTATGATTTGTTGACC \
  --p-match-adapter-wildcards \
  --p-match-read-wildcards \
  --p-cores 11 \
  --o-trimmed-sequences $outdir_2025/trimmed_plate1_2025.qza \
  --verbose > $outdir_2025/logs/cutadapt_out_plate1_2025.log &

# htop -u user_name

##############################################################################
#*                visualize trimming results
##############################################################################
# inspect .qzv after trimming to see where quality tapers off
# the goal is to determine how much we should truncate the reads before the paired end reads are joined. This will depend on the length of our amplicon, and the quality of the reads. Basically, we want to confirm that quality doesn't drop before 130 bp (our trunc length in the next script) and that R2 isn't much worse than F reads.
qiime demux summarize \
  --i-data $outdir_2024/trimmed_plate1_2024.qza \
  --o-visualization $outdir_2024/trimmed_plate1_2024.qzv

qiime demux summarize \
  --i-data $outdir_2025/trimmed_plate1_2025.qza \
  --o-visualization $outdir_2025/trimmed_plate1_2025.qzv

# How much of the total sequence do we need to preserve and still have a sufficient overlap to merge the paired end reads?
# How much of the poor quality sequence can we truncate before trying to merge?

# truncate 1 bp from the ends of reads to get rid of that extra base before primers..