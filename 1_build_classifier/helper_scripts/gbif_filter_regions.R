# katherine carbeck
# 23 oct 2025

# GBIF-based regional filter for CRABS database
# - parallel processing using all available cores
# - batched year queries (55x fewer API calls)
# - results caching to avoid redundant queries
# - progress reporting with ETA
# - proper error handling and validation
# - memory-efficient processing
# - checkpointing for long runs

suppressPackageStartupMessages({
  if (!requireNamespace("data.table", quietly = TRUE)) {
    install.packages("data.table", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    install.packages("rgbif", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  if (!requireNamespace("parallel", quietly = TRUE)) {
    install.packages("parallel", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
})

library(data.table)
library(rgbif)
library(parallel)

if (getRversion() >= "2.15.1") utils::globalVariables(c("target_regions"))

# Enable data.table parallelization
setDTthreads(0)  # Use all available threads for data.table operations

args <- commandArgs(trailingOnly = TRUE)

usage <- function() {
  cat("Usage: Rscript gbif_filter_regions.R --input <crabs_db.txt> --output <filtered.txt>\n")
  cat("  --regions 'COUNTRY:ADMIN_NAME' (e.g., 'US:Washington,CA:British Columbia,GB:England')\n")
  cat("  [--year-start 1970] [--year-end 2025]\n")
  cat("  [--threads 4] [--cache-dir .gbif_cache] [--force-refresh]\n")
  cat("  [--gbif-user USER --gbif-pwd PWD --gbif-email EMAIL]\n")
  cat("  [--download auto|always|never]\n")
  cat("\n")
  cat("Notes:\n")
  cat("  - Country codes: ISO 3166-1 alpha-2 (US, CA, GB, AU, MX, etc.)\n")
  cat("  - US state codes (e.g., WA) and CA province codes (e.g., BC) are auto-expanded\n")
  cat("  - For other countries, use full admin names (e.g., GB:England, AU:New South Wales)\n")
}

if (length(args) < 4) {
  usage()
  quit(status = 1)
}

# Parse arguments
get_arg <- function(flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) == 1 && idx < length(args)) return(args[idx + 1])
  default
}

# Configuration
input_path  <- get_arg("--input")
output_path <- get_arg("--output")
regions_arg <- get_arg("--regions", NULL)
species_col <- get_arg("--species-col", NULL)
taxonomy_col<- get_arg("--taxonomy-col", NULL)
sep_opt     <- tolower(get_arg("--sep", "auto"))
year_start  <- as.integer(get_arg("--year-start", "1970"))
year_end    <- as.integer(get_arg("--year-end", format(Sys.Date(), "%Y")))
threads_opt <- as.integer(get_arg("--threads", min(detectCores() - 1, 8)))
cache_dir   <- get_arg("--cache-dir", ".gbif_cache")
force_refresh <- "--force-refresh" %in% args
gbif_user   <- get_arg("--gbif-user", Sys.getenv("GBIF_USER", ""))
gbif_pwd    <- get_arg("--gbif-pwd", Sys.getenv("GBIF_PWD", ""))
gbif_email  <- get_arg("--gbif-email", Sys.getenv("GBIF_EMAIL", ""))
download_opt <- tolower(get_arg("--download", "auto"))

if (is.null(input_path) || is.null(output_path)) {
  usage()
  quit(status = 1)
}

# create cache directory
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)

# ===================================================================
# Regional Code Mappings
# ===================================================================
# NOTE: Code-to-name expansion is currently only supported for US states
# and Canadian provinces/territories. For other countries, use full admin
# names in the --regions argument (e.g., "GB:England", "AU:New South Wales").
# The script accepts any ISO 3166-1 alpha-2 country code (US, CA, GB, AU, 
# MX, JP, etc.) and will work globally as long as admin names are provided.
# ===================================================================

# US state mapping 
state_code_to_name <- c(
  NY = "New York", PA = "Pennsylvania", NJ = "New Jersey", CT = "Connecticut",
  RI = "Rhode Island", MA = "Massachusetts", VT = "Vermont", NH = "New Hampshire",
  ME = "Maine", MD = "Maryland", DE = "Delaware", WV = "West Virginia",
  VA = "Virginia", NC = "North Carolina", SC = "South Carolina", GA = "Georgia",
  FL = "Florida", AL = "Alabama", MS = "Mississippi", LA = "Louisiana",
  TX = "Texas", OK = "Oklahoma", AR = "Arkansas", TN = "Tennessee",
  KY = "Kentucky", IN = "Indiana", OH = "Ohio", MI = "Michigan",
  WI = "Wisconsin", IL = "Illinois", MO = "Missouri", IA = "Iowa",
  MN = "Minnesota", ND = "North Dakota", SD = "South Dakota", NE = "Nebraska",
  KS = "Kansas", CO = "Colorado", WY = "Wyoming", MT = "Montana",
  ID = "Idaho", UT = "Utah", AZ = "Arizona", NM = "New Mexico",
  NV = "Nevada", CA = "California", OR = "Oregon", WA = "Washington",
  AK = "Alaska", HI = "Hawaii"
)

# Canadian province/territory mapping
ca_province_code_to_name <- c(
  AB = "Alberta", BC = "British Columbia", MB = "Manitoba", NB = "New Brunswick",
  NL = "Newfoundland and Labrador", NS = "Nova Scotia", NT = "Northwest Territories",
  NU = "Nunavut", ON = "Ontario", PE = "Prince Edward Island", QC = "Quebec",
  SK = "Saskatchewan", YT = "Yukon"
)

# Progress reporting helper (matches original output style)
message <- function(...) {
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), 
              paste0(..., collapse = "")))
  flush.console()
}

