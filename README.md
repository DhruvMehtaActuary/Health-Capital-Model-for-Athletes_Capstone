# Health Capital Framework (HCF) - Model

HCF is a simulation-first R/Shiny decision-support system for professional cricket fast bowlers. It models latent structural integrity, fatigue, recovery capacity and micro-damage as a jump-diffusion, estimates state with `pomp`, and presents seven-day availability and workload scenarios.

## Install and run

1. Install R >= 4.3, then run `Rscript scripts/install_packages.R`.
2. Run `Rscript scripts/run_validation.R` (the mandatory simulate-then-recover check).
3. Run `Rscript app.R` and open the displayed local address.

The app creates `data/hcf.sqlite` automatically and can seed itself with a synthetic 15-player / 200-day season from the Admin tab.

## Structure

- `R/config_params.R`: all tunable parameters.
- `R/model_*.R`: simulator, POMP estimator and forward scenario engine; no Shiny dependency.
- `R/db.R`: source-agnostic SQLite repository.
- `R/app_*.R`: Shiny modules.
- `scripts/run_validation.R`: mandatory simulator-to-estimator recovery report.

**Decision-support tool for coaching and medical staff. Not a medical diagnosis. Does not replace clinical judgment or medical clearance.**
