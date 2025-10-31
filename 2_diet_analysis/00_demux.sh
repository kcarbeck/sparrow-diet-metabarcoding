# katherine carbeck
# import and demultiplex reads
# 31 oct 2025

##############################################################################
#*              activate qiime2 environment
##############################################################################

export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
source /programs/miniconda3/bin/activate qiime2-amplicon-2024.10

##############################################################################
#*                FILE PATHS (UPDATE THESE ACCORDINGLY)
##############################################################################
#i've filled in an example here, but be sure to update these
# note: move your old 2024 files in a different directory so you don't overwrite them. We can eventually delete them, but probably want to keep them for now
WORK_DIR=/lustre2/home/lc736_0001/song_sparrow/Mandarte_diet
indir_2024=$WORK_DIR/Mandarte_diet_2024/reads
outdir_2024=$WORK_DIR/Mandarte_diet_2024
indir_2025=$WORK_DIR/Mandarte_diet_2025/reads
outdir_2025=$WORK_DIR/Mandarte_diet_2025

##############################################################################
#*               import and demultiplex reads
##############################################################################
# 2024
qiime tools import\
  --type 'SampleData[PairedEndSequencesWithQuality]'\
  --input-path $indir_2024  \
  --output-path $outdir_2024/demux_plate1_2024.qza &

# 2025
qiime tools import\
  --type 'SampleData[PairedEndSequencesWithQuality]'\
  --input-path $indir_2025  \
  --output-path $outdir_2025/demux_plate1_2025.qza 


# 2024
qiime demux summarize \
 --i-data $outdir_2024/demux_plate1_2024.qza \
 --o-visualization $outdir_2024/demux_plate1_2024.qzv &

# 2025
qiime demux summarize \
 --i-data $outdir_2025/demux_plate1_2025.qza \
 --o-visualization $outdir_2025/demux_plate1_2025.qzv