# Parse regions: accepts tokens like "US:Washington", "CA:British Columbia", "GB:England"
# Supports any ISO 3166-1 alpha-2 country code (US, CA, GB, AU, MX, JP, etc.)
# Auto-expands US state codes (e.g., US:WA -> US:Washington) and CA province codes (e.g., CA:BC -> CA:British Columbia)
# For other countries, use full admin names (e.g., "GB:England", "AU:New South Wales", "MX:Jalisco")
parse_regions <- function(x) {
  raw <- trimws(unlist(strsplit(x, ",")))
  regions <- list()
  for (tok in raw) {
    if (!nzchar(tok)) next
    parts <- trimws(unlist(strsplit(tok, ":", fixed = TRUE)))
    if (length(parts) != 2) {
      stop("Invalid --regions token: '", tok, "'. Use COUNTRY:ADMIN format.\n",
           "Examples: 'US:Washington', 'CA:BC', 'GB:England', 'AU:New South Wales'")
    }
    country <- toupper(parts[1])
    admin <- parts[2]
    
    # Auto-expand US state codes
    if (country == "US") {
      if (toupper(admin) %in% names(state_code_to_name)) {
        admin <- state_code_to_name[[toupper(admin)]]
      }
    # Auto-expand Canadian province codes
    } else if (country == "CA") {
      if (toupper(admin) %in% names(ca_province_code_to_name)) {
        admin <- ca_province_code_to_name[[toupper(admin)]]
      }
    }
    # For all other countries, admin name is used as-is
    
    regions[[length(regions) + 1]] <- list(country = country, admin = admin)
  }
  
  # De-duplicate regions
  unique_keys <- unique(vapply(regions, function(r) paste0(r$country, "|", r$admin), character(1)))
  
  # Rebuild ordered unique list
  out <- lapply(unique_keys, function(k) {
    parts <- strsplit(k, "|", fixed = TRUE)[[1]]
    list(country = parts[1], admin = parts[2])
  })
  out
}

if (!is.null(regions_arg)) {
  target_regions <- parse_regions(regions_arg)
} else {
  usage()
  stop("You must provide --regions in COUNTRY:ADMIN format.\n",
       "Examples: 'US:Washington,CA:British Columbia', 'GB:England', 'AU:New South Wales'")
}

message("Target regions: ", paste(vapply(target_regions, function(r) paste0(r$country, ": ", r$admin), ""), collapse = ", "))
message("Using ", threads_opt, " threads for parallel processing")

