hcf_disclaimer <- "Decision-support tool for coaching and medical staff. Not a medical diagnosis. Does not replace clinical judgment or medical clearance."

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
clip <- function(x, lo, hi) pmin(pmax(x, lo), hi)
z_safe <- function(x, reference) (x - mean(reference, na.rm = TRUE)) / max(stats::sd(reference, na.rm = TRUE), 1e-6)

state_risk_z <- function(state, ref, limit = Inf) {
  z <- cbind(
    z_S = -(state[, "S"] - ref$S["mean"]) / ref$S["sd"],
    z_F =  (state[, "F"] - ref$F["mean"]) / ref$F["sd"],
    z_R = -(state[, "R"] - ref$R["mean"]) / ref$R["sd"],
    z_D =  (state[, "D"] - ref$D["mean"]) / ref$D["sd"]
  )
  pmax(pmin(z, limit), -limit)
}

age_risk_z <- function(age, cfg = hcf_config()) (as.numeric(age) - cfg$age_reference) / cfg$age_sd

reference_distribution <- function(states) {
  out <- lapply(c("S", "F", "R", "D"), function(v) c(mean = mean(states[[v]]), sd = max(sd(states[[v]]), 1e-6)))
  names(out) <- c("S", "F", "R", "D"); out
}

health_score <- function(states, reference_states, cfg = hcf_config()) {
  z <- sapply(c("S", "F", "R", "D"), function(v) z_safe(states[[v]], reference_states[[v]]))
  h <- cfg$h_weights["S"] * z[, "S"] - cfg$h_weights["F"] * z[, "F"] + cfg$h_weights["R"] * z[, "R"] - cfg$h_weights["D"] * z[, "D"]
  ref_z <- sapply(c("S", "F", "R", "D"), function(v) z_safe(reference_states[[v]], reference_states[[v]]))
  ref_h <- cfg$h_weights["S"]*ref_z[,"S"] - cfg$h_weights["F"]*ref_z[,"F"] + cfg$h_weights["R"]*ref_z[,"R"] - cfg$h_weights["D"]*ref_z[,"D"]
  100 * pnorm((h - mean(ref_h)) / max(sd(ref_h), 1e-6))
}
