repos <- "https://cloud.r-project.org"
required <- c("shiny", "bslib", "DBI", "RSQLite", "data.table", "ggplot2", "DT", "pomp", "jsonlite", "testthat")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = repos, dependencies = TRUE)
message("Packages ready: ", paste(required, collapse = ", "))