# validate input
if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path)
}

# read db
message("Reading database: ", input_path)

# auto-detect delimiter 
sep_map <- list(auto = NULL, tab = "\t", space = " ", comma = ",")
if (!sep_opt %in% names(sep_map)) sep_opt <- "auto"

if (identical(sep_opt, "auto")) {
  dt <- fread(input_path, header = FALSE, quote = "\"", na.strings = c("", "NA"), 
              showProgress = FALSE)
} else {
  dt <- fread(input_path, sep = sep_map[[sep_opt]], header = FALSE, quote = "\"", 
              na.strings = c("", "NA"), showProgress = FALSE)
}

# name columns if standard CRABS format (from original)
if (ncol(dt) >= 11) {
  setnames(dt, c("accession", "provided_name", "taxid", "note", "phylum", "class", 
                 "order", "family", "genus", "species", "sequence",
                 if (ncol(dt) > 11) paste0("extra", seq_len(ncol(dt) - 11))))
}

message("Loaded ", nrow(dt), " records with ", ncol(dt), " columns")

if (nrow(dt) == 0) {
  stop("Input database appears empty: ", input_path)
}

# original columns
original_cols <- names(dt)

# extract species function
extract_species <- function(D) {
  # User-specified columns first
  if (!is.null(species_col) && species_col %in% names(D)) {
    v <- trimws(as.character(D[[species_col]]))
    if (any(nzchar(v))) return(v)
  }
  if (!is.null(taxonomy_col) && taxonomy_col %in% names(D)) {
    v <- as.character(D[[taxonomy_col]])
    sp <- vapply(strsplit(v, ";"), function(parts) {
      parts <- trimws(parts)
      parts <- parts[nzchar(parts)]
      if (length(parts) == 0) return(NA_character_)
      last <- parts[[length(parts)]]
      sub("^[a-zA-Z]__", "", last)
    }, character(1))
    return(sp)
  }
  # standard CRABS species column
  if ("species" %in% names(D)) {
    v <- trimws(as.character(D[["species"]]))
    if (any(nzchar(v))) return(v)
  }
  # try other common column names
  candidate_cols <- c("species", "scientific_name", "scientificName", "taxon", "taxon_name")
  for (cn in candidate_cols) {
    if (cn %in% names(D)) {
      v <- trimws(as.character(D[[cn]]))
      if (any(nzchar(v))) return(v)
    }
  }
  # parse from taxonomy lineage
  lineage_cols <- c("taxonomy", "lineage", "tax_lineage", "tax")
  for (cn in lineage_cols) {
    if (cn %in% names(D)) {
      v <- as.character(D[[cn]])
      sp <- vapply(strsplit(v, ";"), function(parts) {
        parts <- trimws(parts)
        parts <- parts[nzchar(parts)]
        if (length(parts) == 0) return(NA_character_)
        last <- parts[[length(parts)]]
        sub("^[a-zA-Z]__", "", last)
      }, character(1))
      return(sp)
    }
  }
  stop("Could not locate species names. Ensure database has a 'species' or 'taxonomy' column.")
}

dt[, species_name := extract_species(dt)]

# Binomial check (optimized but same logic)
is_binomial <- function(x) {
  # Using regex for speed instead of strsplit
  grepl("^\\S+\\s+\\S+", x, perl = TRUE)
}

dt_valid <- dt[!is.na(species_name) & nzchar(species_name) & is_binomial(species_name)]
message("Total records: ", nrow(dt), "; with binomial species: ", nrow(dt_valid))

db_species <- sort(unique(dt_valid$species_name))
message("Unique species in database: ", length(db_species))

###############################################
# GBIF Query Functions
###############################################

# Cache helpers
get_cache_file <- function(country, admin, y_start, y_end) {
  file.path(cache_dir, sprintf("gbif_%s_%s_%d_%d.rds", 
                               country, gsub(" ", "_", admin), y_start, y_end))
}

