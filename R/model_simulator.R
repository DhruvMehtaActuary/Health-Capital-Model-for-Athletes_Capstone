# Daily Euler-Maruyama jump-diffusion DGP. Latent truth is retained solely for validation.
source_if_needed <- function() { invisible(NULL) }

make_fixture_calendar <- function(days, start_date = as.Date("2026-01-01"), seed = 1L) {
  set.seed(seed); match <- rep(FALSE, days); day <- sample(3:7, 1)
  while (day <= days) { match[day] <- TRUE; day <- day + sample(c(3:6, 7:12), 1, prob = c(rep(1,4), rep(0.65,6))) }
  last <- cummax(ifelse(match, seq_len(days), 0)); since <- ifelse(last == 0, 14, seq_len(days) - last)
  data.frame(date = start_date + seq_len(days) - 1, match_day = match, days_since_match = since,
    matches_trailing_14 = vapply(seq_len(days), function(i) sum(match[pmax(1,i-13):i]), numeric(1)))
}

team_factor <- function(calendar) {
  # Deterministic one-factor portfolio covariate: congestion drives shared risk.
  scale(calendar$matches_trailing_14) + ifelse(calendar$days_since_match <= 2, 0.35, 0)
}

simulate_forcing <- function(calendar, player_effect, cfg) {
  n <- nrow(calendar); e1 <- as.numeric(arima.sim(list(ar = .65), n = n, sd = .30)); e2 <- as.numeric(arima.sim(list(ar = .55), n = n, sd = .28))
  w <- pmax(0, 0.30 + 1.35 * calendar$match_day + .18 * calendar$matches_trailing_14 + player_effect + e1)
  r <- pmax(0, 0.70 - .35 * calendar$match_day - .12 * calendar$matches_trailing_14 - .14 * e1 + e2)
  data.frame(w_true = w, r_true = r)
}

simulate_observables <- function(w, r, state, calendar, age, prior, cfg) {
  n <- length(w); match <- calendar$match_day
  data.frame(training_minutes = round(pmax(20, 70 + 35*w + rnorm(n,0,18))),
    match_minutes = ifelse(match, round(pmax(0, 45 + 50*w + rnorm(n,0,15))), 0),
    overs_bowled = ifelse(match, round(pmax(0, 3 + 4.5*w + rnorm(n,0,1)),1), round(pmax(0, .8*w + rnorm(n,0,.4)),1)),
    high_intensity_distance = round(pmax(0, 250 + 500*w + rnorm(n,0,120))),
    sprint_count = round(pmax(0, 6 + 11*w + rnorm(n,0,4))),
    bowling_speed = pmax(110, 132 + 2*w - .7*state[,"F"] + rnorm(n,0,3)),
    session_rpe = clip(round(4 + 2.2*w + .5*state[,"F"] + rnorm(n,0,1), 1), 1, 10),
    sleep_hours = clip(7.5 + .40*r - .35*state[,"F"] + rnorm(n,0,.55), 3.5, 11),
    wellness_score = clip(round(6.5 + .9*r - .55*state[,"F"] + .4*state[,"R"] + rnorm(n,0,1),1),1,10),
    muscle_soreness = clip(round(2.2 + .6*state[,"F"] + .35*state[,"D"] + rnorm(n,0,.6),1),1,5),
    recovery_score = clip(round(60 + 12*r + 6*state[,"R"] - 7*state[,"F"] + rnorm(n,0,8)),0,100),
    rest_days = calendar$days_since_match,
    age = age, prior_injury = as.integer(prior), pitch_hardness = 0, travel_tier = 0, heat_index = 0)
}

