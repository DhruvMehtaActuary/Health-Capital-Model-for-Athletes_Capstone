# Fast preflight check: run this once before the slower validation job.
root <- normalizePath(".")
required <- c("app.R", "R/config_params.R", "R/model_util.R", "R/model_simulator.R",
              "R/model_estimation.R", "R/model_decision.R", "R/db.R", "R/app_modules.R")
missing <- required[!file.exists(required)]
if (length(missing)) stop("Missing project files: ", paste(missing, collapse = ", "))
invisible(lapply(required, parse))
packages <- c("shiny", "bslib", "DBI", "RSQLite", "data.table", "ggplot2", "DT", "pomp", "jsonlite")
not_installed <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(not_installed)) stop("Install packages first: ", paste(not_installed, collapse = ", "))
message("Preflight passed. R code parses and all required packages are installed.")