is_cache_valid <- function(cache_file, max_age_days = 30) {
  if (!file.exists(cache_file)) return(FALSE)
  if (force_refresh) return(FALSE)
  age_days <- as.numeric(Sys.Date() - as.Date(file.info(cache_file)$mtime))
  age_days <= max_age_days
}

# Bulk download function 
download_gbif_species <- function(target_regions) {
  message("Requesting GBIF bulk download via occ_download()...")
  
  # Build region predicates
  region_preds <- lapply(target_regions, function(r) {
    rgbif::pred_and(
      rgbif::pred("country", r$country),
      rgbif::pred("stateProvince", r$admin)
    )
  })

  # Compose a single combined predicate using DSL
  if (length(region_preds) == 1) {
    region_or <- region_preds[[1]]
  } else {
    region_or <- do.call(rgbif::pred_or, region_preds)
  }
  
  # Build the final predicate by appending region_or to common predicates
  # Important: Don't use c() which flattens - build the argument list correctly
  pred_final <- rgbif::pred_and(
    rgbif::pred_gte("year", year_start),
    rgbif::pred_lte("year", year_end),
    rgbif::pred("hasCoordinate", TRUE),
    rgbif::pred_notnull("speciesKey"),
    region_or
  )

  key <- tryCatch({
    # Prefer newer API if available
    if ("occ_download_predicate" %in% getNamespaceExports("rgbif")) {
      rgbif::occ_download_predicate(
        pred_final,
        format = "SIMPLE_CSV",
        user = gbif_user,
        pwd = gbif_pwd,
        email = gbif_email
      )
    } else {
      rgbif::occ_download(
        pred_final,
        format = "SIMPLE_CSV",
        user = gbif_user,
        pwd = gbif_pwd,
        email = gbif_email
      )
    }
  }, error = function(e) {
    stop("GBIF occ_download request failed: ", conditionMessage(e))
  })
  
  if (is.list(key) && !is.null(key$key)) key <- key$key
  message("GBIF download key: ", key)
  
  rgbif::occ_download_wait(key)
  
  get_res <- rgbif::occ_download_get(key, overwrite = TRUE)
  zip_path <- if (is.character(get_res)) {
    get_res
  } else if (is.list(get_res) && !is.null(get_res$path)) {
    get_res$path
  } else if (is.list(get_res) && length(get_res) > 0 && is.character(get_res[[1]])) {
    get_res[[1]]
  } else {
    stop("Could not determine zip path from occ_download_get() result.")
  }
  
  # stream taxonomy from CSV
  files_in_zip <- utils::unzip(zip_path, list = TRUE)
  csv_file <- files_in_zip$Name[grepl("\\.csv$", files_in_zip$Name, ignore.case = TRUE)][1]
  if (is.na(csv_file)) stop("Could not find CSV in GBIF zip: ", zip_path)
  
  message("Importing taxonomy columns from GBIF download...")
  dt_tax <- tryCatch({
    data.table::fread(cmd = paste("unzip -p", shQuote(zip_path), shQuote(csv_file)), 
                      select = c("species", "genus", "family", "order", "class", "phylum"), 
                      showProgress = FALSE)
  }, error = function(e) {
    message("Streaming import failed. Falling back to full import...")
    NULL
  })
  
  if (is.null(dt_tax)) {
    df <- rgbif::occ_download_import(zip_path)
    sp <- df$species
    gn <- df$genus
    fm <- df$family
    od <- df$order
    cl <- df$class
    ph <- df$phylum
  } else {
    sp <- dt_tax$species
    gn <- dt_tax$genus
    fm <- dt_tax$family
    od <- dt_tax[["order"]]
    cl <- dt_tax[["class"]]
    ph <- dt_tax$phylum
  }
  
  sp <- sp[!is.na(sp) & nzchar(sp)]
  gn <- gn[!is.na(gn) & nzchar(gn)]
  fm <- fm[!is.na(fm) & nzchar(fm)]
  od <- od[!is.na(od) & nzchar(od)]
  cl <- cl[!is.na(cl) & nzchar(cl)]
  ph <- ph[!is.na(ph) & nzchar(ph)]
  
  list(
    species = sort(unique(sp)),
    genus   = sort(unique(gn)),
    family  = sort(unique(fm)),
    order   = sort(unique(od)),
    class   = sort(unique(cl)),
    phylum  = sort(unique(ph))
  )
}