simulate_season <- function(n_players = hcf_config()$squad_size, days = hcf_config()$season_days, cfg = hcf_config(), seed = cfg$seed) {
  set.seed(seed); calendar <- make_fixture_calendar(days, seed = seed); calendar$z_team <- as.numeric(team_factor(calendar))
  profiles <- data.frame(player_id = sprintf("FB%02d", seq_len(n_players)), player_name = paste("Fast Bowler", seq_len(n_players)),
    age = round(clip(rnorm(n_players, 27, 4),18,38)), prior_injury = rbinom(n_players,1,.42), experience_years = pmax(0,round(rnorm(n_players,7,3))))
  rows <- vector("list", n_players)
  for (p in seq_len(n_players)) {
    prof <- profiles[p,]; forcing <- simulate_forcing(calendar, rnorm(1,0,.18), cfg)
    st <- matrix(NA_real_, days, 4, dimnames=list(NULL,c("S","F","R","D"))); st[1,] <- c(rnorm(1,0,.2), rnorm(1,0,.15), rnorm(1,0,.2), runif(1,0,.1))
    jumps <- numeric(days)
    for (t in 2:days) {
      prev <- st[t-1,]; jn <- rpois(1, pmax(0, cfg$jump_lambda_0 + cfg$jump_lambda_workload*forcing$w_true[t] + cfg$jump_lambda_team*calendar$z_team[t]))
      jumps[t] <- if (jn) -sum(rexp(jn, rate=1/cfg$jump_mean)) else 0
      F <- prev["F"] + (-cfg$kappa_F*prev["F"] + cfg$alpha_F*forcing$w_true[t]) + cfg$sigma_F*rnorm(1)
      R <- prev["R"] + (cfg$kappa_R*(cfg$baseline_R-prev["R"]) + cfg$alpha_R*forcing$r_true[t] - cfg$beta_R*prev["F"]) + cfg$sigma_R*rnorm(1)
      D <- max(0, prev["D"] + cfg$gamma_D*max(0,prev["F"]-prev["R"]) - cfg$delta_D*prev["D"])
      S <- prev["S"] + cfg$kappa_S*(cfg$baseline_S-prev["S"]) - cfg$lambda_S*prev["D"] + cfg$sigma_S*rnorm(1) + jumps[t]
      st[t,] <- c(S,F,R,D)
    }
    obs <- simulate_observables(forcing$w_true, forcing$r_true, st, calendar, prof$age, prof$prior_injury, cfg)
    rows[[p]] <- cbind(data.frame(player_id=prof$player_id, player_name=prof$player_name, date=calendar$date, z_team=calendar$z_team,
      match_day=calendar$match_day, w_true=forcing$w_true, r_true=forcing$r_true, jump=jumps, S=st[,"S"],F=st[,"F"],R=st[,"R"],D=st[,"D"]),obs)
  }
  # Convert at the data-layer boundary: downstream code intentionally uses standard data-frame indexing.
  panel <- as.data.frame(data.table::rbindlist(rows))
  state_ref <- cfg$state_reference
  health_ref <- reference_distribution(panel[, c("S", "F", "R", "D")])
  zz <- state_risk_z(as.matrix(panel[,c("S","F","R","D")]), state_ref, cfg$hazard_z_limit)
  lin <- cfg$theta_S*zz[,1]+cfg$theta_F*zz[,2]+cfg$theta_R*zz[,3]+cfg$theta_D*zz[,4]+cfg$theta_age*age_risk_z(panel$age,cfg)+cfg$theta_hist*panel$prior_injury
  panel$hazard_true <- 1-exp(-cfg$injury_lambda_0*exp(lin)); panel$injury_event <- rbinom(nrow(panel),1,panel$hazard_true)
  excess <- pmax(0, lin - stats::quantile(lin,.75)); panel$severity_tier <- ifelse(panel$injury_event==0, NA_character_, ifelse(excess<.4,"mild",ifelse(excess<1,"moderate","severe")))
  med <- c(mild=7,moderate=21,severe=60)
  panel$days_out <- 0L
  injured <- panel$injury_event == 1
  panel$days_out[injured] <- round(rlnorm(sum(injured), log(med[panel$severity_tier[injured]]), .35))
  panel$health_score_true <- health_score(panel[,c("S","F","R","D")],panel[,c("S","F","R","D")],cfg)
  list(panel = as.data.frame(panel), profiles = profiles, calendar = calendar,
    reference = state_ref, health_reference = health_ref, config = cfg)
}
