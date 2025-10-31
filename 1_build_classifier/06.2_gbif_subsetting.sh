# subset database for Mandarte Island (WA, USA + BC, Canada) using GBIF
# katherine carbeck
# 23 oct 2025

# this uses the helper script helper_scripts/gbif_filter_regions.R to retain database sequences only if the taxon occurs in GBIF within the selected regions (US: Washington, CA: British Columbia) and year range (has coordinates). For each record, matching is attempted at the most specific available rank, in order: species → genus → family → order → class → phylum. A record falls back to a broader rank only when more-specific ranks are missing (blank/NA). If a more-specific rank is present but not found in GBIF, the record is excluded and does not fall back. Species-level matches require a binomial name. “Presence in GBIF” reflects any occurrence record in GBIF under the filters; it does not imply nativeness or abundance. Using GBIF bulk download ensures full coverage; API mode may paginate and is not recommended when completeness is critical.

# paths
WORK_DIR=/lustre2/home/lc736_0001/diet/mandarte
ref_dir=$WORK_DIR/coi_database
helper_dir=$WORK_DIR/helper_scripts
log_dir=$WORK_DIR/logs

# gbif login credentials
GBIF_PWD_FILE=$helper_dir/gbif_pwd.txt
[ -f "$GBIF_PWD_FILE" ] || { echo "Missing $GBIF_PWD_FILE" >&2; exit 1; }
export GBIF_PWD="$(tr -d '\r\n' < "$GBIF_PWD_FILE")"

##############################################################################
#*                   TEST SUBSET OF DATABASE
##############################################################################
# Test with first 1000 lines
head -1000 $ref_dir/mandarte_database_20251023.txt > $ref_dir/test_input.txt

# Quick diagnostics to see how many records GBIF has in WA (US) and BC (CA)
Rscript -e "
library(rgbif)
c1 <- occ_count(country='US', stateProvince='Washington', year='2020,2025', hasCoordinate=TRUE)
c2 <- occ_count(country='CA', stateProvince='British Columbia', year='2020,2025', hasCoordinate=TRUE)
cat('GBIF has', format(c1, big.mark=','), 'occurrences for Washington (US) 2020-2025\n')
cat('GBIF has', format(c2, big.mark=','), 'occurrences for British Columbia (CA) 2020-2025\n')
"
#GBIF has 21,675,110 occurrences for Washington (US) 2020-2025
#GBIF has 19,027,990 occurrences for British Columbia (CA) 2020-2025

# Run script on test subset
Rscript $helper_dir/gbif_filter_regions.R \
  --input $ref_dir/test_input.txt \
  --output $ref_dir/test_output.txt \
  --regions "US:Washington,CA:British Columbia" \
  --year-start 2020 \
  --year-end 2025 \
  --threads 12 \
  --download always \
  --gbif-user "jenwalsh123" \
  --gbif-pwd "$GBIF_PWD" \
  --gbif-email "jlw395@cornell.edu"
# took about 30 mins
# 1) every row has exactly 11 tab-separated fields
awk -F'\t' 'NF!=11{print "bad fields on line " NR ": " NF; exit 1}' $ref_dir/test_output.txt 

# 2) no double-tabs
grep -nP '\t\t' $ref_dir/test_output.txt | head

##############################################################################
#*              GBIF FILTER FOR FULL DATABASE
##############################################################################
# Use 'time' and 'nohup' for long runs
time Rscript $helper_dir/gbif_filter_regions.R \
  --input $ref_dir/mandarte_database_20251023.txt \
  --output $ref_dir/mandarte_database_WA_BC_20251027.txt \
  --regions "US:Washington,CA:British Columbia" \
  --year-start 1970 \
  --year-end 2025 \
  --threads 12 \
  --cache-dir .gbif_cache \
  --gbif-user "jenwalsh123" \
  --gbif-pwd "$GBIF_PWD" \
  --gbif-email "jlw395@cornell.edu" \
  --download always \
  > $log_dir/gbif_filter_mandarte_20251027.log 2>&1 &
# [1]+  Done                    nohup time Rscript $helper_dir/gbif_filter_regions.R --input $ref_dir/mandarte_database_20251023.txt --output $ref_dir/mandarte_database_WA_BC_20251027.txt --regions "US:Washington,CA:British Columbia" --year-start 1970 --year-end 2025 --threads 12 --cache-dir .gbif_cache --gbif-user "jenwalsh123" --gbif-pwd "$GBIF_PWD" --gbif-email "jlw395@cornell.edu" --download always > $log_dir/gbif_filter_mandarte_20251027.log 2>&1  (wd: /lustre2/home/lc736_0001/diet/mandarte)
#(wd now: /lustre2/home/lc736_0001/diet/mandarte/logs)


# monitor progress
tail -f $log_dir/gbif_filter_mandarte_20251027.log
# took about 1 hour
# Filtered results:
# - started with 477,188 unique species globally in database
# - filtered to 9,613 species in WA+BC (2.0%)
# - retained 1.64M records (58.4%)


# poll status (safe to run anytime)
KEY=$(grep -oE 'GBIF download key: [A-Z0-9-]+' $log_dir/gbif_filter_mandarte_20251027.log | awk '{print $4}' | tail -n1)
echo "Latest GBIF key: $KEY"
Rscript -e "library(rgbif); m<-occ_download_meta('$KEY'); cat(m$status, '\n')"

# check cache size
du -sh .gbif_cache 2>/dev/null

# if status switches to SUCCEEDED but the log doesn’t advance:
# look for the downloaded zip that rgbif fetched
ls -lh *.zip 2>/dev/null || true
# or show more detail on the download record
Rscript -e "library(rgbif); m<-occ_download_meta('$KEY'); str(m)"

##############################################################################
#*                   CHECK OUTPUT
##############################################################################
# confirm row counts (original vs filtered)
wc -l $ref_dir/mandarte_database_20251023.txt $ref_dir/mandarte_database_WA_BC_20251027.txt
#   2807766 mandarte_database_20251023.txt
#   1640740 mandarte_database_WA_BC_20251027.txt

# how many unique species GBIF returned (binomials only)
awk -F'\t' '{print $10}' $ref_dir/mandarte_database_WA_BC_20251027.txt \
  | grep -E '^[^[:space:]]+ [^[:space:]]+$' | sort -u | wc -l
#9613

# see breakdown of how many rows came from each taxonomic level 
grep 'Filtered records:' -n $log_dir/gbif_filter_mandarte_20251027.log
# Filtered records: 1640740; by-species: 122126; by-genus: 240868; by-family: 1177681; by-order: 99058; by-class: 1007; by-phylum: 0

# record provenance
printf "GBIF key\t%s\nregions\tUS:Washington,CA:British Columbia\nyears\t1970–2025\n" "$KEY" > $ref_dir/mandarte_database_WA_BC_20251027.META

##############################################################################
#*                  OUTPUT FORMAT VALIDATION
##############################################################################
# The R script now writes CRABS format directly (TSV, no header, no quotes, literal NA).

# 1) every row has exactly 11 tab-separated fields
awk -F'\t' 'NF!=11{print "bad fields on line " NR ": " NF; exit 1}' $ref_dir/mandarte_database_WA_BC_20251027.txt

# 2) no double-tabs (which would imply empty fields)
grep -nP '\t\t' $ref_dir/mandarte_database_WA_BC_20251027.txt | head

head -20 $ref_dir/mandarte_database_20251023.txt
head -20 $ref_dir/mandarte_database_WA_BC_20251027.txt