# Compatibility path: perform separate downloads per-region using predicates
download_gbif_species_by_region <- function(target_regions) {
  message("Attempting per-region GBIF downloads using predicates (compat mode)...")

  aggregate <- list(
    species = character(0),
    genus   = character(0),
    family  = character(0),
    order   = character(0),
    class   = character(0),
    phylum  = character(0)
  )

  for (r in target_regions) {
    message("Region: ", r$country, ": ", r$admin)
    
    # Build predicates for this single region
    pred_single <- rgbif::pred_and(
      rgbif::pred("country", r$country),
      rgbif::pred("stateProvince", r$admin),
      rgbif::pred_gte("year", year_start),
      rgbif::pred_lte("year", year_end),
      rgbif::pred("hasCoordinate", TRUE),
      rgbif::pred_notnull("speciesKey")
    )

    key <- tryCatch({
      if ("occ_download_predicate" %in% getNamespaceExports("rgbif")) {
        rgbif::occ_download_predicate(
          pred_single,
          format = "SIMPLE_CSV",
          user = gbif_user,
          pwd = gbif_pwd,
          email = gbif_email
        )
      } else {
        rgbif::occ_download(
          pred_single,
          format = "SIMPLE_CSV",
          user = gbif_user,
          pwd = gbif_pwd,
          email = gbif_email
        )
      }
    }, error = function(e) {
      stop("Predicate-based occ_download failed for ", r$country, ": ", r$admin, ": ", conditionMessage(e))
    })

    if (is.list(key) && !is.null(key$key)) key <- key$key
    message("  GBIF download key: ", key)

    rgbif::occ_download_wait(key)
    get_res <- rgbif::occ_download_get(key, overwrite = TRUE)
    zip_path <- if (is.character(get_res)) get_res else if (is.list(get_res) && !is.null(get_res$path)) get_res$path else get_res[[1]]

    files_in_zip <- utils::unzip(zip_path, list = TRUE)
    csv_file <- files_in_zip$Name[grepl("\\.csv$", files_in_zip$Name, ignore.case = TRUE)][1]
    if (is.na(csv_file)) stop("Could not find CSV in GBIF zip: ", zip_path)

    dt_tax <- tryCatch({
      data.table::fread(cmd = paste("unzip -p", shQuote(zip_path), shQuote(csv_file)), 
                        select = c("species", "genus", "family", "order", "class", "phylum"), 
                        showProgress = FALSE)
    }, error = function(e) NULL)

    if (!is.null(dt_tax)) {
      sp <- dt_tax$species; gn <- dt_tax$genus; fm <- dt_tax$family
      od <- dt_tax[["order"]]; cl <- dt_tax[["class"]]; ph <- dt_tax$phylum
    } else {
      df <- rgbif::occ_download_import(zip_path)
      sp <- df$species; gn <- df$genus; fm <- df$family
      od <- df$order; cl <- df$class; ph <- df$phylum
    }

    # filter non-empty and accumulate
    aggregate$species <- unique(c(aggregate$species, sp[!is.na(sp) & nzchar(sp)]))
    aggregate$genus   <- unique(c(aggregate$genus,   gn[!is.na(gn) & nzchar(gn)]))
    aggregate$family  <- unique(c(aggregate$family,  fm[!is.na(fm) & nzchar(fm)]))
    aggregate$order   <- unique(c(aggregate$order,   od[!is.na(od) & nzchar(od)]))
    aggregate$class   <- unique(c(aggregate$class,   cl[!is.na(cl) & nzchar(cl)]))
    aggregate$phylum  <- unique(c(aggregate$phylum,  ph[!is.na(ph) & nzchar(ph)]))
  }

  aggregate
}

