# subset databases for mandarte sparrow diets
# katherine carbeck
# 23 oct 2025


conda activate CRABS

# workdir used for project: /lustre2/home/lc736_0001/diet/mandarte

# filter database for relevant taxa
crabs --subset \
 --input /lustre2/home/lc736_0001/diet/songbird_coi_database/processed/anml_aligned_recovered_dereplicated_filtered_011025.txt \
  --include 'Lepidoptera;Diptera;Coleoptera;Hymenoptera;Hemiptera;Orthoptera;Trichoptera;Ephemeroptera;Plecoptera;Odonata;Neuroptera;Megaloptera;Dermaptera;Thysanoptera;Araneae;Opiliones;Acari;Collembola;Protura;Diplura;Chilopoda;Diplopoda;Amphipoda;Isopoda;Decapoda;Copepoda;Mysida;Tanaidacea;Cumacea;Clitellata;Oligochaeta;Polychaeta;Hirudinea;Gastropoda;Bivalvia' \
 --output /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_20251023.txt
# /lustre2/home/lc736_0001/diet/mandarte/coi_database/mandarte_database_20251023.txt out of 3023466 initial sequences (92.87%)
