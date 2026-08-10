severity_draw <- function(risk_signal) { tier <- ifelse(risk_signal<.5,"mild",ifelse(risk_signal<1.2,"moderate","severe")); round(rlnorm(length(tier),log(c(mild=7,moderate=21,severe=60)[tier]),.35)) }

forward_risk <- function(state, plan, player, reference, cfg=hcf_config(), multiplier=1, paths=cfg$monte_carlo_paths, horizon=cfg$horizon_days) {
  set.seed(cfg$seed + round(multiplier*100)); x <- matrix(rep(state,each=paths),ncol=4,byrow=FALSE,dimnames=list(NULL,c("S","F","R","D"))); survival <- rep(1,paths)
  for (t in seq_len(horizon)) { row <- plan[min(t,nrow(plan)),]; w <- row$w_true %||% 0; r <- row$r_true %||% 0; zt <- row$z_team %||% 0
    jn <- rpois(paths,pmax(0,cfg$jump_lambda_0+cfg$jump_lambda_workload*w*multiplier+cfg$jump_lambda_team*zt)); x[,"S"] <- x[,"S"]+cfg$kappa_S*(cfg$baseline_S-x[,"S"])-cfg$lambda_S*x[,"D"]+cfg$sigma_S*rnorm(paths)-ifelse(jn>0,rexp(paths,1/cfg$jump_mean)*jn,0)
    x[,"F"] <- x[,"F"]+(-cfg$kappa_F*x[,"F"]+cfg$alpha_F*w*multiplier)+cfg$sigma_F*rnorm(paths); x[,"R"] <- x[,"R"]+cfg$kappa_R*(cfg$baseline_R-x[,"R"])+cfg$alpha_R*r-cfg$beta_R*x[,"F"]+cfg$sigma_R*rnorm(paths); x[,"D"] <- pmax(0,x[,"D"]+cfg$gamma_D*pmax(0,x[,"F"]-x[,"R"])-cfg$delta_D*x[,"D"])
    z <- state_risk_z(x,reference,cfg$hazard_z_limit); age_z <- age_risk_z(player$age,cfg); lam <- cfg$injury_lambda_0*exp(cfg$theta_S*z[,1]+cfg$theta_F*z[,2]+cfg$theta_R*z[,3]+cfg$theta_D*z[,4]+cfg$theta_age*age_z+cfg$theta_hist*player$prior_injury); survival <- survival*(1-(1-exp(-lam)))
  }; 1-mean(survival)
}

decision_support <- function(current_state, planned_panel, player, reference, cfg=hcf_config(), paths=cfg$monte_carlo_paths, horizon=cfg$horizon_days) {
  probs <- vapply(cfg$scenarios,function(m) forward_risk(current_state,planned_panel,player,reference,cfg,m,paths,horizon),numeric(1)); baseline <- probs["Current plan"]
  tier <- if (baseline<cfg$risk_low) "Low" else if (baseline<=cfg$risk_high) "Medium" else "High"
  list(horizon_days=horizon, baseline_probability=baseline, risk_tier=tier, scenarios=data.frame(scenario=names(probs),workload_multiplier=as.numeric(cfg$scenarios),injury_probability=as.numeric(probs)), marginal_risk_per_10pct=probs["+10% workload"]-baseline)
}