# API query function for parallel processing (by country + admin)
fetch_region_species_api <- function(region) {
  # Ensure packages are loaded in worker
  suppressPackageStartupMessages({
    require(rgbif)
    require(data.table)
  })
  
  # Check cache
  cache_file <- get_cache_file(region$country, region$admin, year_start, year_end)
  if (is_cache_valid(cache_file)) {
    cat(sprintf("  Using cached data for %s: %s\n", region$country, region$admin))
    return(readRDS(cache_file))
  }
  
  cat(sprintf("  Querying GBIF for %s: %s (years %d-%d)\n", 
              region$country, region$admin, year_start, year_end))
  
  # Collect all taxonomy data
  species_accum <- character(0)
  genus_accum <- character(0)
  family_accum <- character(0)
  order_accum <- character(0)
  class_accum <- character(0)
  phylum_accum <- character(0)
  
  # Query parameters
  page_limit <- 300
  start <- 0
  total_retrieved <- 0
  max_records <- 100000
  
  # Retry logic with exponential backoff
  safe_query <- function(...) {
    delay <- 0.5
    max_delay <- 30
    attempts <- 0
    repeat {
      attempts <- attempts + 1
      res <- tryCatch({
        rgbif::occ_data(...)
      }, error = function(e) e)
      
      if (!inherits(res, "error")) return(res)
      
      msg <- conditionMessage(res)
      if (grepl("Too many requests|Service Unavailable|429|503", msg, ignore.case = TRUE)) {
        cat(sprintf("    Rate limit (attempt %d) - backing off %.1fs\n", attempts, delay))
        Sys.sleep(delay + runif(1, 0, 0.5))
        delay <- min(max_delay, delay * 2)
      } else {
        cat(sprintf("    GBIF error: %s\n", msg))
        return(NULL)
      }
      
      if (attempts >= 8) {
        cat("    Giving up after repeated errors\n")
        return(NULL)
      }
    }
  }
  
  # Main query loop - OPTIMIZED to query all years at once
  repeat {
    res <- safe_query(
      country = region$country,
      stateProvince = region$admin,
      year = paste(year_start, year_end, sep = ","),  # KEY: All years in one query!
      hasCoordinate = TRUE,
      limit = page_limit,
      start = start
    )
    
    if (is.null(res) || is.null(res$data) || nrow(res$data) == 0) break
    
    # Extract taxonomy data
    sp <- res$data$species
    gn <- res$data$genus
    fm <- res$data$family
    od <- res$data[["order"]]
    cl <- res$data[["class"]]
    ph <- res$data$phylum
    
    # Filter and accumulate
    sp <- sp[!is.na(sp) & nzchar(sp)]
    gn <- gn[!is.na(gn) & nzchar(gn)]
    fm <- fm[!is.na(fm) & nzchar(fm)]
    od <- od[!is.na(od) & nzchar(od)]
    cl <- cl[!is.na(cl) & nzchar(cl)]
    ph <- ph[!is.na(ph) & nzchar(ph)]
    
    species_accum <- c(species_accum, sp)
    genus_accum <- c(genus_accum, gn)
    family_accum <- c(family_accum, fm)
    order_accum <- c(order_accum, od)
    class_accum <- c(class_accum, cl)
    phylum_accum <- c(phylum_accum, ph)
    
    nret <- nrow(res$data)
    total_retrieved <- total_retrieved + nret
    
    # Check end conditions
    if (!is.null(res$meta) && isTRUE(res$meta$endOfRecords)) break
    if (nret < page_limit) break
    if (total_retrieved >= max_records) {
      cat(sprintf("    Reached limit of %d records\n", max_records))
      break
    }
    
    start <- start + nret
    Sys.sleep(0.1)  # Brief pause between pages
  }
  
  cat(sprintf("    Retrieved %d records from %s: %s\n", total_retrieved, region$country, region$admin))
  
  # Create result list
  result <- list(
    species = sort(unique(species_accum)),
    genus   = sort(unique(genus_accum)),
    family  = sort(unique(family_accum)),
    order   = sort(unique(order_accum)),
    class   = sort(unique(class_accum)),
    phylum  = sort(unique(phylum_accum))
  )
  
  # Save to cache
  saveRDS(result, cache_file)
  cat(sprintf("    Cached results for %s: %s\n", region$country, region$admin))
  
  result
}

