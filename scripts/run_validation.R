source("scripts/check_project.R")
source("R/config_params.R"); source("R/model_util.R"); source("R/model_simulator.R"); source("R/model_estimation.R")
cfg <- hcf_config(); result <- simulate_then_recover(cfg, particles=300, mif_iterations=5); dir.create("outputs",showWarnings=FALSE); write.csv(result$recovery,"outputs/simulate_then_recover_report.csv",row.names=FALSE); print(result$recovery); if(!result$pass) stop("Validation failed: non-finite POMP likelihood")