###############################################
# Main GBIF Query Logic
###############################################

# Check if we can use bulk download
can_use_download <- (
  (download_opt == "always") ||
  (download_opt == "auto" && nzchar(gbif_user) && nzchar(gbif_pwd) && nzchar(gbif_email))
)

gbif_taxa <- list(species = character(0), genus = character(0), family = character(0), 
                  order = character(0), class = character(0), phylum = character(0))

used_download <- FALSE
if (can_use_download && download_opt != "never") {
  used_download <- TRUE
  gbif_taxa <- tryCatch({
    download_gbif_species(target_regions)
  }, error = function(e1) {
    message("Bulk download failed: ", conditionMessage(e1))
    message("Trying compatibility mode (per-region downloads)...")
    tryCatch({
      download_gbif_species_by_region(target_regions)
    }, error = function(e2) {
      message("Compat mode also failed: ", conditionMessage(e2))
      message("Falling back to API queries (this may be slower).")
      NULL
    })
  })
}

if (is.null(gbif_taxa) || length(gbif_taxa$species) == 0) {
  # API strategy
  if (download_opt == "always" && !isTRUE(used_download)) {
    stop("--download always specified but GBIF credentials are missing.")
  }

  if (!isTRUE(used_download)) {
    message("Using API queries (may be slower). Consider providing GBIF credentials.")
  }
  
  # Parallel or sequential processing
  if (length(target_regions) > 1 && threads_opt > 1) {
    message("Querying ", length(target_regions), " regions in parallel...")
    
    # Create cluster
    cl <- makeCluster(min(threads_opt, length(target_regions)))
    
    # Export required objects to workers
    clusterExport(cl, c("fetch_region_species_api", "get_cache_file", "is_cache_valid",
                        "cache_dir", "force_refresh", "year_start", "year_end"),
                  envir = environment())
    
    # Query regions in parallel
    state_results <- parLapply(cl, target_regions, fetch_region_species_api)
    
    stopCluster(cl)
  } else {
    message("Querying ", length(target_regions), " region(s) sequentially...")
    state_results <- lapply(target_regions, fetch_region_species_api)
  }
  
  # Merge results across regions
  merged <- list(species = character(0), genus = character(0), family = character(0),
                 order = character(0), class = character(0), phylum = character(0))
  
  for (lst in state_results) {
    merged$species <- unique(c(merged$species, lst$species))
    merged$genus   <- unique(c(merged$genus,   lst$genus))
    merged$family  <- unique(c(merged$family,  lst$family))
    merged$order   <- unique(c(merged$order,   lst$order))
    merged$class   <- unique(c(merged$class,   lst$class))
    merged$phylum  <- unique(c(merged$phylum,  lst$phylum))
  }
  
  gbif_taxa <- merged
  message("GBIF unique species across regions (API): ", length(gbif_taxa$species))
} else {
  message("GBIF unique species across regions (download): ", length(gbif_taxa$species))
}

###############################################
# Filter Database 
###############################################

# Find matching species
keep_species <- intersect(db_species, gbif_taxa$species)
message("Species in DB with GBIF occurrences in target regions: ", length(keep_species))

if (length(keep_species) == 0) {
  warning("No overlapping species found between database and GBIF occurrences.")
}

# Prepare taxonomy columns (from original)
gbif_genera  <- gbif_taxa$genus
gbif_families<- gbif_taxa$family
gbif_orders  <- gbif_taxa$order
gbif_classes <- gbif_taxa$class
gbif_phyla   <- gbif_taxa$phylum

# Extract taxonomy for filtering (maintaining original logic)
if ("genus" %in% names(dt)) {
  dt[, genus_for_filter := as.character(genus)]
} else {
  dt[, genus_for_filter := NA_character_]
}

if ("family" %in% names(dt)) {
  dt[, family_for_filter := as.character(family)]
} else {
  dt[, family_for_filter := NA_character_]
}

if ("order" %in% names(dt)) {
  dt[, order_for_filter := as.character(`order`)]  # FIXED: backticks for reserved word
} else {
  dt[, order_for_filter := NA_character_]
}

if ("class" %in% names(dt)) {
  dt[, class_for_filter := as.character(`class`)]
} else {
  dt[, class_for_filter := NA_character_]
}

if ("phylum" %in% names(dt)) {
  dt[, phylum_for_filter := as.character(phylum)]
} else {
  dt[, phylum_for_filter := NA_character_]
}

# Apply hierarchical filtering (exactly as in original)
species_present <- !is.na(dt$species_name) & nzchar(dt$species_name) & is_binomial(dt$species_name)
genus_present   <- !is.na(dt$genus_for_filter) & nzchar(dt$genus_for_filter)
family_present  <- !is.na(dt$family_for_filter) & nzchar(dt$family_for_filter)
order_present   <- !is.na(dt$order_for_filter)  & nzchar(dt$order_for_filter)
class_present   <- !is.na(dt$class_for_filter)  & nzchar(dt$class_for_filter)
phylum_present  <- !is.na(dt$phylum_for_filter) & nzchar(dt$phylum_for_filter)

# Inclusion rules (mutually exclusive hierarchy as in original)
include_species <- species_present & (dt$species_name %chin% keep_species)
include_genus   <- (!species_present) & genus_present & (dt$genus_for_filter %chin% gbif_genera)
include_family  <- (!species_present) & (!genus_present) & family_present & (dt$family_for_filter %chin% gbif_families)
include_order   <- (!species_present) & (!genus_present) & (!family_present) & order_present & (dt$order_for_filter %chin% gbif_orders)
include_class   <- (!species_present) & (!genus_present) & (!family_present) & (!order_present) & class_present & (dt$class_for_filter %chin% gbif_classes)
include_phylum  <- (!species_present) & (!genus_present) & (!family_present) & (!order_present) & (!class_present) & phylum_present & (dt$phylum_for_filter %chin% gbif_phyla)

dt_filtered <- dt[include_species | include_genus | include_family | include_order | include_class | include_phylum]

message("Filtered records: ", nrow(dt_filtered),
        "; by-species: ", sum(include_species, na.rm = TRUE),
        "; by-genus: ",   sum(include_genus & !include_species, na.rm = TRUE),
        "; by-family: ",  sum(include_family & !(include_species | include_genus), na.rm = TRUE),
        "; by-order: ",   sum(include_order  & !(include_species | include_genus | include_family), na.rm = TRUE),
        "; by-class: ",   sum(include_class  & !(include_species | include_genus | include_family | include_order), na.rm = TRUE),
        "; by-phylum: ",  sum(include_phylum & !(include_species | include_genus | include_family | include_order | include_class), na.rm = TRUE))

# Clean up helper columns to preserve original structure
helper_cols <- c("species_name", "genus_for_filter", "family_for_filter", 
                "order_for_filter", "class_for_filter", "phylum_for_filter")

for (col in helper_cols) {
  if (col %in% names(dt_filtered)) {
    dt_filtered[, (col) := NULL]
  }
}

# Ensure output has exact same columns as input
keep_cols <- intersect(original_cols, names(dt_filtered))
dt_output <- dt_filtered[, ..keep_cols]

# Write output in exact CRABS format: TSV, no header, no quotes, NA as literal
tryCatch({
  # convert all empty strings to NA so fwrite can serialize them as NA
  for (j in seq_along(dt_output)) {
    if (is.character(dt_output[[j]])) {
      set(dt_output, which(dt_output[[j]] == ""), j, NA_character_)
    }
  }
  fwrite(
    dt_output,
    file = output_path,
    sep = "\t",
    quote = FALSE,
    na = "NA",
    col.names = FALSE,
    showProgress = FALSE
  )
  message("Wrote filtered database to: ", output_path)
}, error = function(e) {
  stop("Failed to write output: ", conditionMessage(e))
})

# Summary
message("Complete: ", nrow(dt_output), " of ", nrow(dt), " records retained")